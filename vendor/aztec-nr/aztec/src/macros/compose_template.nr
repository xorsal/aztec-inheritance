//! Injection logic for generic contract template composition.
//!
//! This module provides two things:
//!
//! 1. `inject_template_functions_to_registries(host, template_ids)`: Populates the composed
//!    registries with template FunctionDefinitions. This enables
//!    `generate_external_function_calls(host)`, `generate_external_function_self_calls_structs(host)`,
//!    and `generate_call_internal_struct(host)` to include composed functions in the host module's
//!    interface/stubs. These operations do NOT call `f.body()`, so they work cross-crate.
//!
//! 2. `get_composed_templates_quoted(template_ids)`: Returns the pre-generated Quoted code (stored
//!    by `#[contract_template(...)]`) for the `__aztec_nr_internals__` wrappers, contract library
//!    helpers, and ABI export structs. This avoids the Noir cross-crate `f.body()` limitation since
//!    the bodies were captured in the template crate.

use crate::utils::cmap::CHashMap;
use crate::macros::{
    internals_functions_generation::{external_functions_registry, internal_functions_registry},
    template_registry,
};

/// Tracks which modules have had a `ComposedStorage` synthesized. Every contract that runs through `#[aztec]` with
/// at least one storage struct gets a `ComposedStorage` emitted (with the host fields when no templates are composed,
/// or with templates' fields prepended when they are). The function-body re-emitters in
/// `internals_functions_generation/external/*.nr` and `internal.nr` consult this map to decide whether to call
/// `ComposedStorage::init` (default, when synthesis happened) or fall back to `Storage::init` (defensive default for
/// edge cases the synth doesn't cover).
pub(crate) comptime mut global MODULE_HAS_COMPOSED_STORAGE: CHashMap<Module, ()> = CHashMap::new();

/// Returns the struct name the function-body re-emitters should use for `<Name>::init(...)`. Every contract that runs
/// through `#[aztec]` and has a `#[storage]` struct gets a `ComposedStorage` synthesized (with host fields when no
/// templates are composed, or merged with template fields when they are), so we unconditionally return
/// `ComposedStorage` here. Templates' pre-captured bodies that contain `ComposedStorage::init(context)` then resolve
/// against the host's merged struct at replay time, which is exactly what the storage merge needs.
pub(crate) comptime fn storage_struct_name_for(_m: Module) -> Quoted {
    quote { ComposedStorage }
}

/// Populates the host module's composed registries with the selected templates'
/// FunctionDefinitions. This enables the interface/stub generators to include composed functions
/// without accessing function bodies (no cross-crate limitation applies here).
pub(crate) comptime fn inject_template_functions_to_registries(host: Module, template_keys: [Field]) {
    for template_key in template_keys {
        let template_module_opt = template_registry::get_template_module(template_key);
        assert(
            template_module_opt.is_some(),
            "compose: no contract template registered for one of the requested template ids",
        );

        let template_module = template_module_opt.unwrap();

        // Inject external function definitions into the host's composed registries.
        // These are used by generate_external_function_calls and generate_external_function_self_calls_structs.
        for f in external_functions_registry::get_own_private_functions(template_module) {
            external_functions_registry::add_composed_private(host, f);
        }
        for f in external_functions_registry::get_own_public_functions(template_module) {
            external_functions_registry::add_composed_public(host, f);
        }
        for f in external_functions_registry::get_own_utility_functions(template_module) {
            external_functions_registry::add_composed_utility(host, f);
        }

        // Inject internal function definitions into the host's composed registries.
        // These are used by generate_call_internal_struct.
        for f in internal_functions_registry::get_own_private_functions(template_module) {
            internal_functions_registry::add_composed_private(host, f);
        }
        for f in internal_functions_registry::get_own_public_functions(template_module) {
            internal_functions_registry::add_composed_public(host, f);
        }
    }
}

/// Returns the pre-generated Quoted code for all selected composed template functions:
/// - `functions`: all `__aztec_nr_internals__` wrappers (private, public, utility, internal) plus
///   contract library helpers referenced by them.
/// - `abi_exports`: all ABI export parameter/abi structs.
/// - `_self_call_structs`: Always empty (the host's `generate_external_function_self_calls_structs`
///   covers them via the composed registries).
///
/// Panics if any requested template id has not been registered.
pub(crate) comptime fn get_composed_templates_quoted(template_keys: [Field]) -> (Quoted, Quoted, Quoted) {
    let mut all_functions = quote {};
    let mut all_abi_exports = quote {};

    for template_key in template_keys {
        let functions_opt = template_registry::get_template_functions(template_key);
        assert(
            functions_opt.is_some(),
            "compose: no contract template functions registered for one of the requested template ids",
        );

        let abi_exports_opt = template_registry::get_template_abi_exports(template_key);
        let contract_library_methods_opt =
            template_registry::get_template_contract_library_methods(template_key);

        let functions = functions_opt.unwrap();
        let abi_exports = abi_exports_opt.unwrap_or(quote {});
        let contract_library_methods = contract_library_methods_opt.unwrap_or(quote {});

        all_functions = quote {
            $all_functions
            $contract_library_methods
            $functions
        };
        all_abi_exports = quote {
            $all_abi_exports
            $abi_exports
        };
    }

    (all_functions, all_abi_exports, quote {})
}

/// Synthesizes a `ComposedStorage<Context>` struct that contains the union of the host's storage fields and every
/// composed template's storage fields, plus its `init` impl. Composed-template fields come first (in `.compose()`
/// invocation order); the host's own fields are appended after. Same-name fields are deduplicated when their types
/// match exactly and rejected with a panic when they don't.
///
/// Called from `#[aztec]` only when at least one template is composed. The resulting Quoted is appended to the host's
/// module output alongside the existing `Storage::init` (which becomes inert; the function-body re-emitters call
/// `ComposedStorage::init` instead).
///
/// Note: the contract ABI's `StorageLayoutFields` continues to reflect only the host's own fields (emitted by
/// `#[storage]`). This is a cosmetic loss for the codegen'd TS layout, not a correctness one - composed templates'
/// runtime behavior is fully preserved because function bodies access fields through `self.storage.<name>`, which
/// resolves against the merged `ComposedStorage`.
pub(crate) comptime fn generate_composed_storage_quoted(host: Module, template_keys: [Field]) -> Quoted {
    // Helper: find the #[storage]-tagged struct in a module, panicking if absent.
    let find_storage_struct = |m: Module, label: Quoted| -> TypeDefinition {
        let candidates = m.structs().filter(|s: TypeDefinition| {
            s.has_named_attribute("storage") | s.has_named_attribute("storage_no_init")
        });
        if candidates.len() == 0 {
            panic(f"compose: {label} has no #[storage] struct - cannot merge into ComposedStorage")
        }
        candidates[0]
    };

    let mut merged_names: [Quoted] = &[];
    let mut merged_pairs: [(Quoted, Type)] = &[];

    // Compares two Types by their source-text representation. Type equality (`==`) considers the type variables
    // they carry, so `PublicMutable<AztecAddress, Context>` from ownable's struct and the textually-identical type
    // from upgradable's struct compare unequal because each carries a different `Context` binding. Comparing the
    // string form ignores that and matches the user intent.
    let types_match = |a: Type, b: Type| -> bool {
        let qa: Quoted = f"{a}".quoted_contents();
        let qb: Quoted = f"{b}".quoted_contents();
        qa == qb
    };

    // Templates' fields first, in compose-invocation order.
    for template_key in template_keys {
        let template_module_opt = template_registry::get_template_module(template_key);
        assert(template_module_opt.is_some(), "compose: template module missing from registry");
        let template_module = template_module_opt.unwrap();
        let template_storage = find_storage_struct(template_module, quote { template });

        for field in template_storage.fields_as_written() {
            let (fname, ftyp, _) = field;
            let mut already_present = false;
            for i in 0..merged_names.len() {
                if merged_names[i] == fname {
                    let (_existing_name, existing_typ) = merged_pairs[i];
                    if !types_match(existing_typ, ftyp) {
                        panic(
                            f"compose: storage field {fname} is declared with conflicting types across composed templates",
                        )
                    }
                    already_present = true;
                }
            }
            if !already_present {
                merged_names = merged_names.push_back(fname);
                merged_pairs = merged_pairs.push_back((fname, ftyp));
            }
        }
    }

    // Host fields appended after templates. Same-name+same-type host-vs-template is treated the same as the
    // template-vs-template case: the field is deduped (the host's declaration "wins" but the slot/type is identical so
    // there is nothing to choose). This lets read-only "view" templates (e.g. the storage-export mixin) declare a field
    // they intend to read via `self.storage.<name>` so their function bodies type-check standalone, without forcing the
    // host to drop its own declaration. Type mismatch on the same name is still a hard error - silent shadowing would
    // let the host accidentally trash invariants the template relies on.
    let host_storage = find_storage_struct(host, quote { host });
    for field in host_storage.fields_as_written() {
        let (fname, ftyp, _) = field;
        let mut already_present = false;
        for i in 0..merged_names.len() {
            if merged_names[i] == fname {
                let (_existing_name, existing_typ) = merged_pairs[i];
                if !types_match(existing_typ, ftyp) {
                    panic(
                        f"compose: host storage field {fname} collides with a composed template field of the same name and a different type",
                    )
                }
                already_present = true;
            }
        }
        if !already_present {
            merged_names = merged_names.push_back(fname);
            merged_pairs = merged_pairs.push_back((fname, ftyp));
        }
    }

    // Walk the merged list and assign slots linearly, mirroring the allocator in storage.nr.
    let mut slot: u32 = 1;
    let mut struct_fields_quoted = &[];
    let mut init_fields_quoted = &[];
    let mut layout_struct_members = &[];
    let mut layout_constructors = &[];

    for pair in merged_pairs {
        let (fname, ftyp) = pair;

        let maybe_storage_size = std::meta::typ::fresh_type_variable();
        let _maybe_context = std::meta::typ::fresh_type_variable();
        if !ftyp.implements(quote { crate::state_vars::StateVariable<$maybe_storage_size, $_maybe_context> }
            .as_trait_constraint()) {
            panic(
                f"compose: storage field {fname} of type {ftyp} does not implement StateVariable and cannot live in ComposedStorage",
            )
        }
        let storage_size = maybe_storage_size.as_constant().unwrap();
        let slot_as_field = slot as Field;

        // Splice the type as source text rather than as a Type value: the Type retains its original generic
        // bindings (the user's struct's `<Context>`), so splicing it directly leaves `Context` unbound in our impl.
        // Going through `f"{ftyp}".quoted_contents()` yields the same source token stream the user wrote, where
        // `Context` rebinds to our `impl<Context> ComposedStorage<Context>` generic at name-resolution time.
        let ftyp_source = f"{ftyp}".quoted_contents();
        struct_fields_quoted = struct_fields_quoted.push_back(quote { pub $fname: $ftyp_source });
        init_fields_quoted = init_fields_quoted.push_back(
            quote { $fname: aztec::state_vars::StateVariable::<$storage_size, Context>::new(context, $slot_as_field) },
        );
        layout_struct_members =
            layout_struct_members.push_back(quote { pub $fname: aztec::state_vars::Storable });
        layout_constructors = layout_constructors.push_back(
            quote { $fname: aztec::state_vars::Storable { slot: $slot_as_field } },
        );
        slot += storage_size;
    }

    let struct_fields_q = struct_fields_quoted.join(quote {,});
    let init_fields_q = init_fields_quoted.join(quote {,});
    // Suppress the unused-binding lints since the layout machinery emit was scoped out of this iteration.
    let _ = layout_struct_members;
    let _ = layout_constructors;

    let module_name = host.name();

    let _ = module_name;
    quote {
        pub struct ComposedStorage<Context> {
            $struct_fields_q
        }

        impl<Context> ComposedStorage<Context> {
            fn init(context: Context) -> Self {
                Self {
                    $init_fields_q
                }
            }
        }
    }
}

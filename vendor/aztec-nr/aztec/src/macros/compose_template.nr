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

use crate::macros::{
    internals_functions_generation::{external_functions_registry, internal_functions_registry},
    template_registry,
};

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

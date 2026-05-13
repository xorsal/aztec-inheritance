//! Registry for internal functions that are added to the corresponding global variable when the `#[internal(...)]`
//! macro is applied. This registry is then used by the `#[aztec]` macro to transform the internal functions.
//!
//! Note that we need to use this registry approach instead of directly iterating over the functions in the `#[aztec]`
//! macro, because at that point we do not have the information about whether a given internal function is private or
//! public. We only see the internal attribute itself, not the "private" or "public" argument.

use crate::utils::cmap::CHashMap;

// Key is a contract module, value is an array of function definitions.
comptime mut global PRIVATE_INTERNAL_REGISTRY: CHashMap<Module, [FunctionDefinition]> = CHashMap::new();
comptime mut global PUBLIC_INTERNAL_REGISTRY: CHashMap<Module, [FunctionDefinition]> = CHashMap::new();

// Composed registries: internal functions injected from registered templates.
comptime mut global COMPOSED_PRIVATE_INTERNAL_REGISTRY: CHashMap<Module, [FunctionDefinition]> = CHashMap::new();
comptime mut global COMPOSED_PUBLIC_INTERNAL_REGISTRY: CHashMap<Module, [FunctionDefinition]> = CHashMap::new();

comptime fn add_to_registry(registry: &mut CHashMap<Module, [FunctionDefinition]>, f: FunctionDefinition) {
    let module = f.module();
    let current_functions = registry.get(module);
    let functions_to_insert = if current_functions.is_some() {
        current_functions.unwrap().push_back(f)
    } else {
        @[f]
    };
    registry.insert(module, functions_to_insert);
}

comptime fn add_to_composed_registry(
    registry: &mut CHashMap<Module, [FunctionDefinition]>,
    host: Module,
    f: FunctionDefinition,
) {
    let current_functions = registry.get(host);
    let functions_to_insert = if current_functions.is_some() {
        current_functions.unwrap().push_back(f)
    } else {
        @[f]
    };
    registry.insert(host, functions_to_insert);
}

pub(crate) comptime fn add_private(f: FunctionDefinition) {
    add_to_registry(&mut PRIVATE_INTERNAL_REGISTRY, f);
}

pub(crate) comptime fn add_public(f: FunctionDefinition) {
    add_to_registry(&mut PUBLIC_INTERNAL_REGISTRY, f);
}

pub(crate) comptime fn add_composed_private(host: Module, f: FunctionDefinition) {
    add_to_composed_registry(&mut COMPOSED_PRIVATE_INTERNAL_REGISTRY, host, f);
}

pub(crate) comptime fn add_composed_public(host: Module, f: FunctionDefinition) {
    add_to_composed_registry(&mut COMPOSED_PUBLIC_INTERNAL_REGISTRY, host, f);
}

/// Returns only the functions registered by the module's own `#[internal]` attributes.
/// Used by `process_functions` to avoid calling `f.body()` on cross-crate composed functions.
pub(crate) comptime fn get_own_private_functions(m: Module) -> [FunctionDefinition] {
    PRIVATE_INTERNAL_REGISTRY.get(m).unwrap_or(@[])
}

pub(crate) comptime fn get_own_public_functions(m: Module) -> [FunctionDefinition] {
    PUBLIC_INTERNAL_REGISTRY.get(m).unwrap_or(@[])
}

/// Returns all functions (own + composed). Used by `generate_call_internal_struct` where
/// `f.body()` is not needed.
pub(crate) comptime fn get_private_functions(m: Module) -> [FunctionDefinition] {
    let own = PRIVATE_INTERNAL_REGISTRY.get(m).unwrap_or(@[]);
    let composed = COMPOSED_PRIVATE_INTERNAL_REGISTRY.get(m).unwrap_or(@[]);
    own.append(composed)
}

pub(crate) comptime fn get_public_functions(m: Module) -> [FunctionDefinition] {
    let own = PUBLIC_INTERNAL_REGISTRY.get(m).unwrap_or(@[]);
    let composed = COMPOSED_PUBLIC_INTERNAL_REGISTRY.get(m).unwrap_or(@[]);
    own.append(composed)
}

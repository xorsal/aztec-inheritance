//! Registry for external functions that are added to the corresponding global variable when the `#[external(...)]`
//! macro is applied. This registry is then used by the `#[aztec]` macro to generate the functions prefixed with
//! `__aztec_nr_internals___` and the `public_dispatch` function.
//!
//! Note that we need to use this registry approach instead of directly iterating over the functions in the `#[aztec]`
//! macro, because at that point we do not have the information about whether a given external function is private or
//! public. We only see the internal attribute itself, not the "private" or "public" argument.

use crate::utils::cmap::CHashMap;

// Key is a contract module, value is an array of function definitions.
comptime mut global PRIVATE_REGISTRY: CHashMap<Module, [FunctionDefinition]> = CHashMap::new();
comptime mut global PUBLIC_REGISTRY: CHashMap<Module, [FunctionDefinition]> = CHashMap::new();
comptime mut global UTILITY_REGISTRY: CHashMap<Module, [FunctionDefinition]> = CHashMap::new();

// Composed registries: functions injected from registered templates.
comptime mut global COMPOSED_PRIVATE_REGISTRY: CHashMap<Module, [FunctionDefinition]> = CHashMap::new();
comptime mut global COMPOSED_PUBLIC_REGISTRY: CHashMap<Module, [FunctionDefinition]> = CHashMap::new();
comptime mut global COMPOSED_UTILITY_REGISTRY: CHashMap<Module, [FunctionDefinition]> = CHashMap::new();

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
    add_to_registry(&mut PRIVATE_REGISTRY, f);
}

pub(crate) comptime fn add_public(f: FunctionDefinition) {
    add_to_registry(&mut PUBLIC_REGISTRY, f);
}

pub(crate) comptime fn add_utility(f: FunctionDefinition) {
    add_to_registry(&mut UTILITY_REGISTRY, f);
}

pub(crate) comptime fn add_composed_private(host: Module, f: FunctionDefinition) {
    add_to_composed_registry(&mut COMPOSED_PRIVATE_REGISTRY, host, f);
}

pub(crate) comptime fn add_composed_public(host: Module, f: FunctionDefinition) {
    add_to_composed_registry(&mut COMPOSED_PUBLIC_REGISTRY, host, f);
}

pub(crate) comptime fn add_composed_utility(host: Module, f: FunctionDefinition) {
    add_to_composed_registry(&mut COMPOSED_UTILITY_REGISTRY, host, f);
}

/// Returns only the functions registered by the module's own `#[external]` attributes.
/// Used by `process_functions` to avoid calling `f.body()` on cross-crate composed functions.
pub(crate) comptime fn get_own_private_functions(m: Module) -> [FunctionDefinition] {
    PRIVATE_REGISTRY.get(m).unwrap_or(@[])
}

pub(crate) comptime fn get_own_public_functions(m: Module) -> [FunctionDefinition] {
    PUBLIC_REGISTRY.get(m).unwrap_or(@[])
}

pub(crate) comptime fn get_own_utility_functions(m: Module) -> [FunctionDefinition] {
    UTILITY_REGISTRY.get(m).unwrap_or(@[])
}

/// Returns all functions (own + composed). Used for interface stub generation where `f.body()` is
/// not needed.
pub(crate) comptime fn get_private_functions(m: Module) -> [FunctionDefinition] {
    let own = PRIVATE_REGISTRY.get(m).unwrap_or(@[]);
    let composed = COMPOSED_PRIVATE_REGISTRY.get(m).unwrap_or(@[]);
    own.append(composed)
}

pub(crate) comptime fn get_public_functions(m: Module) -> [FunctionDefinition] {
    let own = PUBLIC_REGISTRY.get(m).unwrap_or(@[]);
    let composed = COMPOSED_PUBLIC_REGISTRY.get(m).unwrap_or(@[]);
    own.append(composed)
}

pub(crate) comptime fn get_utility_functions(m: Module) -> [FunctionDefinition] {
    let own = UTILITY_REGISTRY.get(m).unwrap_or(@[]);
    let composed = COMPOSED_UTILITY_REGISTRY.get(m).unwrap_or(@[]);
    own.append(composed)
}

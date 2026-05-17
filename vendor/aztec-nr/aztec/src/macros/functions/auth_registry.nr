use crate::utils::cmap::CHashMap;

/// Registers the functions that have the `#[authorize_once(...)]` macro, and the parameters the macro was invoked
/// with. This is used to later inject the authorization check (see ./utils.nr -> create_authorize_once_check) via the
/// #[external("private")] or #[external("public")] macros. The `#[authorize_once(...)]` macro is not used directly to
/// inject the check because it has to be placed after context instantiation but before the function body, which only
/// the aforementioned macros can do.
pub(crate) comptime mut global AUTHORIZE_ONCE_REGISTRY: CHashMap<FunctionDefinition, (CtString, CtString)> =
    CHashMap::new();

/// Registers the functions that have the `#[only_owner]` macro. The check itself is injected later by the
/// `#[external("public")]` macro (see ./external/helpers.nr -> `create_only_owner_check`) for the same
/// "after-context-but-before-body" reason as `AUTHORIZE_ONCE_REGISTRY`. The injected check calls
/// `_assert_only_owner(self.msg_sender(), self.storage.owner.read())`. Both symbols come from
/// `aztec_ownable_mixin` once composed via `#[aztec(AztecConfig::new().compose("aztec_ownable"))]`.
pub(crate) comptime mut global ONLY_OWNER_REGISTRY: CHashMap<FunctionDefinition, ()> = CHashMap::new();

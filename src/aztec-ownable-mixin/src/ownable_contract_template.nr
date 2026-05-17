use aztec::macros::{aztec, contract_template};

/// Ownable contract template. Injects a single-owner access-control surface
/// (`get_owner`, `transfer_ownership`, `_initialize_ownable`) plus the
/// `_assert_only_owner` library helper used by the `#[only_owner]` attribute.
///
/// Hosts opt in with `#[aztec(AztecConfig::new().compose("aztec_ownable"))]`
/// and must inline `owner: PublicMutable<AztecAddress, Context>` in their own
/// `Storage<Context>` (L-4 limitation; nested storage not yet supported).
///
/// Composition note: when stacked with `aztec_upgradable`, the host inlines a
/// single shared `owner` slot and the upgradable template's auth check reads
/// the same field. Owner == upgrade admin by design.
///
/// Zero-address policy: `transfer_ownership` REJECTS `AztecAddress::zero()`.
/// Renounce is intentionally not provided in v1 because the same role gates
/// upgrades when composed with `aztec_upgradable`; bricking the upgrade path
/// silently is more dangerous than a missing feature. A dedicated
/// `renounce_ownership` may be added later with explicit confirmation.
#[contract_template("aztec_ownable")]
#[aztec]
pub contract OwnableContractTemplate {
    use aztec::{
        macros::{
            functions::{external, internal, view},
            storage::storage,
        },
        protocol::address::AztecAddress,
        state_vars::PublicMutable,
    };

    #[storage]
    struct Storage<Context> {
        owner: PublicMutable<AztecAddress, Context>,
    }

    /// Returns the current owner.
    #[external("public")]
    #[view]
    fn get_owner() -> AztecAddress {
        self.storage.owner.read()
    }

    /// Rotates ownership to `new_owner`. Caller must be the current owner.
    /// Rejects the zero address (see crate docs for rationale).
    #[external("public")]
    fn transfer_ownership(new_owner: AztecAddress) {
        _assert_only_owner(self.msg_sender(), self.storage.owner.read());
        assert(!new_owner.eq(aztec::protocol::address::AztecAddress::zero()), "new owner is zero");
        self.storage.owner.write(new_owner);
    }

    /// Initializes the owner in public storage. Call from the host
    /// constructor: `self.internal._initialize_ownable(owner);`. When also
    /// composing `aztec_upgradable`, call this once - both templates share
    /// the same `owner` slot.
    #[internal("public")]
    fn _initialize_ownable(owner: AztecAddress) {
        self.storage.owner.write(owner);
    }

    /// Gate helper used by `transfer_ownership` and by the `#[only_owner]`
    /// attribute's expansion. Callable directly from host code as well.
    #[contract_library_method]
    fn _assert_only_owner(caller: AztecAddress, current_owner: AztecAddress) {
        assert(current_owner.eq(caller), "caller is not owner");
    }
}

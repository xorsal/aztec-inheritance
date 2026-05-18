use aztec::macros::{aztec, contract_template};

/// Pausable contract template. Adds an emergency-stop surface (`pause`,
/// `unpause`, `paused`) plus an `_initialize_pausable()` internal and the
/// `_assert_not_paused` library helper hosts use to gate their own
/// functions while paused.
///
/// Composition with `aztec_ownable`: this template's `owner` slot dedupes
/// with the ownable template's via the storage merger's same-name+same-type
/// rule, so `_initialize_ownable(owner)` initializes both. When composed
/// without ownable, the host is responsible for writing a non-zero owner
/// (otherwise `pause`/`unpause` are unauthenticated).
///
/// Auth helper is named `_assert_pausable_admin` rather than `_assert_only_owner`
/// to avoid colliding with `aztec_ownable_mixin`'s identically-named library
/// method when both templates are composed into the same host. Same convention
/// `aztec_upgradable_mixin` uses with `_assert_caller_is_owner`.
#[contract_template("aztec_pausable")]
#[aztec]
pub contract PausableContractTemplate {
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
        paused: PublicMutable<bool, Context>,
    }

    /// Returns whether the contract is currently paused.
    #[external("public")]
    #[view]
    fn paused() -> bool {
        self.storage.paused.read()
    }

    /// Pauses the contract. Caller must be the owner; reverts if already paused.
    #[external("public")]
    fn pause() {
        _assert_pausable_admin(self.msg_sender(), self.storage.owner.read());
        assert(!self.storage.paused.read(), "already paused");
        self.storage.paused.write(true);
    }

    /// Unpauses the contract. Caller must be the owner; reverts if not paused.
    #[external("public")]
    fn unpause() {
        _assert_pausable_admin(self.msg_sender(), self.storage.owner.read());
        assert(self.storage.paused.read(), "not paused");
        self.storage.paused.write(false);
    }

    /// Initializes the paused flag to false. Call from the host constructor:
    /// `self.internal._initialize_pausable();`. The `owner` slot must be
    /// initialized separately (typically by `_initialize_ownable(owner)` when
    /// composed with `aztec_ownable`).
    #[internal("public")]
    fn _initialize_pausable() {
        self.storage.paused.write(false);
    }

    /// Admin gate used by `pause`/`unpause`.
    #[contract_library_method]
    fn _assert_pausable_admin(caller: AztecAddress, current_owner: AztecAddress) {
        assert(current_owner.eq(caller), "caller is not owner");
    }

    /// Host-callable guard. Place at the top of any function that should revert
    /// while paused: `_assert_not_paused(self.storage.paused.read());`.
    #[contract_library_method]
    fn _assert_not_paused(paused: bool) {
        assert(!paused, "contract is paused");
    }
}

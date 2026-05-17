// Demo host: a public counter that composes BOTH the ownable mixin AND the
// upgradable mixin.
//
// Both templates share a single `owner: PublicMutable<AztecAddress, Context>`
// storage slot -- the ownable template authors it (transfer_ownership,
// get_owner, #[only_owner] gate) and the upgradable template piggy-backs on
// the same owner for upgrade administration. The host therefore only inits
// the slot once via `_initialize_ownable`; `_initialize_upgradable` is
// intentionally NOT called (it would re-write the same slot).
//
// All upgrade administration (`update_to`, `set_update_delay`,
// `get_update_delay`) and ownership administration (`get_owner`,
// `transfer_ownership`) are injected by the composed templates.

pub mod test;

use aztec::macros::{AztecConfig, aztec};

#[aztec(AztecConfig::new().compose("aztec_ownable").compose("aztec_upgradable"))]
pub contract OwnableUpgradableCounter {
    use aztec::{
        macros::{
            functions::{external, initializer, view},
            storage::storage,
        },
        protocol::address::AztecAddress,
        state_vars::PublicMutable,
    };
    use aztec_ownable_mixin::only_owner;

    #[storage]
    struct Storage<Context> {
        // owner is contributed by both composed templates (deduped via the
        // macro's same-name+same-type rule); only host-specific state lives here.
        count: PublicMutable<u64, Context>,
    }

    #[initializer]
    #[external("public")]
    fn constructor(owner: AztecAddress) {
        // One init for the shared slot. The upgradable template's
        // _initialize_upgradable is intentionally NOT called -- both
        // templates point at the same `owner` slot.
        self.internal._initialize_ownable(owner);
        self.storage.count.write(0);
    }

    /// Anyone can bump the counter -- no ownership gate.
    #[external("public")]
    fn increment() {
        self.storage.count.write(self.storage.count.read() + 1);
    }

    /// Owner-only setter, gated by the composed `#[only_owner]` macro.
    #[external("public")]
    #[only_owner]
    fn set_count(value: u64) {
        self.storage.count.write(value);
    }

    #[external("public")]
    #[view]
    fn get_count() -> u64 {
        self.storage.count.read()
    }

    /// Version tag so tests can prove the new class is live after `update_to`.
    /// v1 returns 1; the v2 contract under the same name will return 2.
    #[external("public")]
    #[view]
    fn version() -> u64 {
        1
    }

    // =========================================================================
    // Surface injected by composition:
    //   from aztec_ownable:    get_owner, transfer_ownership, _initialize_ownable
    //   from aztec_upgradable: update_to, set_update_delay, get_update_delay
    // =========================================================================
}

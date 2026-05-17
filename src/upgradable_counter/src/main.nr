// Demo host: a public counter that composes the upgradable mixin.
//
// The developer writes ONLY the counter logic + the storage field the mixin
// needs (`owner`). All upgrade administration (`update_to`,
// `set_update_delay`, `get_update_delay`) is injected by
// `#[aztec(AztecConfig::new().compose("aztec_upgradable"))]`. The owner field
// doubles as the "owner" role expected by a future `aztec_ownable`
// composition - shared slot, single role.

pub mod test;

use aztec::macros::{AztecConfig, aztec};

#[aztec(AztecConfig::new().compose("aztec_upgradable"))]
pub contract UpgradableCounter {
    use aztec::{
        macros::{
            functions::{external, initializer, view},
            storage::storage,
        },
        protocol::address::AztecAddress,
        state_vars::PublicMutable,
    };

    #[storage]
    struct Storage<Context> {
        // Required by the composed `aztec_upgradable` template (L-4: nested
        // storage not yet supported; inline the mixin's fields). Order
        // matters: this field must stay at the same slot in upgrade targets
        // (upgradable_counter_v2) for the persisted owner to remain readable.
        owner: PublicMutable<AztecAddress, Context>,
        // Counter-specific state.
        count: PublicMutable<u64, Context>,
    }

    #[initializer]
    #[external("public")]
    fn constructor(owner: AztecAddress) {
        self.internal._initialize_upgradable(owner);
        self.storage.count.write(0);
    }

    #[external("public")]
    fn increment() {
        self.storage.count.write(self.storage.count.read() + 1);
    }

    #[external("public")]
    #[view]
    fn get_count() -> u64 {
        self.storage.count.read()
    }

    /// Returns a version tag so the test can prove the new class is now live
    /// after `update_to`. v1 returns 1; the v2 contract under the same name
    /// will return 2.
    #[external("public")]
    #[view]
    fn version() -> u64 {
        1
    }
}

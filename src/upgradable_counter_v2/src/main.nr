// Upgrade target. Same storage shape and exposed surface as upgradable_counter,
// but `version()` returns 2 and `increment()` adds 10 instead of 1. The test
// upgrades v1's class to v2's class and asserts those new behaviors appear.
//
// Storage layout MUST match upgradable_counter exactly (same field order,
// same types) so the persisted `owner` value is readable from the new class.

use aztec::macros::{AztecConfig, aztec};

#[aztec(AztecConfig::new().compose("aztec_upgradable"))]
pub contract UpgradableCounterV2 {
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
        owner: PublicMutable<AztecAddress, Context>,
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
        self.storage.count.write(self.storage.count.read() + 10);
    }

    #[external("public")]
    #[view]
    fn get_count() -> u64 {
        self.storage.count.read()
    }

    #[external("public")]
    #[view]
    fn version() -> u64 {
        2
    }
}

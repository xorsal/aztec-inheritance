// Upgrade target for ownable_upgradable_counter. Same storage layout (owner
// then count, both at slot 1 and slot 2 respectively) so the persisted owner
// remains readable after the class-id swap. version() returns 2 and
// increment() jumps by 100 instead of 1 - the TS test asserts those new
// behaviors appear after the upgrade.

use aztec::macros::{AztecConfig, aztec};

#[aztec(AztecConfig::new().compose("aztec_ownable").compose("aztec_upgradable"))]
pub contract OwnableUpgradableCounterV2 {
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
        owner: PublicMutable<AztecAddress, Context>,
        count: PublicMutable<u64, Context>,
    }

    #[initializer]
    #[external("public")]
    fn constructor(owner: AztecAddress) {
        self.internal._initialize_ownable(owner);
        self.storage.count.write(0);
    }

    #[external("public")]
    fn increment() {
        self.storage.count.write(self.storage.count.read() + 100);
    }

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

    #[external("public")]
    #[view]
    fn version() -> u64 {
        2
    }
}

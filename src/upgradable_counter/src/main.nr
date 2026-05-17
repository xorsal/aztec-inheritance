// Demo host: a public counter that composes the upgradable mixin.
//
// The developer writes ONLY counter-specific state. The `owner` slot needed by
// the composed `aztec_upgradable` template is now contributed automatically by
// the macro and merged into the synthesized `ComposedStorage` (templates first,
// host fields appended) - no more L-4 inlining boilerplate.

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
        // Counter-specific state. `owner` is contributed by aztec_upgradable
        // via the macro-synthesized ComposedStorage.
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

    #[external("public")]
    #[view]
    fn version() -> u64 {
        1
    }
}

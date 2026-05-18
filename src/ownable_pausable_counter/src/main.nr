// Demo host: a simple public counter that composes the ownable, pausable,
// and metadata mixins.
//
// All three templates contribute their `owner` slot, which dedupes to a
// single PublicMutable<AztecAddress> via the storage merger's same-name+
// same-type rule -- so one `_initialize_ownable(owner)` authenticates
// admin paths on all three templates. The host's only domain-specific
// state is `count`. `increment` gates itself with `_assert_not_paused`,
// showing the pausable library helper composing with host-authored code.

pub mod test;

use aztec::macros::{AztecConfig, aztec};

#[aztec(
    AztecConfig::new()
        .compose("aztec_ownable")
        .compose("aztec_pausable")
        .compose("aztec_metadata")
)]
pub contract OwnablePausableCounter {
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
        count: PublicMutable<u64, Context>,
    }

    #[initializer]
    #[external("public")]
    fn constructor(owner: AztecAddress, metadata: Field) {
        self.internal._initialize_ownable(owner);
        self.internal._initialize_pausable();
        self.internal._initialize_metadata(metadata);
        self.storage.count.write(0);
    }

    /// Anyone can increment, but only while the contract is not paused.
    #[external("public")]
    fn increment() {
        _assert_not_paused(self.storage.paused.read());
        self.storage.count.write(self.storage.count.read() + 1);
    }

    #[external("public")]
    #[view]
    fn get_count() -> u64 {
        self.storage.count.read()
    }

    // =========================================================================
    // Surface injected by composition:
    //   from aztec_ownable:  get_owner, transfer_ownership, _initialize_ownable
    //   from aztec_pausable: pause, unpause, paused, _initialize_pausable,
    //                        _assert_not_paused (library)
    //   from aztec_metadata: get_metadata, set_metadata, _initialize_metadata
    // =========================================================================
}

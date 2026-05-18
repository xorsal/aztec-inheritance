// Demo host: a simple public counter that composes BOTH the ownable mixin
// AND the pausable mixin.
//
// The ownable template contributes the `owner` slot plus get_owner /
// transfer_ownership; the pausable template contributes the `paused` slot
// plus pause / unpause / paused, and shares the same `owner` slot via the
// storage merger's same-name+same-type dedup (so a single
// `_initialize_ownable(owner)` covers both templates' auth).
//
// The host's only domain-specific state is `count`. `increment` gates itself
// with `_assert_not_paused`, demonstrating that the pausable library helper
// is callable from host-authored code after composition.

pub mod test;

use aztec::macros::{AztecConfig, aztec};

#[aztec(AztecConfig::new().compose("aztec_ownable").compose("aztec_pausable"))]
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
    fn constructor(owner: AztecAddress) {
        self.internal._initialize_ownable(owner);
        self.internal._initialize_pausable();
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
    // =========================================================================
}

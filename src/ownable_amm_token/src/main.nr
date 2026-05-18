// Storage-merge stress test: a host that composes TWO templates whose storage
// field sets are disjoint - the AIP-20 token mixin contributes
// name/symbol/decimals/private_balances/total_supply/public_balances/minter,
// the ownable mixin contributes owner. Neither is inlined here; the macro
// synthesizes ComposedStorage with both groups prepended in .compose() order
// before this host's own AMM state.
//
// We don't care about auth semantics for this contract - the constructor wires
// the token's minter to `self.context.this_address()` (the contract itself) and
// initializes the ownable owner separately. The point is to prove that two
// independent templates can contribute their storage to the same host without
// the host re-declaring any of it.

pub mod test;

use aztec::macros::{AztecConfig, aztec};

#[aztec(AztecConfig::new().compose("aip20_token").compose("aztec_ownable").compose("aztec_storage_export"))]
pub contract OwnableAmmToken {
    use aztec::{
        macros::{
            events::event,
            functions::{external, initializer, view},
            storage::storage,
        },
        protocol::address::AztecAddress,
        state_vars::{Map, Owned, PublicImmutable, PublicMutable, StateVariable},
    };
    use aztec_token_mixin::TokenInitParams;
    use aztec_storage_export_mixin::StorageSnapshot;
    use compressed_string::FieldCompressedString;
    use balance_set::BalanceSet;
    // FromField is required by the token functions injected via template composition.
    // It appears unused to the compiler (this host's own code does not reference it)
    // but is needed to bring the from_field trait method into scope for generated bodies.
    use aztec::protocol::traits::FromField;

    // Required by the composed token functions; signature must match the token
    // template's Transfer event exactly.
    #[event]
    struct Transfer {
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
    }

    #[storage]
    struct Storage<Context> {
        // Token storage (name/symbol/decimals/private_balances/total_supply/
        // public_balances/minter) is contributed by aip20_token.
        // `owner` is contributed by aztec_ownable.
        // Only AMM-specific state lives here.
        reserve_a: PublicMutable<u128, Context>,
        reserve_b: PublicMutable<u128, Context>,
        token_a: PublicImmutable<AztecAddress, Context>,
        token_b: PublicImmutable<AztecAddress, Context>,
        total_shares: PublicMutable<u128, Context>,
    }

    #[initializer]
    #[external("public")]
    fn constructor(
        token_a: AztecAddress,
        token_b: AztecAddress,
        name: str<31>,
        symbol: str<31>,
        decimals: u8,
        owner: AztecAddress,
    ) {
        // Two independent inits, one per composed template. The token mixin
        // writes its own storage slots (including `minter`); the ownable mixin
        // writes the `owner` slot. The merged ComposedStorage holds both.
        self.internal._initialize_token(TokenInitParams {
            name,
            symbol,
            decimals,
            minter: self.context.this_address(),
        });
        self.internal._initialize_ownable(owner);

        // Host's own initialization for AMM-specific state.
        self.storage.token_a.initialize(token_a);
        self.storage.token_b.initialize(token_b);
    }

    /// Host-authored view; exercises the host's own storage slots after merge.
    #[external("public")]
    #[view]
    fn get_reserves() -> (u128, u128) {
        (self.storage.reserve_a.read(), self.storage.reserve_b.read())
    }
}

use aztec::{
    protocol::address::AztecAddress,
    state_vars::{Map, Owned, PublicImmutable, PublicMutable},
};
use compressed_string::FieldCompressedString;
use balance_set::BalanceSet;

/// Mirror of Token::Storage. Embed as a field in the host contract's #[storage] struct.
/// Note: #[storage] does NOT support nested structs yet (L-4 in roadmap);
/// host contracts must inline these fields directly.
pub struct TokenStorage<Context> {
    pub name: PublicImmutable<FieldCompressedString, Context>,
    pub symbol: PublicImmutable<FieldCompressedString, Context>,
    pub decimals: PublicImmutable<u8, Context>,
    pub private_balances: Owned<BalanceSet<Context>, Context>,
    pub total_supply: PublicMutable<u128, Context>,
    pub public_balances: Map<AztecAddress, PublicMutable<u128, Context>, Context>,
    pub minter: PublicImmutable<AztecAddress, Context>,
}

use aztec::protocol::{address::AztecAddress, traits::{Deserialize, Serialize}};
use compressed_string::FieldCompressedString;

/// Full snapshot of a host contract's public-readable storage. The field set
/// covers the owner/upgradable mixins, the AIP-20 token mixin, and the
/// AMM-specific public fields contributed by the `ownable_amm_token` host.
///
/// Defined at the crate level so that:
///   - inside the template, `use crate::storage_snapshot::StorageSnapshot;`
///     brings it into scope for the function body's struct literal,
///   - inside the host, `use aztec_storage_export_mixin::StorageSnapshot;`
///     brings the same struct into scope under an unqualified name, which is
///     what the captured `Quoted` body (raw token text) needs at replay time.
#[derive(Deserialize, Eq, Serialize)]
pub struct StorageSnapshot {
    pub owner: AztecAddress,
    pub name: FieldCompressedString,
    pub symbol: FieldCompressedString,
    pub decimals: u8,
    pub total_supply: u128,
    pub reserve_a: u128,
    pub reserve_b: u128,
    pub token_a: AztecAddress,
    pub token_b: AztecAddress,
    pub total_shares: u128,
}

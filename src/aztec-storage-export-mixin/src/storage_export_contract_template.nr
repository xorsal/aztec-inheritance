use aztec::macros::{aztec, contract_template};

/// Storage-export contract template. Contributes a single utility function
/// `export_storage` that returns a full `StorageSnapshot` of the host's
/// public-readable storage.
///
/// Must be the LAST template in `.compose("...")` so the merged
/// `ComposedStorage<Context>` already exposes every field the snapshot reads.
///
/// The template's `#[storage]` struct redeclares each field it reads with the
/// same type the host (or an earlier template) uses. The storage merger
/// dedupes matching-type fields across templates and host, so this neither
/// forces the host to repeat anything nor allocates extra slots; it only lets
/// the body type-check when this template module is elaborated standalone.
#[contract_template("aztec_storage_export")]
#[aztec]
pub contract StorageExportContractTemplate {
    use aztec::{
        macros::{functions::external, storage::storage},
        protocol::address::AztecAddress,
        state_vars::{PublicImmutable, PublicMutable},
    };
    use compressed_string::FieldCompressedString;
    // Bring StorageSnapshot into the template's scope for the literal below.
    // The captured Quoted body references it unqualified; the host imports the
    // same type via `use aztec_storage_export_mixin::StorageSnapshot;`.
    use crate::storage_snapshot::StorageSnapshot;

    #[storage]
    struct Storage<Context> {
        owner: PublicMutable<AztecAddress, Context>,
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        total_supply: PublicMutable<u128, Context>,
        reserve_a: PublicMutable<u128, Context>,
        reserve_b: PublicMutable<u128, Context>,
        token_a: PublicImmutable<AztecAddress, Context>,
        token_b: PublicImmutable<AztecAddress, Context>,
        total_shares: PublicMutable<u128, Context>,
    }

    /// Returns a full snapshot of the host's public-readable storage.
    #[external("utility")]
    unconstrained fn export_storage() -> StorageSnapshot {
        StorageSnapshot {
            owner: self.storage.owner.read(),
            name: self.storage.name.read(),
            symbol: self.storage.symbol.read(),
            decimals: self.storage.decimals.read(),
            total_supply: self.storage.total_supply.read(),
            reserve_a: self.storage.reserve_a.read(),
            reserve_b: self.storage.reserve_b.read(),
            token_a: self.storage.token_a.read(),
            token_b: self.storage.token_b.read(),
            total_shares: self.storage.total_shares.read(),
        }
    }
}

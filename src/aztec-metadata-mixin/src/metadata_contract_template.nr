use aztec::macros::{aztec, contract_template};

/// Metadata contract template. Stores a single `Field` of opaque, host-defined
/// metadata in public storage (e.g. an IPFS hash, a version tag, a config
/// pointer). Contributes `get_metadata`, `set_metadata`, and an
/// `_initialize_metadata(value)` internal.
///
/// `set_metadata` is owner-gated through the shared `owner` slot, mirroring
/// `aztec_pausable_mixin` and `aztec_upgradable_mixin`: when composed with
/// `aztec_ownable`, the storage merger dedupes the slot and one
/// `_initialize_ownable(owner)` authenticates all admin paths. When composed
/// without ownable, the host owns the initialization of `owner`.
///
/// Auth helper is named `_assert_metadata_admin` to avoid colliding with the
/// identically-shaped helpers in `aztec_ownable_mixin` and other mixins.
#[contract_template("aztec_metadata")]
#[aztec]
pub contract MetadataContractTemplate {
    use aztec::{
        macros::{
            functions::{external, internal, view},
            storage::storage,
        },
        protocol::address::AztecAddress,
        state_vars::PublicMutable,
    };

    #[storage]
    struct Storage<Context> {
        owner: PublicMutable<AztecAddress, Context>,
        metadata: PublicMutable<Field, Context>,
    }

    /// Returns the current metadata Field.
    #[external("public")]
    #[view]
    fn get_metadata() -> Field {
        self.storage.metadata.read()
    }

    /// Overwrites the metadata Field. Caller must be the owner.
    #[external("public")]
    fn set_metadata(value: Field) {
        _assert_metadata_admin(self.msg_sender(), self.storage.owner.read());
        self.storage.metadata.write(value);
    }

    /// Initializes the metadata slot. Call from the host constructor:
    /// `self.internal._initialize_metadata(value);`. The `owner` slot must be
    /// initialized separately (typically by `_initialize_ownable(owner)` when
    /// composed with `aztec_ownable`).
    #[internal("public")]
    fn _initialize_metadata(value: Field) {
        self.storage.metadata.write(value);
    }

    /// Admin gate used by `set_metadata`.
    #[contract_library_method]
    fn _assert_metadata_admin(caller: AztecAddress, current_owner: AztecAddress) {
        assert(current_owner.eq(caller), "caller is not owner");
    }
}

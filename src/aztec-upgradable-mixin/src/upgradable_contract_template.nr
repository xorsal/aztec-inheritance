use aztec::macros::{aztec, contract_template};

/// Upgradable contract template. Injects the upgrade administration surface
/// (`update_to`, `set_update_delay`, `get_update_delay`) plus an
/// `_initialize_upgradable(owner)` internal that the host's constructor must
/// call when this template is composed alone. When also composing
/// `aztec_ownable`, hosts call `_initialize_ownable(owner)` instead; both
/// templates share the same `owner` storage slot by design (owner ==
/// upgrade admin), so initializing one suffices.
///
/// Hosts opt in with `#[aztec(AztecConfig::new().compose("aztec_upgradable"))]`
/// and must inline `owner: PublicMutable<AztecAddress, Context>` in their own
/// `Storage<Context>` (L-4 limitation; nested storage not yet supported).
/// `PublicMutable` is required so that future composition with `aztec_ownable`
/// can rotate the value via `transfer_ownership` without storage rewrites.
///
/// All function bodies use fully-qualified paths so the captured Quoted
/// resolves in the host's scope. The host crate only needs to depend on
/// `aztec` and `contract_instance_registry` in its Nargo.toml.
///
/// Note: a public `get_owner()` view is intentionally NOT provided here -
/// compose `aztec_ownable` if the host wants to expose owner as a public
/// view function. Defining it in both templates would collide at compose
/// time (no override resolution in the current PoC).
#[contract_template("aztec_upgradable")]
#[aztec]
pub contract UpgradableContractTemplate {
    use aztec::{
        macros::{
            functions::{external, internal},
            storage::storage,
        },
        protocol::{address::AztecAddress, contract_class_id::ContractClassId},
        state_vars::PublicMutable,
    };

    #[storage]
    struct Storage<Context> {
        owner: PublicMutable<AztecAddress, Context>,
    }

    /// Schedules an upgrade to a new contract class. The new class must already be
    /// published via the ContractClassRegistry (aztec.js `publishContractClass` or the
    /// implicit publish done by `Contract.deploy`).
    #[external("public")]
    fn update_to(new_class_id: ContractClassId) {
        _assert_caller_is_owner(self.msg_sender(), self.storage.owner.read());
        self.call(
            contract_instance_registry::ContractInstanceRegistry::at(
                aztec::protocol::constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            )
                .update(new_class_id),
        );
    }

    /// Changes the delay between scheduling `update_to` and the new class taking
    /// effect. The new delay itself is subject to the current delay before it
    /// takes effect (DelayedPublicMutable semantics).
    #[external("public")]
    fn set_update_delay(new_delay: u64) {
        _assert_caller_is_owner(self.msg_sender(), self.storage.owner.read());
        self.call(
            contract_instance_registry::ContractInstanceRegistry::at(
                aztec::protocol::constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            )
                .set_update_delay(new_delay),
        );
    }

    /// Current effective update delay for this contract instance.
    #[external("public")]
    fn get_update_delay() -> u64 {
        self.view(
            contract_instance_registry::ContractInstanceRegistry::at(
                aztec::protocol::constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            )
                .get_update_delay(),
        )
    }

    /// Initializes the owner in public storage. Call from the host
    /// constructor: `self.internal._initialize_upgradable(owner);`. Only call
    /// this when `aztec_upgradable` is composed without `aztec_ownable` - the
    /// ownable template's `_initialize_ownable(owner)` writes the same slot.
    #[internal("public")]
    fn _initialize_upgradable(owner: AztecAddress) {
        self.storage.owner.write(owner);
    }

    /// Restricts upgrade administration to the configured owner.
    #[contract_library_method]
    fn _assert_caller_is_owner(caller: AztecAddress, owner: AztecAddress) {
        assert(owner.eq(caller), "caller is not owner");
    }
}

use aztec::macros::{aztec, contract_template};

/// Upgradable contract template. Injects the upgrade administration surface
/// (`update_to`, `set_update_delay`, `get_update_delay`, `get_upgrade_admin`)
/// plus an `_initialize_upgradable(admin)` internal that the host's constructor
/// must call.
///
/// Hosts opt in with `#[aztec(AztecConfig::new().compose("aztec_upgradable"))]`
/// and must inline `upgrade_admin: PublicImmutable<AztecAddress, Context>` in
/// their own `Storage<Context>` (L-4 limitation; nested storage not yet
/// supported).
///
/// All function bodies use fully-qualified paths so the captured Quoted
/// resolves in the host's scope. The host crate only needs to depend on
/// `aztec` and `contract_instance_registry` in its Nargo.toml.
#[contract_template("aztec_upgradable")]
#[aztec]
pub contract UpgradableContractTemplate {
    use aztec::{
        macros::{
            functions::{external, internal, view},
            storage::storage,
        },
        protocol::{address::AztecAddress, contract_class_id::ContractClassId},
        state_vars::PublicImmutable,
    };

    #[storage]
    struct Storage<Context> {
        upgrade_admin: PublicImmutable<AztecAddress, Context>,
    }

    /// Schedules an upgrade to a new contract class. The new class must already be
    /// published via the ContractClassRegistry (aztec.js `publishContractClass` or the
    /// implicit publish done by `Contract.deploy`).
    #[external("public")]
    fn update_to(new_class_id: ContractClassId) {
        _assert_caller_is_upgrade_admin(self.msg_sender(), self.storage.upgrade_admin.read());
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
        _assert_caller_is_upgrade_admin(self.msg_sender(), self.storage.upgrade_admin.read());
        self.call(
            contract_instance_registry::ContractInstanceRegistry::at(
                aztec::protocol::constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            )
                .set_update_delay(new_delay),
        );
    }

    /// Current effective update delay for this contract instance.
    #[external("public")]
    #[view]
    fn get_update_delay() -> u64 {
        self.view(
            contract_instance_registry::ContractInstanceRegistry::at(
                aztec::protocol::constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            )
                .get_update_delay(),
        )
    }

    /// Returns the address authorized to upgrade this contract.
    #[external("public")]
    #[view]
    fn get_upgrade_admin() -> AztecAddress {
        self.storage.upgrade_admin.read()
    }

    /// Initializes the upgrade admin in public storage. Call from the host
    /// constructor: `self.internal._initialize_upgradable(admin);`.
    #[internal("public")]
    fn _initialize_upgradable(admin: AztecAddress) {
        self.storage.upgrade_admin.initialize(admin);
    }

    /// Restricts upgrade administration to the configured admin.
    #[contract_library_method]
    fn _assert_caller_is_upgrade_admin(caller: AztecAddress, admin: AztecAddress) {
        assert(admin.eq(caller), "caller is not upgrade admin");
    }
}

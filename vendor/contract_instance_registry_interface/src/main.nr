use aztec::macros::aztec;

// Vendored from aztec-packages noir-projects/noir-contracts/contracts/protocol_interface/
// contract_instance_registry_interface. Empty function bodies; sole purpose is to make
// the #[aztec] macro generate the `ContractInstanceRegistry::at(addr).update(...)` Noir
// interface that produces PublicCall stubs. The real ContractInstanceRegistry protocol
// contract has its aztec-nr macros stripped so the interface is not generated there.
#[aztec]
pub contract ContractInstanceRegistry {
    use aztec::{
        macros::functions::{external, view},
        protocol::{contract_class_id::ContractClassId, public_keys::PublicKeys},
    };

    #[external("private")]
    fn publish_for_public_execution(
        salt: Field,
        contract_class_id: ContractClassId,
        initialization_hash: Field,
        public_keys: PublicKeys,
        universal_deploy: bool,
    ) {}

    #[external("public")]
    fn update(new_contract_class_id: ContractClassId) {}

    #[external("public")]
    fn set_update_delay(new_update_delay: u64) {}

    #[external("public")]
    #[view]
    fn get_update_delay() -> u64 {
        0
    }
}

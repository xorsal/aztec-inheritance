use aztec::{
    oracle::random::random,
    protocol::{address::AztecAddress, traits::FromField},
    test::helpers::test_environment::TestEnvironment,
};
use std::test::OracleMock;
use crate::Amm;

pub unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();

    let deployer = env.create_light_account();
    let provider = env.create_light_account();

    // Placeholder token addresses for PoC (real tokens not deployed in unit tests)
    let token_a = AztecAddress::from_field(0xAAAA);
    let token_b = AztecAddress::from_field(0xBBBB);

    (env, deployer, provider, token_a, token_b)
}

pub unconstrained fn deploy_amm_token(
    env: &mut TestEnvironment,
    deployer: AztecAddress,
    token_a: AztecAddress,
    token_b: AztecAddress,
) -> AztecAddress {
    let initializer_call_interface = Amm::interface().constructor(
        token_a,
        token_b,
        "LP Token\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
        "LP\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
        18,
    );
    env.deploy("@amm_token_contract/Amm").with_public_initializer(deployer, initializer_call_interface)
}

pub unconstrained fn mock_note_randomness() {
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);
}

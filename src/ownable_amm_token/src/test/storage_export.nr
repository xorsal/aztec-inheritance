// TXE test for the storage-export mixin composed as the last template in
// `ownable_amm_token`. Proves that the snapshot returned by `export_storage()`
// observes the union of all composed templates' storage plus the host's own,
// after the constructor populates them.

use aztec::{
    protocol::{address::AztecAddress, traits::FromField},
    test::helpers::test_environment::TestEnvironment,
};
use aztec_storage_export_mixin::StorageSnapshot;
use compressed_string::FieldCompressedString;
use crate::OwnableAmmToken;

unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let deployer = env.create_light_account();
    let owner = env.create_light_account();
    let token_a = AztecAddress::from_field(0xAAAA);
    let token_b = AztecAddress::from_field(0xBBBB);

    let initializer = OwnableAmmToken::interface().constructor(
        token_a,
        token_b,
        "Ownable LP\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
        "OLP\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
        18,
        owner,
    );
    let addr = env.deploy("@ownable_amm_token/OwnableAmmToken")
        .with_public_initializer(deployer, initializer);
    (env, owner, deployer, addr)
}

#[test]
unconstrained fn export_storage_returns_full_snapshot() {
    let (env, owner, _deployer, addr) = setup();
    let host = OwnableAmmToken::at(addr);

    let snap: StorageSnapshot = env.execute_utility(host.export_storage());

    // Templates' contributions.
    assert_eq(snap.owner, owner);
    assert_eq(snap.decimals, 18);
    assert_eq(snap.total_supply, 0);
    assert_eq(
        snap.name,
        FieldCompressedString::from_string(
            "Ownable LP\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
        ),
    );
    assert_eq(
        snap.symbol,
        FieldCompressedString::from_string(
            "OLP\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
        ),
    );

    // Host-authored fields.
    assert_eq(snap.token_a, AztecAddress::from_field(0xAAAA));
    assert_eq(snap.token_b, AztecAddress::from_field(0xBBBB));
    assert_eq(snap.reserve_a, 0);
    assert_eq(snap.reserve_b, 0);
    assert_eq(snap.total_shares, 0);
}

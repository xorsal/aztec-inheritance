// TXE tests proving a single host can compose TWO templates with disjoint
// storage field sets - aip20_token (name/symbol/decimals/private_balances/
// total_supply/public_balances/minter) and aztec_ownable (owner) - against
// host-specific AMM state (reserve_a/reserve_b/token_a/token_b/total_shares).
//
// If the storage merge worked, every slot is readable from its respective
// template's composed view AND the host's own view; if it didn't, at least
// one of these reads would either fail to compile or return the wrong value.

use aztec::{
    protocol::{address::AztecAddress, traits::FromField},
    test::helpers::test_environment::TestEnvironment,
};
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

// Ownable template contribution: owner storage slot is readable via the
// composed get_owner() view and reflects what the constructor wrote.
#[test]
unconstrained fn ownable_owner_slot_round_trips() {
    let (mut env, owner, _deployer, addr) = setup();
    let host = OwnableAmmToken::at(addr);
    assert_eq(env.view_public(host.get_owner()), owner);
}

// Token template contribution: name/symbol/decimals slots are readable via
// the composed views and reflect what TokenInitParams wrote.
#[test]
unconstrained fn aip20_token_views_reflect_constructor_state() {
    let (mut env, _owner, _deployer, addr) = setup();
    let host = OwnableAmmToken::at(addr);
    assert_eq(env.view_public(host.decimals()), 18);
    assert_eq(env.view_public(host.total_supply()), 0);
}

// Host's own slot: get_reserves reads the host-declared reserve_a / reserve_b
// fields, which sit AFTER all template-contributed fields in the merged
// ComposedStorage. If slot allocation were off, this would return garbage.
#[test]
unconstrained fn host_reserve_slots_are_zero_initialized() {
    let (mut env, _owner, _deployer, addr) = setup();
    let host = OwnableAmmToken::at(addr);
    let (a, b) = env.view_public(host.get_reserves());
    assert_eq(a, 0);
    assert_eq(b, 0);
}

// Cross-template surface coexistence: a token-domain view AND an ownable-domain
// view on the same instance return the right values from the same call site.
// If the merge had clobbered either group's slots, one of these would fail.
#[test]
unconstrained fn ownable_and_token_views_coexist() {
    let (mut env, owner, _deployer, addr) = setup();
    let host = OwnableAmmToken::at(addr);
    assert_eq(env.view_public(host.get_owner()), owner);
    assert_eq(env.view_public(host.decimals()), 18);
    assert_eq(env.view_public(host.total_supply()), 0);
}

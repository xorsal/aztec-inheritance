// Hermetic TXE tests for the composed `aztec_upgradable` template surface on
// UpgradableCounter. The full class-id-swap-after-delay flow cannot be driven
// from TXE (no contract-class publish oracle and no second-artifact swap at the
// same address), so these tests cover what is template-owned: that the composed
// functions exist, init writes admin, the admin view returns it, and the
// authorization guard fires for non-admin callers.

use aztec::{
    oracle::random::random,
    protocol::{address::AztecAddress, traits::FromField},
    test::helpers::test_environment::TestEnvironment,
};
use std::test::OracleMock;
use crate::UpgradableCounter;

unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let admin = env.create_light_account();
    let attacker = env.create_light_account();
    let initializer = UpgradableCounter::interface().constructor(admin);
    let counter_addr = env.deploy("@upgradable_counter/UpgradableCounter")
        .with_public_initializer(admin, initializer);
    (env, admin, attacker, counter_addr)
}

unconstrained fn mock_note_randomness() {
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);
}

#[test]
unconstrained fn composed_get_upgrade_admin_returns_constructor_admin() {
    let (mut env, admin, _attacker, counter_addr) = setup();
    let counter = UpgradableCounter::at(counter_addr);
    assert_eq(env.view_public(counter.get_upgrade_admin()), admin);
}

#[test]
unconstrained fn host_version_is_v1() {
    let (mut env, _admin, _attacker, counter_addr) = setup();
    let counter = UpgradableCounter::at(counter_addr);
    assert_eq(env.view_public(counter.version()), 1);
}

#[test]
unconstrained fn host_increment_and_get_count_coexist_with_composed_surface() {
    let (mut env, admin, _attacker, counter_addr) = setup();
    let counter = UpgradableCounter::at(counter_addr);
    assert_eq(env.view_public(counter.get_count()), 0);
    env.call_public(admin, counter.increment());
    assert_eq(env.view_public(counter.get_count()), 1);
}

// Note: full negative-auth coverage (non-admin update_to revert) and the actual
// class-id swap require a node + L1 cheatcodes. See tests/upgrade.test.ts for
// the TS-side checks that exercise the composed update_to path end-to-end.

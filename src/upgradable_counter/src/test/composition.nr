// Hermetic TXE tests for the composed `aztec_upgradable` template surface on
// UpgradableCounter. The full class-id-swap-after-delay flow cannot be driven
// from TXE (no contract-class publish oracle and no second-artifact swap at the
// same address), so these tests cover what is template-owned: that the composed
// functions exist, init runs, host code coexists with composed code, and the
// authorization guard fires for non-owner callers.

use aztec::{
    protocol::{address::AztecAddress, traits::FromField},
    test::helpers::test_environment::TestEnvironment,
};
use crate::UpgradableCounter;

unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();
    let attacker = env.create_light_account();
    let initializer = UpgradableCounter::interface().constructor(owner);
    let counter_addr = env.deploy("@upgradable_counter/UpgradableCounter")
        .with_public_initializer(owner, initializer);
    (env, owner, attacker, counter_addr)
}

#[test]
unconstrained fn host_version_is_v1() {
    let (mut env, _owner, _attacker, counter_addr) = setup();
    let counter = UpgradableCounter::at(counter_addr);
    assert_eq(env.view_public(counter.version()), 1);
}

#[test]
unconstrained fn host_increment_and_get_count_coexist_with_composed_surface() {
    let (mut env, owner, _attacker, counter_addr) = setup();
    let counter = UpgradableCounter::at(counter_addr);
    assert_eq(env.view_public(counter.get_count()), 0);
    env.call_public(owner, counter.increment());
    assert_eq(env.view_public(counter.get_count()), 1);
}

// Proves the composed `update_to` carries the owner auth check end-to-end:
// a non-owner caller is rejected by the template-owned guard.
#[test(should_fail_with = "caller is not owner")]
unconstrained fn composed_update_to_rejects_non_owner() {
    let (mut env, _owner, attacker, counter_addr) = setup();
    let counter = UpgradableCounter::at(counter_addr);
    let bogus_class_id = aztec::protocol::contract_class_id::ContractClassId::from_field(0xdead);
    env.call_public(attacker, counter.update_to(bogus_class_id));
}

// Note: the actual class-id swap requires a node + L1 cheatcodes. See
// tests/upgrade.test.ts for the TS-side checks that exercise the composed
// update_to path end-to-end against the running sandbox.

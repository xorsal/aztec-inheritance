// Hermetic TXE tests for OwnableUpgradableCounter, which composes BOTH the
// aztec_ownable and aztec_upgradable templates against a single shared owner
// slot. Tests cover the template-owned behaviors: surface visibility, init,
// ownership rotation, and the #[only_owner] vendor-injected guard on a
// host-authored function. The class-id-swap end-to-end leg lives in
// tests/ownable_upgrade.test.ts against the running sandbox.

use aztec::{
    protocol::{address::AztecAddress, traits::FromField},
    test::helpers::test_environment::TestEnvironment,
};
use crate::OwnableUpgradableCounter;

unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();
    let attacker = env.create_light_account();
    let new_owner = env.create_light_account();
    let initializer = OwnableUpgradableCounter::interface().constructor(owner);
    let counter_addr = env.deploy("@ownable_upgradable_counter/OwnableUpgradableCounter")
        .with_public_initializer(owner, initializer);
    (env, owner, attacker, new_owner, counter_addr)
}

#[test]
unconstrained fn composed_get_owner_returns_constructor_owner() {
    let (mut env, owner, _attacker, _new_owner, counter_addr) = setup();
    let counter = OwnableUpgradableCounter::at(counter_addr);
    assert_eq(env.view_public(counter.get_owner()), owner);
}

#[test]
unconstrained fn host_version_is_v1() {
    let (mut env, _owner, _attacker, _new_owner, counter_addr) = setup();
    let counter = OwnableUpgradableCounter::at(counter_addr);
    assert_eq(env.view_public(counter.version()), 1);
}

#[test]
unconstrained fn host_increment_is_open_to_anyone() {
    let (mut env, _owner, attacker, _new_owner, counter_addr) = setup();
    let counter = OwnableUpgradableCounter::at(counter_addr);
    assert_eq(env.view_public(counter.get_count()), 0);
    env.call_public(attacker, counter.increment());
    assert_eq(env.view_public(counter.get_count()), 1);
}

#[test]
unconstrained fn owner_can_call_only_owner_set_count() {
    let (mut env, owner, _attacker, _new_owner, counter_addr) = setup();
    let counter = OwnableUpgradableCounter::at(counter_addr);
    env.call_public(owner, counter.set_count(42));
    assert_eq(env.view_public(counter.get_count()), 42);
}

#[test(should_fail_with = "caller is not owner")]
unconstrained fn only_owner_set_count_rejects_non_owner() {
    let (mut env, _owner, attacker, _new_owner, counter_addr) = setup();
    let counter = OwnableUpgradableCounter::at(counter_addr);
    env.call_public(attacker, counter.set_count(99));
}

#[test]
unconstrained fn transfer_ownership_rotates_owner() {
    let (mut env, owner, _attacker, new_owner, counter_addr) = setup();
    let counter = OwnableUpgradableCounter::at(counter_addr);
    env.call_public(owner, counter.transfer_ownership(new_owner));
    assert_eq(env.view_public(counter.get_owner()), new_owner);
}

#[test]
unconstrained fn transferred_owner_can_use_only_owner_gate() {
    let (mut env, owner, _attacker, new_owner, counter_addr) = setup();
    let counter = OwnableUpgradableCounter::at(counter_addr);
    env.call_public(owner, counter.transfer_ownership(new_owner));
    env.call_public(new_owner, counter.set_count(7));
    assert_eq(env.view_public(counter.get_count()), 7);
}

#[test(should_fail_with = "caller is not owner")]
unconstrained fn old_owner_loses_access_after_transfer() {
    let (mut env, owner, _attacker, new_owner, counter_addr) = setup();
    let counter = OwnableUpgradableCounter::at(counter_addr);
    env.call_public(owner, counter.transfer_ownership(new_owner));
    env.call_public(owner, counter.set_count(13));
}

#[test(should_fail_with = "caller is not owner")]
unconstrained fn transfer_ownership_rejects_non_owner() {
    let (mut env, _owner, attacker, _new_owner, counter_addr) = setup();
    let counter = OwnableUpgradableCounter::at(counter_addr);
    env.call_public(attacker, counter.transfer_ownership(attacker));
}

#[test(should_fail_with = "new owner is zero")]
unconstrained fn transfer_ownership_rejects_zero_address() {
    let (mut env, owner, _attacker, _new_owner, counter_addr) = setup();
    let counter = OwnableUpgradableCounter::at(counter_addr);
    env.call_public(owner, counter.transfer_ownership(AztecAddress::zero()));
}

#[test(should_fail_with = "caller is not owner")]
unconstrained fn composed_update_to_rejects_non_owner() {
    let (mut env, _owner, attacker, _new_owner, counter_addr) = setup();
    let counter = OwnableUpgradableCounter::at(counter_addr);
    let bogus_class_id = aztec::protocol::contract_class_id::ContractClassId::from_field(0xdead);
    env.call_public(attacker, counter.update_to(bogus_class_id));
}

#[test(should_fail_with = "caller is not owner")]
unconstrained fn composed_set_update_delay_rejects_non_owner() {
    let (mut env, _owner, attacker, _new_owner, counter_addr) = setup();
    let counter = OwnableUpgradableCounter::at(counter_addr);
    env.call_public(attacker, counter.set_update_delay(123));
}

// TXE tests for a host that composes aztec_ownable + aztec_pausable +
// aztec_metadata. Proves that all three templates' surfaces coexist and
// that the shared `owner` slot authenticates every admin path through
// the ownable-initialized value.

use aztec::{
    protocol::address::AztecAddress,
    test::helpers::test_environment::TestEnvironment,
};
use crate::OwnablePausableCounter;

global INITIAL_METADATA: Field = 0xCAFEBABE;

unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let deployer = env.create_light_account();
    let owner = env.create_light_account();

    let initializer = OwnablePausableCounter::interface().constructor(owner, INITIAL_METADATA);
    let addr = env.deploy("@ownable_pausable_counter/OwnablePausableCounter")
        .with_public_initializer(deployer, initializer);
    (env, owner, deployer, addr)
}

// Ownable template surface is reachable and reflects the constructor's owner.
#[test]
unconstrained fn ownable_owner_round_trips() {
    let (mut env, owner, _deployer, addr) = setup();
    let host = OwnablePausableCounter::at(addr);
    assert_eq(env.view_public(host.get_owner()), owner);
}

// Pausable template surface is reachable and starts unpaused.
#[test]
unconstrained fn pausable_starts_unpaused() {
    let (mut env, _owner, _deployer, addr) = setup();
    let host = OwnablePausableCounter::at(addr);
    assert_eq(env.view_public(host.paused()), false);
}

// Host's own `increment` works while unpaused.
#[test]
unconstrained fn increment_works_while_unpaused() {
    let (mut env, _owner, _deployer, addr) = setup();
    let host = OwnablePausableCounter::at(addr);
    let caller = env.create_light_account();
    env.call_public(caller, host.increment());
    assert_eq(env.view_public(host.get_count()), 1);
}

// Owner can pause, and once paused the host's increment reverts via
// `_assert_not_paused` injected by the pausable mixin.
#[test(should_fail_with = "contract is paused")]
unconstrained fn increment_reverts_while_paused() {
    let (mut env, owner, _deployer, addr) = setup();
    let host = OwnablePausableCounter::at(addr);
    env.call_public(owner, host.pause());
    let caller = env.create_light_account();
    env.call_public(caller, host.increment());
}

// Non-owner calling pause reverts with the auth helper's message.
#[test(should_fail_with = "caller is not owner")]
unconstrained fn non_owner_cannot_pause() {
    let (mut env, _owner, _deployer, addr) = setup();
    let host = OwnablePausableCounter::at(addr);
    let stranger = env.create_light_account();
    env.call_public(stranger, host.pause());
}

// pause -> unpause -> increment round-trip proves both admin paths and the
// host gate.
#[test]
unconstrained fn pause_then_unpause_restores_increment() {
    let (mut env, owner, _deployer, addr) = setup();
    let host = OwnablePausableCounter::at(addr);
    env.call_public(owner, host.pause());
    assert_eq(env.view_public(host.paused()), true);
    env.call_public(owner, host.unpause());
    assert_eq(env.view_public(host.paused()), false);
    let caller = env.create_light_account();
    env.call_public(caller, host.increment());
    assert_eq(env.view_public(host.get_count()), 1);
}

// Metadata template surface: the constructor's value is readable through
// the composed get_metadata view.
#[test]
unconstrained fn metadata_reflects_constructor_value() {
    let (mut env, _owner, _deployer, addr) = setup();
    let host = OwnablePausableCounter::at(addr);
    assert_eq(env.view_public(host.get_metadata()), INITIAL_METADATA);
}

// Owner can rotate metadata; the new value sticks.
#[test]
unconstrained fn owner_can_set_metadata() {
    let (mut env, owner, _deployer, addr) = setup();
    let host = OwnablePausableCounter::at(addr);
    let new_value: Field = 0xDEADBEEF;
    env.call_public(owner, host.set_metadata(new_value));
    assert_eq(env.view_public(host.get_metadata()), new_value);
}

// Non-owner attempting set_metadata reverts through the metadata admin gate.
#[test(should_fail_with = "caller is not owner")]
unconstrained fn non_owner_cannot_set_metadata() {
    let (mut env, _owner, _deployer, addr) = setup();
    let host = OwnablePausableCounter::at(addr);
    let stranger = env.create_light_account();
    env.call_public(stranger, host.set_metadata(0xBADF00D));
}

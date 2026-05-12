use crate::{test::utils, Amm};

// Minimal surface check: composed token views should exist and reflect constructor state.
#[test]
unconstrained fn composed_views_are_exposed() {
    let (mut env, deployer, provider, token_a, token_b) = utils::setup();
    let amm_addr = utils::deploy_amm_token(&mut env, deployer, token_a, token_b);
    let amm = Amm::at(amm_addr);

    assert_eq(env.view_public(amm.decimals()), 18);
    assert_eq(env.view_public(amm.total_supply()), 0);
    assert_eq(env.view_public(amm.balance_of_public(provider)), 0);
}

// Minimal behavior check: one inherited private token transfer path should work end-to-end.
#[test]
unconstrained fn composed_transfer_private_to_private_works() {
    let (mut env, deployer, provider, token_a, token_b) = utils::setup();
    let recipient = env.create_light_account();
    let amm_addr = utils::deploy_amm_token(&mut env, deployer, token_a, token_b);
    let amm = Amm::at(amm_addr);

    utils::mock_note_randomness();
    env.call_private(provider, amm.add_liquidity(provider, 1000, 1000));

    utils::mock_note_randomness();
    env.call_private(provider, amm.transfer_private_to_private(provider, recipient, 400, 0));

    assert_eq(env.execute_utility(amm.balance_of_private(provider)), 600);
    assert_eq(env.execute_utility(amm.balance_of_private(recipient)), 400);
    assert_eq(env.view_public(amm.total_supply()), 1000);
}

use crate::{test::utils, Amm};

// SC-3: add_liquidity should mint LP shares through the composed token internals.
#[test]
unconstrained fn add_liquidity_mints_lp_shares_and_updates_reserves() {
    let (mut env, deployer, provider, token_a, token_b) = utils::setup();
    let amm_addr = utils::deploy_amm_token(&mut env, deployer, token_a, token_b);
    let amm = Amm::at(amm_addr);

    utils::mock_note_randomness();
    env.call_private(provider, amm.add_liquidity(provider, 1000, 1000));

    assert_eq(env.execute_utility(amm.balance_of_private(provider)), 1000);
    assert_eq(env.view_public(amm.total_supply()), 1000);

    let (reserve_a, reserve_b) = env.view_public(amm.get_reserves());
    assert_eq(reserve_a, 1000);
    assert_eq(reserve_b, 1000);
}

// The host contract sets `minter = self`, so external callers must not be able to mint directly.
#[test(should_fail_with = "Assertion failed: caller is not minter")]
unconstrained fn mint_to_private_fails_for_non_minter() {
    let (mut env, deployer, provider, token_a, token_b) = utils::setup();
    let amm_addr = utils::deploy_amm_token(&mut env, deployer, token_a, token_b);

    utils::mock_note_randomness();
    env.call_private(provider, Amm::at(amm_addr).mint_to_private(provider, 1));
}

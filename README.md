# Aztec Contract Template Composition PoC

This repo is a working proof of concept for **contract template composition** on
Aztec.

The core idea is:

- define a normal Aztec contract as a **template**
- register it by id
- let another Aztec contract **compose** that template during its own `#[aztec]`
  pass

The concrete example here is an AMM contract that also becomes a full token at
the same address. The host AMM contract can call composed token internals such
as `_mint_to_private`, so `add_liquidity` can mint LP shares through the token
logic already injected into the host.

## What This Proves

This PoC proves that:

- a contract can be treated as a reusable template
- a host contract can receive that template's external and internal surface
- the host can call composed internals directly
- one deployed contract can act as both app and token

The example in this repo proves this with:

- `TokenContractTemplate` as the injected AIP-20-style token surface
- `Amm` as the host contract

## Repo Layout

- [vendor/aztec](/Users/wei3erHase/wonderland/aztec/mixins/vendor/aztec): vendored Aztec macro/codegen changes that make template composition work
- [src/aztec-token-mixin](/Users/wei3erHase/wonderland/aztec/mixins/src/aztec-token-mixin): local template crate; contains `TokenContractTemplate`
- [src/amm_token](/Users/wei3erHase/wonderland/aztec/mixins/src/amm_token): local host contract; composes the token template into `Amm`
- [docs/contract-template-composition-poc.md](/Users/wei3erHase/wonderland/aztec/mixins/docs/contract-template-composition-poc.md:1): the main technical writeup
- [ROADMAP.md](/Users/wei3erHase/wonderland/aztec/mixins/ROADMAP.md:1): status log, design history, current limitations

## Read This First

If you want the shortest path through the repo:

1. Read [docs/contract-template-composition-poc.md](/Users/wei3erHase/wonderland/aztec/mixins/docs/contract-template-composition-poc.md:1).
2. Look at the template contract in [src/aztec-token-mixin/src/token_contract_template/mod.nr](/Users/wei3erHase/wonderland/aztec/mixins/src/aztec-token-mixin/src/token_contract_template/mod.nr:1).
3. Look at the host contract in [src/amm_token/src/main.nr](/Users/wei3erHase/wonderland/aztec/mixins/src/amm_token/src/main.nr:1).
4. Check the behavior tests in [src/amm_token/src/test/token_surface.nr](/Users/wei3erHase/wonderland/aztec/mixins/src/amm_token/src/test/token_surface.nr:1) and [src/amm_token/src/test/add_liquidity.nr](/Users/wei3erHase/wonderland/aztec/mixins/src/amm_token/src/test/add_liquidity.nr:1).

## The Main Trick

Template:

```noir
#[contract_template("aip20_token")]
#[aztec]
pub contract TokenContractTemplate { ... }
```

Host:

```noir
#[aztec(AztecConfig::new().compose("aip20_token"))]
pub contract Amm { ... }
```

This is the whole PoC in one picture:

- the template is itself a real `#[aztec]` contract
- `#[contract_template(...)]` captures its generated surface ahead of time
- the host `#[aztec]` injects that surface during host codegen

So the host behaves as if the template functions had been written directly in
the host contract source.

## How To Validate It

From the repo root:

```bash
nargo check
aztec test
```

What the current tests demonstrate:

- composed view functions exist and initialize correctly
- `add_liquidity` mints LP shares through composed token internals
- composed `transfer_private_to_private` works
- direct external minting by a non-minter fails

## Current Boundaries

This repo is a strong PoC, not a finished product.

Important current constraints:

- raw top-level globals are not generically migrated; helper functions work better
- host and template cannot cleanly "override" the same method today; collisions just fail
- the host must satisfy the template's storage/event/import assumptions
- full token parity coverage has not been ported yet

The fuller explanation is in
[docs/contract-template-composition-poc.md](/Users/wei3erHase/wonderland/aztec/mixins/docs/contract-template-composition-poc.md:1).

## If You Want The One-Sentence Summary

This repo shows that with modest vendored changes to Aztec's macro/codegen
layer, a normal Aztec contract can be registered as a reusable template and
composed into another contract, producing a real working single-address
app-plus-token contract.

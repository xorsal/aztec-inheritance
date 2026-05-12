# Contract Template Composition PoC

## What This Repo Is Doing

This repo proves that an Aztec contract can be used as a **template** and its
full function surface can be injected into another Aztec contract, so the host
contract behaves as if those functions had been written there directly.

The concrete example in this repo is:

- a token template: [src/aztec-token-mixin/src/token_contract_template/mod.nr](/Users/wei3erHase/wonderland/aztec/mixins/src/aztec-token-mixin/src/token_contract_template/mod.nr:1)
- a host contract: [src/amm_token/src/main.nr](/Users/wei3erHase/wonderland/aztec/mixins/src/amm_token/src/main.nr:1)

The host `Amm` contract is both:

- an AMM pool
- a full AIP-20-style token at the same address

That lets `add_liquidity` mint LP shares through the composed token internals on
the host contract itself.

This is not token-specific at the mechanism level. The vendored `aztec`
changes are generic: any contract can be turned into a registered template and
injected into any host contract, as long as the host satisfies that template's
assumptions.

## The Core Trick

The mechanism has two sides:

1. A **template contract** is declared and registered by id.
2. A **host contract** opts into one or more registered templates.

Template side:

```noir
#[contract_template("aip20_token")]
#[aztec]
pub contract TokenContractTemplate { ... }
```

Host side:

```noir
#[aztec(AztecConfig::new().compose("aip20_token"))]
pub contract Amm { ... }
```

The important part is that the template is itself a real `#[aztec]` contract.
That is the "double `#[aztec]`" idea:

- the template gets processed once as a normal Aztec contract
- the host gets processed once as a normal Aztec contract
- the host `#[aztec]` reuses pre-registered information from the template

So we are not teaching Noir a new template language. We are piggybacking on the
existing Aztec contract pipeline and replaying a template contract's generated
surface into another contract.

## How It Works

### 1. The template registers itself before host composition

`#[contract_template("...")]` runs on the template module and precomputes:

- generated wrappers for all `#[external(...)]` functions
- generated wrappers for all `#[internal(...)]` functions
- ABI export structs
- generated wrappers for template-local `#[contract_library_method]` helpers

That behavior lives broadly in:

- [vendor/aztec/src/macros/mod.nr](/Users/wei3erHase/wonderland/aztec/mixins/vendor/aztec/src/macros/mod.nr:1)
- [vendor/aztec/src/macros/template_registry.nr](/Users/wei3erHase/wonderland/aztec/mixins/vendor/aztec/src/macros/template_registry.nr:1)

The results are stored in a keyed global registry under the template id.

### 2. The template is also processed as a normal Aztec contract

`#[aztec]` still runs on `TokenContractTemplate`.

This matters for two reasons:

- the template functions must type-check as a real Aztec contract
- the normal Aztec function metadata/registries are what `#[contract_template]`
  reads in order to know which functions are external/internal and how to
  generate wrappers for them

### 3. The host asks to compose one or more templates

`AztecConfig::compose("template-id")` adds a template id to the host config in:

- [vendor/aztec/src/macros/aztec.nr](/Users/wei3erHase/wonderland/aztec/mixins/vendor/aztec/src/macros/aztec.nr:18)

Before the host's normal Aztec codegen runs, the host `#[aztec]` macro:

- looks up the selected template module(s)
- injects their `FunctionDefinition`s into the host's composed registries

That step is handled in:

- [vendor/aztec/src/macros/compose_template.nr](/Users/wei3erHase/wonderland/aztec/mixins/vendor/aztec/src/macros/compose_template.nr:1)

### 4. The host generates its interface/dispatch as if the template functions were local

Once those template `FunctionDefinition`s are in the composed registries, the
normal Aztec generators for:

- external call interface
- self-call stubs
- internal-call helpers
- ABI exports
- dispatch

all "see" the union of:

- host-authored functions
- template-composed functions

So the host contract gets the composed surface without having handwritten token
functions in its source.

### 5. The pre-generated quoted code is replayed into the host

The host also needs the actual generated wrapper bodies and helper wrappers.

Those are pulled back out of the template registry and appended to the host's
generated output in:

- [vendor/aztec/src/macros/compose_template.nr](/Users/wei3erHase/wonderland/aztec/mixins/vendor/aztec/src/macros/compose_template.nr:65)
- [vendor/aztec/src/macros/aztec.nr](/Users/wei3erHase/wonderland/aztec/mixins/vendor/aztec/src/macros/aztec.nr:91)

This is the key workaround for Noir's cross-crate body limitation: we do not
re-read foreign function bodies later; we capture the generated quoted code
while still in the template crate and replay that in the host.

## Broad Vendor Changes

The changes in `vendor/aztec` are broad but conceptually small.

### `AztecConfig` grew composition support

The host can now opt into templates with:

- `AztecConfig::new().compose("template-id")`

instead of composition being a token-only special case.

### A generic template registration macro was added

`#[contract_template("template-id")]` captures a contract template's generated
surface ahead of time and stores it by id.

### A keyed template registry was added

The vendor layer stores:

- template module
- generated function wrappers
- generated ABI exports
- generated contract-library helper wrappers

by template id, so composition is no longer hardcoded to a single token module.

### Host-side Aztec codegen was taught to merge composed functions

Before ordinary `#[aztec]` host codegen runs, the selected templates'
`FunctionDefinition`s are added into the host's composed registries. This is
what makes the normal Aztec interface/dispatch generators include the composed
functions automatically.

### Event registration was relaxed for the same event

The token template and the host both declare `Transfer`. Without adjustment,
that looked like a collision during compilation. The vendored event selector
registration now allows re-registration of the same event name/signature and
only errors on genuine selector collisions.

## What This PoC Proves

This repo currently proves all of the following:

- a contract template can be registered in one crate and composed into a host
  contract in another crate
- the host gets the composed external token surface
- the host gets the composed internal token helpers
- app-specific logic can call composed internals directly
- one contract can act as both "application" and "token"

In the concrete AMM/token example, the tests prove:

- composed view functions exist and reflect constructor state
- `add_liquidity` mints LP shares through composed token internals
- one inherited private transfer path works end-to-end
- direct external minting still respects the minter guard

See:

- [src/amm_token/src/test/token_surface.nr](/Users/wei3erHase/wonderland/aztec/mixins/src/amm_token/src/test/token_surface.nr:1)
- [src/amm_token/src/test/add_liquidity.nr](/Users/wei3erHase/wonderland/aztec/mixins/src/amm_token/src/test/add_liquidity.nr:1)

The current validation path is:

- `nargo check`
- `aztec test`

## Current Limitations

### 1. Raw globals are not generically migrated

Template-local helper functions can be migrated if they are
`#[contract_library_method]`, because vendor can see them through
`m.functions()` and generate host-side forwarding wrappers for them.

Raw top-level globals do not have that path.

That is why the token template uses helper methods like:

- `_initial_transfer_call_max_notes()`
- `_recursive_transfer_call_max_notes()`
- `_private_address_magic_value()`

instead of bare module globals.

Broadly, the reason is:

- the current comptime `Module` API exposes functions/structs/child modules
- it does not expose arbitrary top-level items in a way this mechanism can
  migrate generically

Practical rule:

- prefer helper functions over raw globals inside a template contract

### 2. Shared package-level helpers are awkward across both phases

If a helper lives outside the template contract, the current machinery cannot
just "bring it along" as naturally as a template-local `#[contract_library_method]`.

This is why `_validate_minter` currently lives inside the template contract:

- one source declaration
- migrated by the same helper-wrapper mechanism as the note-limit helpers

Practical rule:

- if a helper is only needed by composed functions, keep it template-local unless
  there is a strong reason to make it a separate reusable library API

### 3. The host must satisfy the template's assumptions

Composition does not mean "any host works automatically".

If composed function bodies expect:

- specific storage fields
- specific event types
- specific internal helper names
- specific imports/traits in scope

the host must satisfy those assumptions.

In this repo today that means, for example:

- the host inlines the token storage fields because nested `TokenStorage<Context>`
  is not supported under `#[storage]`
- the host declares a compatible `Transfer` event
- the host currently imports `FromField`, even though the host's own source does
  not call it directly, because injected bodies need that trait in scope
- the host imports the function macro set that includes `only_self`

These are real constraints of the current PoC, not abstract future concerns.

### 4. Name collisions are still a real constraint

If the host and the template define overlapping function names/signatures, the
current composition model relies on ordinary compilation failure rather than a
specialized friendly diagnostic.

Practical rule:

- template and host APIs must be designed not to overlap

### 5. Full parity is not proven yet

The mechanism works and key behavior is tested, but this repo has not yet ported
the full token standards test suite into the composed AMM fixture.

So the PoC proves:

- composition works
- AMM + token composition works
- LP mint through composed internals works

But it does not yet prove exhaustive behavioral parity with every token test
from the upstream standards suite.

### 6. There is no Solidity-style override today

The current composition model is a **merge**, not an inheritance hierarchy with
override semantics.

That means if the host composes a template and also defines a function with the
same name/signature as a template function, the result is a collision rather
than "host wins".

So this is **not** supported cleanly today:

```noir
#[aztec(AztecConfig::new().compose("aip20_token"))]
pub contract MyToken {
    #[external("private")]
    fn mint_to_private(to: AztecAddress, amount: u128) {
        // intended replacement
    }
}
```

In the current PoC, vendor still tries to inject the template's
`mint_to_private`, so the host and template compete for the same function slot.

Practical rule:

- composition currently supports "take the template surface as-is"
- it does **not** support "compose the template but replace just this one method"

If that capability is ever added, it would likely need an explicit mechanism
such as:

- `compose_except("aip20_token", ["mint_to_private"])`
- or a host-side "override these template methods" list

But that is future work, not part of the current PoC.

## What Makes a Contract "Templatable"

Any contract can be used as a template **if it behaves like a good citizen for
replay into a host**.

In practice, a contract is templatable when:

### It exposes the surface through Aztec-recognized function kinds

The functions you expect to compose should be in categories vendor knows how to
capture and replay:

- `#[external(...)]`
- `#[internal(...)]`
- `#[contract_library_method]` for template-local helper functions

### Its bodies do not rely on raw top-level items that cannot be migrated

Good:

- template-local `#[contract_library_method]` helpers
- fully-qualified library paths

Risky:

- bare module globals
- assumptions that a `use` item will somehow exist in the host

### Its storage expectations are explicit and reproducible in the host

If the template's functions read/write:

- `self.storage.name`
- `self.storage.total_supply`
- `self.storage.public_balances`

then the host must define a compatible storage shape.

Today that compatibility is mostly enforced by normal type-checking, not by a
dedicated template-validator pass.

### Its event expectations are explicit

If template functions emit `Transfer`, the host must provide a compatible
`Transfer` event definition unless the event is otherwise injected by the
composition mechanism.

### Its helper functions are shaped for replay

Template-local helper functions are the easiest case. In this repo, that is why
the token-specific helper methods live inside the template contract.

### It avoids overlapping with the host API

Templating is easiest when the template is a clean, well-scoped surface rather
than a contract with lots of generic names likely to collide with the host.

## Practical Template Authoring Rules

If someone wants to make another contract templatable in this repo, the safest
rules are:

1. Put the template in its own crate/module and register it with `#[contract_template("id")]`.
2. Keep the template itself as a valid `#[aztec]` contract.
3. Make the replayed surface consist of `#[external]`, `#[internal]`, and
   template-local `#[contract_library_method]` helpers.
4. Avoid raw globals; prefer helper functions.
5. Use fully-qualified paths in function bodies where possible.
6. Assume the host must reproduce the template's storage/event assumptions.
7. Avoid host/template function-name overlap.

## Bottom Line

This PoC shows that Aztec contract composition is already possible without new
Noir syntax:

- define a normal Aztec contract as a template
- register it by id
- let a host contract opt into that template during its own `#[aztec]` pass

The vendored changes are generic enough that the token example is only one
consumer of the mechanism.

What is proven:

- real composed contract behavior
- same-address app + token composition
- host calls into composed internals

What is not magically solved:

- arbitrary top-level item migration
- automatic host compatibility checking
- full upstream token parity coverage

That is the real scope of this repo: a working, readable, end-to-end PoC for
contract-template injection on Aztec.

## If Noir Had Better Native Support

If we had full control over the Noir compiler/language, the most valuable
improvements for this design would be:

### 1. First-class top-level item composition

The ideal version would let macros or the language inject full contract items
directly into a contract body, instead of forcing this registry-and-replay
approach.

That would make template composition feel native instead of simulated.

### 2. Reflection over all top-level items

Today the useful reflection surface is strong for functions, but not for
arbitrary top-level items.

For template composition, it would be very valuable if `Module` could expose:

- globals
- imports
- events
- impls
- or, more generally, an ordered stream of top-level items

That would make it possible to migrate more of a template automatically instead
of reshaping things into helper functions.

### 3. Hygienic self-crate paths for replayed code

One of the biggest current pain points is that a helper path written inside the
template source does not necessarily remain stably bound to the template crate
after replay into the host.

An ideal system would let template-authored paths keep their original crate
identity when replayed elsewhere.

That would make shared helper code much cleaner.

### 4. Safe cross-crate body reuse at comptime

This PoC captures generated quoted code early because later cross-crate body
reuse is awkward.

If macros could safely inspect and reuse foreign function bodies directly, much
of the registry/replay machinery could disappear.

### 5. Better quoted-item support

It would be especially useful if quoted top-level items such as `use`
declarations could be replayed cleanly where composition needs them.

That would remove some of the current pressure to keep helper logic inside the
template contract just so it migrates through the existing helper-function path.

### 6. Native template/host compatibility checking

The compiler could give a first-class validation pass for composition, checking:

- required storage fields
- required events
- required helper items
- template/host function collisions

before the user hits lower-level type or codegen failures.

### 7. Capability traits for Aztec storage/context types

This is the class of issue behind the repo's old L-9 exploration.

If Aztec storage/context APIs exposed trait-like capabilities such as:

- readable public storage
- writable public storage
- receivable private note state

then more token logic could live in ordinary reusable libraries rather than
being kept inline in the template/host.

### The Highest-Value Improvements

For this repo specifically, the biggest wins would be:

1. first-class top-level item composition
2. hygienic self-crate paths for replayed code
3. native template/host compatibility checking

Those three would remove most of the current awkwardness while keeping the same
overall product direction.

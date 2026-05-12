# L-9: Historical `private_actions` / `public_actions` Idea

## Short Version

Those files were meant to hold **reusable state-touching token helpers**.
This is a historical explanation only: the repo does **not** pursue this design anymore.

Without the current Noir/Aztec limitation, the template contract would keep the
high-level token API, while the low-level storage mutations would live in small
library modules.

So instead of one large contract containing both:

- "what this token operation does"
- "how to mutate balances/supply in storage"

we would split it into:

- contract/template: orchestration
- hypothetical `private_actions.nr`: private-state mutations
- hypothetical `public_actions.nr`: public-state mutations

## What That Would Look Like

Today, this kind of logic lives directly in the template contract:

```noir
#[internal("public")]
fn _increase_public_balance(to: AztecAddress, amount: u128) {
    let new_balance = self.storage.public_balances.at(to).read() + amount;
    self.storage.public_balances.at(to).write(new_balance);
}
```

If there were no limitation, the contract could delegate the storage mutation to
an extracted public-actions helper instead:

```noir
#[internal("public")]
fn _increase_public_balance(to: AztecAddress, amount: u128) {
    public_actions::increase_public_balance(self.storage.public_balances.at(to), amount);
}
```

And that extracted helper module would contain the reusable implementation:

```noir
pub fn increase_public_balance(
    balance: PublicMutable<u128, PublicContext>,
    amount: u128,
) {
    let current = balance.read();
    balance.write(current + amount);
}
```

## Why This Would Be Nice

- smaller template contract
- clearer separation between API/orchestration and storage mutation
- easier reuse across multiple token-like templates
- easier testing/reasoning about small balance-update helpers

## Why It Is Parked

In the current system, those storage values are too tied to specific context
types, so they cannot be cleanly passed around as generic library inputs the way
this design wants.

That is why the helpers are currently inlined in the template/host instead of
living in separate action modules. In this repo, L-9 is now closed and not pursued.

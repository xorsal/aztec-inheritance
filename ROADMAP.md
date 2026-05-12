# Roadmap: Inheritance-like Token Composition for Aztec

**Project**: Single-contract Token Composition (Mixins)  
**Branch**: `feat/token-composition-mixin`  
**Repos in scope**:
- `defi-wonderland/aztec-standards` → `feat/token-composition-mixin`  
- `AztecProtocol/aztec-packages` (fork: `wei3erhase/aztec-packages`) → `feat/token-composition-mixin`  
- `noir-lang/noir` → M1 planned (via `aztec-packages/noir/noir-repo` submodule)  
**Workspace**: `wonderland/aztec/mixins/` (this repo)

---

## Milestones

| ID | Milestone | Status | Notes |
|----|-----------|--------|-------|
| M0 | ADR + roadmap + workspace setup | ✅ Done | This document |
| M1 | Noir: parser + AST for macro items in `contract { }` | 📋 Planned | Requires `noir-lang/noir` contribution |
| M2 | Aztec: generic contract-template composition PoC compiles | ✅ Done | token mixin now rides generic vendor machinery |
| M3 | Full token parity tests + AMM+LP-mint fixture | 🚧 In progress | Minimal behavior tests added; parity port still pending |
| M4 | Docs, migration guide, security review, perf pass | 📋 Planned | After M3 |

---

## Log

### 2026-05-12 — stop rewriting `validate_minter`

**Decision:** keep `_validate_minter` inside `TokenContractTemplate` as a
`#[contract_library_method]`, the same way the note-limit helpers already work.

**Why this decision:**
- there is a single source declaration for the helper in the codebase
- the helper follows the same migration path as `_initial_transfer_call_max_notes` and
  `_recursive_transfer_call_max_notes`
- no extra support crate or host-alias mechanism is needed

**Why this is acceptable:**
- the host still receives a generated forwarding wrapper behind the scenes, but that wrapper comes
  from the existing `#[contract_library_method]` composition path
- the helper is not declared twice in source; it exists once in the template and once in generated
  output only

**Current rule:**
- if a helper is needed by composed functions and a single source declaration is acceptable, keep it
  inside the template contract as `#[contract_library_method]`
- only pursue package-level shared helpers if/when we need a real multi-consumer library surface
  outside the template

### 2026-05-12 — generic contract-template composition refactor

**Achieved:**
- generalized vendor composition from token-only wiring to named contract templates
- replaced singleton token registries with a keyed template registry
- replaced `compose_token()` with `compose("template-id")`, which can be called multiple times
- replaced `#[token_template]` with `#[contract_template("template-id")]`
- removed token-only global injection from vendor; the AIP-20 template now uses migratable
  `#[contract_library_method]` helpers for its former constants

**Current architecture:**
- vendor owns only generic composition machinery
- template implementations live outside that machinery and register themselves by id
- the token template is now just one consumer of the generic path via
  `#[contract_template("aip20_token")]`
- `_validate_minter` remains template-local and migrates through the same
  `#[contract_library_method]` path as the note-limit helpers

**Validation:**
- `nargo check`
- `aztec compile`
- `aztec test`
- result: `4 tests passed`

### 2026-05-12 — move token mixin out of vendor

**Achieved:**
- moved `aztec_token_mixin` from `vendor/` to `src/aztec-token-mixin`
- kept `vendor/aztec` as the generic/native-like dependency layer
- kept `src/` as the local usage layer, with `src/amm_token` depending on `src/aztec-token-mixin`

**Why:**
- matches the intended architecture more honestly
- makes the token template clearly an ad-hoc consumer of generic vendor machinery, not part of vendor itself

**Current layout:**
- `vendor/aztec`, `vendor/uint-note`, `vendor/compressed-string`, `vendor/balance-set`
- `src/aztec-token-mixin`
- `src/amm_token`

### 2026-05-12 — minimal behavior tests added

**Achieved:**
- added repo-local AMM/token composition tests under `src/amm_token/src/test/`
- covered constructor/composed views, LP mint on `add_liquidity`, composed
  `transfer_private_to_private`, and non-minter rejection for direct `mint_to_private`

**Validation:**
- `nargo check`
- `aztec compile`
- `aztec test`
- result: `4 tests passed`

**Impact on milestones:**
- moves M3 from “next” to “in progress”
- proves the PoC behavior path, but does not yet provide full parity against the
  standards token suite

### 2026-05-12 — isolated repo packaging refined

**Issue:** depending on a full `aztec-packages` checkout was too heavy for a demo repo whose real
goal is to show the modified `#[aztec]` path.

**Current layout:**
- keep the modified Aztec macro crates local under `vendor/`
- keep the minimal local dependency closure that must share the same Noir `aztec` crate identity:
  `aztec`, `uint-note`, `compressed-string`, `balance-set`
- leave unmodified upstream-only dependencies on git where crate identity does not force a local copy

**Why this shape exists:** Noir crate identity is nominal, so crates that depend on `aztec` cannot
mix a vendored `aztec` with upstream `aztec` and still share types safely.

### 2026-05-12 — compose_token: generic `#[contract_library_method]` migration

**Issue:** `compose_token` manually re-declared template-local helper code inside `scope_setup`
because template `#[contract_library_method]` helpers were not part of the composed token registry
path. That worked for one helper but encoded a special case into the macro.

**Fix implemented:**
- `#[token_template]` now captures template `#[contract_library_method]` helpers and stores their
  generated wrapper definitions in `token_module_registry`
- each generated host-side wrapper forwards to a preserved typed reference to the original template
  helper, avoiding cross-crate body re-quoting
- `compose_token::get_token_quoted()` now injects those helpers generically into the host contract
- token-only hardcoding in `scope_setup` was removed; remaining template-local helpers migrate
  through the same generic path

**Status:** ✅ Implemented and validated in local vendored `aztec` / `aztec-token-mixin`

**Why this matters:**
- removes one-off helper duplication from the composition machinery
- makes future token helper methods migrate automatically as long as they are
  `#[contract_library_method]`
- keeps the PoC closer to the intended “template-driven composition” model

**Validation:**
- `nargo check`
- `aztec compile`
- `aztec test`
- result: `4 tests passed`

### 2026-05-12 — Correction: isolated repo setup

**Issue:** Initial approach incorrectly worked on existing local repo clones at `aztec/packages/` and `aztec/standards/`. All changes reverted.

**Fix:** Isolated clones set up under `mixins/repos/`:
- `repos/aztec-standards/` — fresh clone at `c60e973` (v4.2.0 aligned), branch `feat/token-composition-mixin`
- `repos/aztec-packages/` — shallow clone at `v4.2.0` tag, branch `feat/token-composition-mixin`
- `repos/aztec-packages/noir/noir-repo/` — Noir submodule inited at matching commit (shallow)

**Binding:** `src/amm_token/Nargo.toml` uses path deps `../../repos/aztec-packages/noir-projects/aztec-nr/...`

---

### 2026-05-12 — M0: ADR, workspace, standards cleanup

**Achieved:**
- Initialized `mixins` workspace with git
- Created `feat/token-composition-mixin` branch in `aztec-standards` and `aztec-packages`
- Removed non-Token contracts from `aztec-standards` workspace (vault, dripper, NFT, escrow, generic_proxy)
  — Source files preserved in `src/`, removed only from Nargo workspace members
- Catalogued full token API surface (see ADR-001 below)
- Researched aztec.nr macro system — identified composition strategy
- Researched Noir parser — confirmed M1 requirements

**Limitations / Issues discovered:**
- `inject_full_token!()` at module scope is **blocked by the Noir parser**: `TopLevelStatementKind` has no `MacroInvocation` variant. Parser grammar is fixed. This is the core gap that M1 must address.
- The `#[aztec]` macro uses **global CHashMap registries** populated by item-level attribute macros (`#[external]`, `#[internal]`) that run BEFORE `#[aztec]`. This creates a timing challenge for any "pre-macro injection" approach: functions injected after the registries are read won't appear in dispatch/ABI.
- `Module::add_item()` is **not used** in the current aztec-nr codebase. Its elaboration timing relative to module-level macros is unknown without testing.
- The `token_actions_poc.nr` in standards shows a prior attempt using function hooks — useful pattern but limited to private operations.

**ADR decisions made:**
- Selected composition strategy: **Modify `#[aztec]` to accept `compose_token` via `AztecConfig`** (see ADR-001)
- Token logic extracted to `aztec-token-mixin` library in `aztec-nr` (see ADR-002)
- Storage composition via named token fields in a `TokenStorage<Context>` wrapper struct (see ADR-003)
- Internal mint from LP: minter = self address, calls shared library functions (see ADR-004)

---

## Architecture Decision Records

### ADR-001: Composition Strategy

**Decision**: Implement composition by modifying `#[aztec]` to generate token function dispatch/ABI when `compose_token` is enabled.

**Status**: Selected for M2 PoC

**Context**: Three viable paths identified:
1. **`inject_token!()` at module scope** → blocked by Noir parser (no `MacroInvocation` in `TopLevelStatementKind`)  
2. **Pre-macro `#[compose_token]` on Storage** → timing issue: injected functions' attributes may not populate registries before `#[aztec]` reads them  
3. **Modify `#[aztec]` to handle composition** → single-pass, avoids timing issue, matches existing `AztecConfig` extension pattern  

**Selected approach**: Extend `AztecConfig` with `compose_token()`:
```noir
#[aztec(AztecConfig::new().compose_token())]
pub contract Amm {
    // Only app-specific functions here
    // Token functions are generated by #[aztec]
}
```

When `compose_token` is set, `#[aztec]` will:
1. Skip `check_each_fn_macroified` for token functions (they are not in the source)
2. Directly call `generate_private_external()`, `generate_public_external()`, `generate_utility_external()` with synthetic `FunctionDefinition` objects for each token function
3. Inject token function implementations as `Quoted` code
4. Include token functions in dispatch, interface generation, and ABI exports

**Fallback (if synthetic FunctionDefinition is not possible)**: Generate dispatch/ABI code directly from known token function signatures, bypassing the registry mechanism.

**Deferred (M1)**: Native `inject_token!()` syntax at module scope, requiring:
- Add `MacroInvocation` variant to `TopLevelStatementKind` enum (`parser/mod.rs`)
- Add grammar rule in `top_level_statement_kind()` combinator (`parser/parser.rs`)
- Extend elaboration to process macro invocations in contract context (propagate `is_contract` flag)
- Wire to comptime system's `Quoted` blob re-parsing mechanism

### ADR-002: Token Logic Location

**Decision**: Extract token logic to a new `aztec-token-mixin` library in `aztec-nr`.

**Rationale**: 
- Single source of truth for token logic
- Can be imported by both plain token contracts AND composed contracts
- `NFR-2: Maintainability` — one canonical module, versioned with aztec-packages

**What goes in the library**:
- `TokenStorage<Context>` wrapper struct (re-exporting token storage fields)
- Public-context helpers: `increase_public_balance`, `decrease_public_balance`, `increase_total_supply`, `decrease_total_supply`
- Private-context helpers: `increase_private_balance`
- Validation: `_validate_minter` as a template-local `#[contract_library_method]`

**What stays in the composed contract** (generated by `#[aztec]` with `compose_token`):
- External function dispatch wrappers (ABI surface)
- `#[internal]` orchestration functions (calling library helpers)
- Storage initialization

### ADR-003: Storage Composition

**Decision**: Composed contract includes all token storage fields inline. No nested struct magic for v1.

**Implementation**: The AMM contract must declare a Storage struct containing both:
- App fields (`reserves`, `pool_id`, etc.)
- Token fields (name, symbol, decimals, private_balances, total_supply, public_balances, minter)

The `compose_token` machinery validates that these fields are present and correctly typed.

**Field naming**: Token fields are namespaced with the standard names (as in `token_contract`) — no prefix.

**Open question**: Exact storage layout strategy (documented, not blocking PoC).

### ADR-004: Internal Mint from LP (SC-3)

**Decision**: AMM's `add_liquidity` calls `self.internal._mint_to_private(to, shares)` which is available via composition.

**Requirements**:
- Minter must be initialized to `AztecAddress::this()` (self-minting)
- Initializer must call both pool setup AND token setup (name/symbol/decimals)
- `validate_minter` checks `self.storage.minter == self.msg_sender()`

**Auth pattern**: Since `add_liquidity` is an external function and it calls `_mint_to_private`
(which is reached from mint paths guarded by `validate_minter`), the minter check will see
`msg_sender() = contract_address` (the AMM), which matches the initialized `minter` value.

---

## Token API Surface (v4.2.0)

Full catalog from `aztec-standards/src/token_contract/src/main.nr`:

### Storage
```noir
name: PublicImmutable<FieldCompressedString, Context>
symbol: PublicImmutable<FieldCompressedString, Context>
decimals: PublicImmutable<u8, Context>
private_balances: Owned<BalanceSet<Context>, Context>
total_supply: PublicMutable<u128, Context>
public_balances: Map<AztecAddress, PublicMutable<u128, Context>, Context>
minter: PublicImmutable<AztecAddress, Context>
```

### Constants
```noir
global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;
global PRIVATE_ADDRESS_MAGIC_VALUE: AztecAddress = ...;
```

### Events
```noir
#[event] struct Transfer { from: AztecAddress, to: AztecAddress, amount: u128 }
```

### Initializers (`#[external("public")] #[initializer]`)
- `constructor_with_initial_supply(name, symbol, decimals, initial_supply, to)`
- `constructor_with_minter(name, symbol, decimals, minter)`

### External Private (`#[external("private")]`)
- `transfer_private_to_public(from, to, amount, _nonce)` — `#[authorize_once]`
- `transfer_private_to_private(from, to, amount, _nonce)` — `#[authorize_once]`
- `transfer_private_to_public_with_commitment(from, to, amount, _nonce) -> Field` — `#[authorize_once]`
- `transfer_private_to_commitment(from, commitment, amount, _nonce)` — `#[authorize_once]`
- `transfer_public_to_private(from, to, amount, _nonce)` — `#[authorize_once]`
- `initialize_transfer_commitment(to, completer) -> Field`
- `recurse_subtract_balance_internal(account, amount) -> u128` — `#[only_self]`
- `mint_to_private(to, amount)`
- `burn_private(from, amount, _nonce)` — `#[authorize_once]`

### External Public (`#[external("public")]`)
- `transfer_public_to_public(from, to, amount, _nonce)` — `#[authorize_once]`
- `transfer_public_to_commitment(from, commitment, amount, _nonce)` — `#[authorize_once]`
- `increase_public_balance_internal(to, amount)` — `#[only_self]`
- `decrease_public_balance_internal(from, amount)` — `#[only_self]`
- `balance_of_public(owner) -> u128` — `#[view]`
- `total_supply() -> u128` — `#[view]`
- `name() -> FieldCompressedString` — `#[view]`
- `symbol() -> FieldCompressedString` — `#[view]`
- `decimals() -> u8` — `#[view]`
- `mint_to_public(to, amount)`
- `mint_to_commitment(commitment, amount)`
- `increase_total_supply_internal(amount)` — `#[only_self]`
- `burn_public(from, amount, _nonce)` — `#[authorize_once]`
- `decrease_total_supply_internal(amount)` — `#[only_self]`

### External Utility (`#[external("utility")]`)
- `balance_of_private(owner) -> u128` — `unconstrained`

### Internal Private (`#[internal("private")]`)
- `_decrease_private_balance(account, amount, max_notes)`
- `_increase_private_balance(to, amount)`
- `_subtract_balance(account, amount, max_notes) -> u128`
- `_initialize_transfer_commitment(to, completer) -> PartialUintNote`
- `_mint_to_private(to, amount)`
- `_burn_private(from, amount)`

### Internal Public (`#[internal("public")]`)
- `_increase_public_balance(to, amount)`
- `_decrease_public_balance(from, amount)`
- `_increase_commitment_balance(commitment, completer, amount)`
- `_increase_total_supply(amount)`
- `_decrease_total_supply(amount)`
- `_mint_to_public(to, amount)`
- `_burn_public(from, amount)`

### Contract Library Methods (`#[contract_library_method]`)
- `_initial_transfer_call_max_notes()`
- `_recursive_transfer_call_max_notes()`
- `_private_address_magic_value()`

---

## Historical Investigation Notes

| ID | Issue | Impact | Status |
|----|-------|--------|--------|
| L-1 | Noir parser: no `MacroInvocation` in `TopLevelStatementKind` | Relevant only if reviving `inject_token!()` syntax | Historical, superseded by current `compose(...)` approach |
| L-2 | `Module::add_item()` timing vs `#[aztec]` registry reads | Relevant only for pre-macro injection designs | Historical, not used by current implementation |
| L-3 | Synthetic `FunctionDefinition` creation | Relevant only for synthetic-function composition designs | Historical, not used by current implementation |
| L-4 | Nested token storage wrapper under `#[storage]` | Prevents using nested `TokenStorage<Context>` today | Active limitation |
| L-6 | Single initializer must set up both token and pool state | Handled by host constructor calling `_initialize_token(...)` | Resolved in current PoC |
| L-7 | ABI/function-name collision between template and host methods | Still a real composition constraint | Active constraint; needs clearer diagnostics/docs |

---

---

### 2026-05-12 — M2: generic contract-template composition PoC — COMPLETE

**Achieved: SC-2 + SC-3 demonstrated. `Amm` compiles with 4 developer-written functions and 24 AIP-20 token functions generated automatically.**

#### What was built

**Modified `aztec-nr` files:**
- `aztec/src/macros/aztec.nr` — replaced token-only composition config with generic `compose("template-id")`; injects selected template functions before `check_each_fn_macroified`
- `aztec/src/macros/internals_functions_generation/external_functions_registry.nr` — composed external functions are merged into the host registries
- `aztec/src/macros/internals_functions_generation/internal_functions_registry.nr` — same pattern for composed internals
- `aztec/src/macros/mod.nr` — generic `#[contract_template("template-id")]` registration and template helper capture
- `aztec/src/macros/template_registry.nr` — keyed template registry replacing the old token singleton
- `aztec/src/macros/compose_template.nr` — generic retrieval/injection of selected template quotes
- `aztec/src/macros/events.nr` — `register_event_selector` made idempotent for same-name re-registration

**Template consumer added:**
- `src/aztec-token-mixin/src/token_contract_template/mod.nr` — AIP-20 token template registered via `#[contract_template("aip20_token")]`

**New `aztec-token-mixin/src/lib.nr`** — added `pub mod token_contract_template`

**New `Amm` contract (`src/amm_token/src/main.nr`):**
```noir
#[aztec(AztecConfig::new().compose("aip20_token"))]
pub contract Amm {
    // storage: token fields (inlined, L-4) + pool fields
    
    #[external("public")] #[initializer]
    fn constructor(token_a, token_b, name, symbol, decimals) { ... }
    
    #[external("private")]
    fn add_liquidity(provider, amount_a, amount_b) {
        self.internal._mint_to_private(provider, shares);  // SC-3
        self.enqueue_self.update_reserves_internal(amount_a, amount_b);
    }
    
    #[external("public")] #[only_self]
    fn update_reserves_internal(amount_a, amount_b) { ... }
    
    #[external("public")] #[view]
    fn get_reserves() -> (u128, u128) { ... }
    
    // AIP-20 token functions NOT written here - generated by template composition
}
```

#### Composition mechanism (how it works)

1. `aztec-token-mixin` registers `TokenContractTemplate` via `#[contract_template("aip20_token")]` during template crate elaboration
2. `#[aztec(AztecConfig::new().compose("aip20_token"))]` on `Amm` injects that template's function definitions into the host registries before `check_each_fn_macroified`
3. The host generators (`process_functions`, `generate_call_internal_struct`, `generate_public_dispatch`, `generate_contract_interface`, `create_fn_abi_exports`) then see the union of host-defined and composed functions
4. The pre-generated quoted wrappers, ABI exports, and template-local `#[contract_library_method]` helpers are replayed into the host from the keyed template registry
5. Composed function bodies still reference `self.storage.*`, which re-resolves correctly in the host module context

#### Generated ABI (confirmed)

| Category | Count | Functions |
|----------|-------|-----------|
| AMM-authored (private) | 1 | `add_liquidity` |
| AMM-authored (public) | 3 | `constructor`, `update_reserves_internal`, `get_reserves` |
| Token-composed (private) | 9 | `burn_private`, `initialize_transfer_commitment`, `mint_to_private`, `recurse_subtract_balance_internal`, `transfer_private_to_*` (5) |
| Token-composed (public) | 14 | `balance_of_public`, `burn_public`, `decimals`, `decrease_*_internal` (2), `increase_*_internal` (2), `mint_to_*` (3), `name`, `symbol`, `total_supply`, `transfer_public_to_*` (2) |
| Token-composed (utility) | 1 | `balance_of_private` |
| Infrastructure | 3 | `public_dispatch`, `sync_state`, `offchain_receive` |

#### Known limitations and open issues (updated)

| ID | Issue | Status |
|----|-------|--------|
| L-4 | Nested struct in `#[storage]` not supported — token fields must be inlined in host storage | Open, Aztec-side work |
| L-11 | `FromField` trait import required in host contract for composed function bodies to resolve `PartialUintNote::from_field(commitment)` — DX issue | Workaround in `main.nr` |
| L-12 | `only_self` import must be in host contract's `use aztec::macros::functions` block even if host doesn't use it | Workaround in `main.nr` |
| L-7 | ABI/function-name collision between template and host methods | Open constraint; currently fails at compile time, but docs/diagnostics should be better |

#### Resolved / closed notes

| ID | Note | Status |
|----|------|--------|
| L-9 | Extracting `private_actions.nr` / `public_actions.nr` as reusable state-touching libraries is not desired for this repo | Closed, not pursuing |
| L-10 | `Transfer` event must be declared in the host contract AND is defined in `TokenContractTemplate` | Fixed in `events.nr` via idempotent selector registration |
| L-13 | Token template initializers were not originally composed | Fixed via composed `_initialize_token(TokenInitParams)` |

#### Historical implementation note

- `recurse_subtract_balance_internal` is a deliberate private self-call pattern, not an active limitation.
  It exists so `_subtract_balance` can retry through a private `#[only_self]` entrypoint with a larger
  note budget when the initial subtraction pass is insufficient.

## Next Steps (M3)

1. Port token parity tests from `aztec-standards/token_contract/src/test/` to `src/amm_token/src/test/`
2. Write `add_liquidity` + LP mint test fixture (SC-3 acceptance test):
   - Deploy `Amm`, call `add_liquidity`, assert `balance_of_private(provider) > 0`
   - Assert `total_supply` increased
3. Port all transfer tests (private/public/commitment paths) against `Amm`
4. Port minter auth tests: only `self.address` can call `mint_to_private` directly, and AMM's internal mint path is valid
5. Document what needs to change in `aztec-nr` to remove workarounds L-11 / L-12

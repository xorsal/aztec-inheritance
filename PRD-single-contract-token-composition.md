# PRD: Inheritance-like token composition for Aztec contracts (Noir mixins + Aztec integration)

**Status:** Draft for implementation exploration  
**Audience:** Noir compiler team, Aztec `aztec-nr` / standards maintainers  
**Scope:** End-to-end ability for a **single deployed contract** (e.g. an AMM) to **behave as a full AIP-20-style token**—**full external surface + shared token internals**—without hand-copying the entire token implementation. **Noir** changes supply the **authoring mechanism** (decl-macros / mixin items in `contract { }`); **Aztec** changes supply **composition policy** (storage layout, `#[aztec]` / `process_functions`, safe reuse of `#[internal]` token paths).

---

## 1. Executive summary

### 1.1 Problem

Standards consumers (AMM, lending pool, game economy, etc.) need contracts that are **also** fungible tokens: same address, same artifact, indexers and wallets see a normal token API, while app-specific entrypoints (e.g. `add_liquidity`) must drive **token state transitions** (mint to LP, burn on withdraw) **without re-implementing** balance math, note handling, enqueue sequences, and auth patterns.

Today that implies one of:

- **Massive duplication** of `token_contract` (externals + internals + storage shape), or  
- **External codegen** merging snippets, or  
- **Split deployments** (separate `Token` address), which breaks the “this contract is the token” product story.

Underlying technical gaps:

1. **Noir:** Module / `contract { }` bodies have **no** first-class slot for **decl-macro invocations** (`inject_full_token!();`), so composition cannot live in source as a maintained mixin.
2. **Noir:** Comptime `add_item` / unquote paths **reject** several item kinds (e.g. nested `SubModule`), constraining how much can be injected post-parse without language support.
3. **Aztec:** `#[aztec]` assumes a **single coherent** module of `#[external]` / `#[internal]` / `#[contract_library_method]` definitions tied to **one** storage layout and dispatch graph. “Paste two contracts together” naïvely breaks `process_functions`, dispatch, and ABI unless composition is **designed**.

### 1.2 Product goal

Deliver an **inheritance-like** authoring and compilation story:

- A developer writes an app contract (e.g. `Amm`) and **opts into the full token** via a **small, stable surface** (one or few mixin invocations / attributes—not thousands of lines of copy-paste).
- The resulting artifact exposes the **complete** token **public API** expected by tooling and AIP-20-style tests (mints, burns, transfers across private/public/commitment as applicable—not a two-method proof of concept).
- **App entrypoints** can call **token-internal** behavior (e.g. mint when an LP deposits) by reusing the **same** internal / enqueue patterns as `token_contract`, with **clear rules** for who may mint, initialization, and minter permissions.

### 1.3 Non-goals

- **Optional surface syntax** such as `contract Amm: Token { }` — not required for the first shippable vertical if mixins / attributes achieve the same semantics; can remain a follow-on language sugar.
- **Protocol / kernel opcode changes** — not assumed; composition should work within current Aztec private/public/utility models unless discovery proves otherwise.
- **Defining AIP-20 normative text** — this PRD targets **implementation and DX**; spec text lives in AIP / forum.

---

## 2. Motivation and flagship use case

### 2.1 Flagship: AMM “is a” token

**User story:** As an AMM author, I deploy **one** contract. It is the liquidity pool **and** the LP token. When a user adds liquidity, my `add_liquidity` path **mints** LP token balances using the **same invariants and implementation strategy** as the canonical `Token` contract (notes, `BalanceSet`, public enqueue, minter rules), without maintaining a forked copy of every token function.

**Acceptance hints:**

- Token **externals** are present and pass existing token-style tests (or a defined subset mapped to this vertical).
- `add_liquidity` (or equivalent) calls into **shared** mint / balance increase logic—either generated wrappers around canonical `#[internal]` patterns or a formally supported “compose token internals” path in `aztec-nr`.

### 2.2 Secondary use cases

- **Vault share token**, **lending receipt token**, **game currency** with custom `play_turn` but standard transfer/mint/burn.
- **Access-control or pause mixins** emitted alongside token surface (same mechanism).

### 2.3 Success criteria (measurable)

| # | Criterion |
|---|-----------|
| **SC-1** | **Noir:** Decl-macro (or equivalent) **module items** inside `contract { }` parse, expand in a documented order, and yield **first-class** `fn` / `struct` / `global` / `impl` items that `#[aztec]` consumes indistinguishably from handwritten items (modulo naming policy). |
| **SC-2** | **Token completeness:** Composed contract includes the **full** intended token **external** surface for the target standard (not a minimal stub); exact list is versioned with the mixin / `aztec-nr` release (derive from current `token_contract` in `standards` / `aztec-packages`). |
| **SC-3** | **Internal reuse:** At least one **app-only** `#[external]` demonstrates calling **token-equivalent internal** behavior (e.g. mint-on-LP) without duplicating the full private balance implementation by hand. |
| **SC-4** | **Storage:** Documented and tested **layout strategy** so token fields (`name`, `symbol`, `private_balances`, `minter`, …) coexist with app fields (`reserves`, `pool_id`, …) without undefined overlap; migrations / versioning story referenced. |
| **SC-5** | **Safety / DX:** Stable diagnostics for duplicate symbols, bad ordering, unsupported expanded items, and **permission** mistakes (e.g. mint callable from wrong context). |
| **SC-6** | **Performance:** Compile time and circuit constraints remain acceptable for token-scale expansion (profile mixin + `#[aztec]` on representative AMM-sized contracts). |

---

## 3. Background (constraints to respect)

### 3.1 Noir parser and AST

- `top_level_statement_kind` has **no** production for top-level `ident!();` inside modules / contracts.
- `TopLevelStatementKind` has **no** macro-invocation variant at module scope.

### 3.2 Noir elaboration (`add_item`)

- Unquoted / macro-added top-level items: only a **subset** of kinds is supported today (`fn`, `struct`, `global`, non-trait `impl`, etc.); **nested `contract` / `mod`**, `use`, `trait`, … are rejected with `UnsupportedTopLevelItemUnquote`.
- **Implication:** “Import whole `Token` as nested contract” is not the default path; **flattened** emission of token-shaped items into the **parent** contract module is the primary mechanical story unless `add_item` is explicitly extended with new semantics.

### 3.3 Aztec (`#[aztec]`)

- `check_each_fn_macroified` requires every function in the contract module to carry supported attributes (`#[external]`, `#[internal]`, `#[contract_library_method]`, `#[test]`).
- `process_functions` and dispatch tie generated internals to **this** module’s externals—composition must preserve **one** coherent dispatch and storage story.
- **Private balance / note recursion:** prior art in this repo shows that **deep nesting** of private self-calls into balance decrease can break compile-time bounds; mixin design must **preserve** known-good patterns (entrypoint vs second-leg splits), not blindly duplicate risky call graphs.

### 3.4 Attribute names vs provenance

- `has_named_attribute("external")` is **name-based**; mixins must still attach the **real** Aztec `#[external]` / `#[internal]` macros so codegen matches expectations.

---

## 4. Requirements

### 4.1 Noir (mechanism)

| ID | Requirement |
|----|-------------|
| **N-FR-1** | Support **decl-macro invocations** (or an attribute with identical power) as **first-class items** in **`mod { }` and `contract { }`** bodies, with deterministic grammar and `nargo fmt` behavior. |
| **N-FR-2** | Specify **expansion order** relative to `use`, other items, and **module-level attributes** (`#[aztec]`) so generated token `fn`s exist before Aztec consumes the module. |
| **N-FR-3** | Generated items participate in **name resolution**, **attribute expansion**, and **comptime** the same as handwritten items. |
| **N-FR-4** | Diagnostics: macro call site ↔ expanded spans; duplicate definition errors; unsupported item kinds **explicitly** listed for contract bodies. |

### 4.2 Aztec and standards (token vertical)

| ID | Requirement |
|----|-------------|
| **A-FR-1** | **Full token surface:** The composed contract’s ABI / call interface includes **all** token entrypoints required by the chosen standard version (align with `token_contract` in this repo or canonical package in `aztec-packages`). |
| **A-FR-2** | **Storage composition:** A single `#[storage] struct` (or officially supported composite pattern) contains **both** token and app fields with **documented field ownership**, no accidental aliasing, and guidance for upgrades. |
| **A-FR-3** | **Internal reuse:** App `#[external]` or `#[internal]` code can invoke **token mint / transfer / balance** logic through **supported** paths (`#[internal]` wrappers, `enqueue_self`, shared libraries)—with **documented** permission model (e.g. minter = self, only_self shims, initializer ordering). |
| **A-FR-4** | **One coherent `#[aztec]` pass:** After expansion, `process_functions`, interface generation, and dispatch remain correct; no duplicate conflicting `__aztec_nr_internals__` wiring. |
| **A-FR-5** | **Conformance tests:** Either port a **representative subset** of `token_contract` tests to a **composed** “AMM + token” fixture, or add new integration tests proving parity on critical paths (mint, transfer private/public, minter auth). |

### 4.3 Non-functional

| ID | Requirement |
|----|-------------|
| **NFR-1** | **Determinism:** Same sources → same expanded AST (no hidden FS dependence in default mixins). |
| **NFR-2** | **Maintainability:** Token mixin source of truth is **one** canonical module / crate revision; apps pin a version. |
| **NFR-3** | **Security review:** Minter role, `only_self`, initializer, and **reentrancy** / phase-change hazards documented for “mint from LP” patterns. |

### 4.4 Explicit deferrals (document, do not block first vertical)

- **Hygienic gensyms** for every generated symbol vs **prefix convention** — pick one for v1 and document.
- **Broadening `add_item`** beyond current allowed kinds — only if flattened emission is insufficient.

---

## 5. Design space (implementation must record decisions)

### 5.1 Authoring syntax

Options: Rust-like `inject_full_token!();`, contract-level `#[compose_token]`, or hybrid. Decision must address stacking with `#[aztec]` and with `#[storage]`.

### 5.2 Where token logic lives

| Strategy | Idea | Tradeoff |
|----------|------|----------|
| **Flattened emission** | Mixin expands to full set of `#[external]` / `#[internal]` / helpers in parent module | Large expansion; must dedupe names; closest to “rewrite token in place” |
| **Library + thin wrappers** | Canonical logic in `aztec-nr` or shared crate; mixin emits mostly thin `#[external]` calling shared `#[internal]` | Smaller expansion; requires **public** internal API design for composition |
| **`#[aztec]` compose hook** | Aztec merges codegen from a **template** `Module` without naïvely aliasing wrong dispatch | Centralized; more `aztec-nr` work; may reduce Noir surface if mixins only mark intent |

**Deliverable:** written ADR choosing primary strategy + fallback.

### 5.3 Storage

- **Single struct** with namespaced field names vs **nested struct** fields vs generated layout macro — must satisfy `STORAGE_LAYOUT_NAME` / `#[storage]` rules in `aztec-nr`.

### 5.4 Internal mint from LP

- Explicit pattern: e.g. minter initialized to `this` address, `add_liquidity` calls `self.internal._mint_to_private(...)` (or composed equivalent); document **initializer** and **auth** requirements.

---

## 6. Test plan (acceptance)

### 6.1 Noir

- Macro expands to **large** item sets without parser / elaboration failure.
- Ordering: `use` / `global` / generated `fn` / hand-written `fn` interactions per spec.
- Negative: duplicate `transfer_private_to_public` name, bad forward reference.

### 6.2 Aztec — token parity

- Composed contract passes (or matches behavior of) **full** token integration tests relevant to the shipped surface—not two methods.
- **Interface struct** exposes full selector set for composed token API.

### 6.3 Aztec — AMM slice (flagship)

- Fixture: `AmmAsToken` (name TBD) with **pool storage + full token storage**, `add_liquidity` that **mints** LP representation via token-internal path.
- Assert balances / supply / events (or private-side equivalents) per existing test utilities in `standards`.

### 6.4 Regression / hazards

- Cases mirroring known pitfalls: **nested private** balance paths, `only_self` enqueue completion, minter unset vs set.

---

## 7. Milestones (suggested)

| Milestone | Deliverable |
|-----------|-------------|
| **M0** | ADR: syntax + expansion order + storage strategy + internal-reuse pattern for LP mint. |
| **M1** | Noir: parser + AST + fmt for mixin items in `contract { }`. |
| **M2** | Noir: elaboration integration; mixin emits **full** token-shaped item set in isolation (non-Aztec or minimal `#[aztec]` harness). |
| **M3** | Aztec: composed contract passes **full** token test matrix (or agreed parity subset) + **AMM + LP mint** fixture. |
| **M4** | Docs, migration guide for standards authors, performance pass, security notes. |

---

## 8. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Dispatch / ABI mismatch when merging token + app | ADR + `process_functions` audit; golden ABI diff vs plain `Token` |
| Storage overlap / layout bugs | Layout tests; `storage_layout()` assertions where applicable |
| Private circuit compile bound blowups | Preserve entrypoint vs helper split documented in token standards |
| **Security:** unauthorized mint | Minter + `only_self` + initializer checklist in PR + docs |
| Compile-time / IDE memory | Chunk expansion, caching, optional “slim token” profile **only** if full vertical too heavy (document tradeoff) |

---

## 9. Open questions

1. **Minter model:** Self-mint only vs delegated minter; how does composed AMM revoke / rotate?
2. **Events:** Single `Transfer` stream interleaving app-specific events—indexer contract?
3. **Upgrade path:** When canonical `token_contract` changes, how do composed apps rebaseline?
4. **Partial composition:** Is “token without commitment path” a supported profile, or must parity be total?

---

## 10. References

- Noir: `compiler/noirc_frontend/src/parser/parser.rs`, `parser/mod.rs`, `elaborator/comptime.rs`, `hir/comptime/value.rs`.
- Aztec: `noir-projects/aztec-nr/aztec/src/macros/aztec.nr`, `internals_functions_generation/`, `storage.nr`, `dispatch.nr`.
- This repo: `src/token_contract/` (canonical behavior + tests), `MACROS_AND_AZTEC_LIMITATIONS.md`.

---

## 11. Agent handoff checklist

- [ ] ADR locked: **full token** surface list + storage + internal reuse pattern (LP mint).
- [ ] Noir mixin grammar + expansion order implemented and tested.
- [ ] `#[aztec]` + storage + dispatch validated on **composed** contract—not minimal stub.
- [ ] **Full** token parity tests (or agreed matrix) + **AMM LP mint** fixture green.
- [ ] Security / permission doc for mint-from-app-path reviewed.
- [ ] User-facing “how to compose a token into your contract” guide (standards or `aztec-packages` docs).

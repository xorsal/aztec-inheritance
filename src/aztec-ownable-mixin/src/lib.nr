pub mod ownable_contract_template;

// Re-export the `only_owner` comptime attribute so hosts can write
// `use aztec_ownable_mixin::only_owner;` and apply it as `#[only_owner]`.
// The attribute itself lives in vendor/aztec-nr alongside #[authorize_once]
// because cross-crate `f.body()` mutation is blocked - the check is woven
// in by #[external("public")]'s body re-emitter.
pub use aztec::macros::functions::only_owner;

pub mod ownable_contract_template;

// The `#[only_owner]` comptime attribute is added by a follow-up commit
// that patches vendor/aztec-nr (it must live there because cross-crate
// body mutation is blocked - see ROADMAP).

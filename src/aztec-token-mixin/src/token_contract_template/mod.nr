use aztec::macros::{aztec, contract_template};

/// The token contract template used by generic contract composition.
///
/// This contract contains all AIP-20 token functions. When a contract uses
/// `#[aztec(AztecConfig::new().compose("aip20_token"))]`, all functions defined here are injected into the
/// host contract as if the developer had written them directly.
///
/// Attribute execution order (Noir applies attributes top-to-bottom for modules):
/// 1. `#[contract_template("aip20_token")]` runs first - captures function bodies as Quoted and
///    stores them in the global template registry BEFORE `#[aztec]` has disabled the functions.
/// 2. `#[aztec]` runs second - processes the template as a normal contract (needed so that `self`
///    is in scope for type-checking of the function bodies).
///
/// IMPORTANT: All type references in function bodies use fully-qualified paths so that the
/// captured Quoted resolves correctly when injected into the host contract's scope.
#[contract_template("aip20_token")]
#[aztec]
pub contract TokenContractTemplate {
    use aztec::{
        macros::{
            events::event,
            functions::{authorize_once, external, internal, only_self, view},
            storage::storage,
        },
        messages::message_delivery::MessageDelivery,
        protocol::{address::AztecAddress, traits::{FromField, ToField}},
        state_vars::{Map, Owned, PublicImmutable, PublicMutable, StateVariable},
    };
    use uint_note::{PartialUintNote, UintNote};
    use compressed_string::FieldCompressedString;
    use balance_set::BalanceSet;
    use crate::token_init_params::TokenInitParams;

    #[event]
    struct Transfer {
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
    }

    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals of the token
    /// @param private_balances The private balances of the token
    /// @param total_supply The total supply of the token
    /// @param public_balances The public balances of the token
    /// @param minter The account permissioned to mint the token
    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        private_balances: Owned<BalanceSet<Context>, Context>,
        total_supply: PublicMutable<u128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<u128, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
    }

    /** ==========================================================
    * ========================= PRIVATE =========================
    * ======================================================== */

    /// @notice Transfer tokens from private balance to public balance
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._decrease_private_balance(from, amount, _initial_transfer_call_max_notes());

        self.enqueue_self.increase_public_balance_internal(to, amount);
    }

    /// @notice Transfer tokens from private balance to public balance and initializes a commitment
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_public_with_commitment(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) -> Field {
        self.internal._decrease_private_balance(from, amount, _initial_transfer_call_max_notes());

        self.enqueue_self.increase_public_balance_internal(to, amount);

        let completer = self.msg_sender();
        let commitment = self.internal._initialize_transfer_commitment(to, completer);
        aztec::protocol::traits::ToField::to_field(commitment)
    }

    /// @notice Transfer tokens from private balance to another private balance
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._decrease_private_balance(from, amount, _initial_transfer_call_max_notes());

        self.internal._increase_private_balance(to, amount);
    }

    /// @notice Transfer tokens from a private balance to the recipient commitment
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_commitment(
        from: AztecAddress,
        commitment: Field,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._decrease_private_balance(from, amount, _initial_transfer_call_max_notes());

        let completer = self.msg_sender();
        uint_note::PartialUintNote::from_field(commitment).complete_from_private(
            self.context,
            completer,
            self.storage.private_balances.get_storage_slot(),
            amount,
        );
    }

    /// @notice Transfer tokens from public balance to private balance
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        self.enqueue_self.decrease_public_balance_internal(from, amount);

        self.internal._increase_private_balance(to, amount);
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    #[external("private")]
    fn initialize_transfer_commitment(to: AztecAddress, completer: AztecAddress) -> Field {
        let commitment = self.internal._initialize_transfer_commitment(to, completer);
        aztec::protocol::traits::ToField::to_field(commitment)
    }

    /// @notice Recursively subtracts balance from private balance
    #[external("private")]
    #[only_self]
    fn recurse_subtract_balance_internal(account: AztecAddress, amount: u128) -> u128 {
        self.internal._subtract_balance(account, amount, _recursive_transfer_call_max_notes())
    }

    /** ==========================================================
    * ========================= PUBLIC ==========================
    * ======================================================== */

    /// @notice Transfers tokens from public balance to public balance
    #[authorize_once("from", "_nonce")]
    #[external("public")]
    fn transfer_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._decrease_public_balance(from, amount);
        self.internal._increase_public_balance(to, amount);

        self.emit(Transfer { from, to, amount });
    }

    /// @notice Finalizes a transfer of token amount from public balance of from to a commitment of to
    #[authorize_once("from", "_nonce")]
    #[external("public")]
    fn transfer_public_to_commitment(
        from: AztecAddress,
        commitment: Field,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._decrease_public_balance(from, amount);

        let completer = self.msg_sender();
        self.internal._increase_commitment_balance(
            uint_note::PartialUintNote::from_field(commitment),
            completer,
            amount,
        );

        self.emit(Transfer { from, to: _private_address_magic_value(), amount });
    }

    /// @notice Increases the public balance of to by amount
    #[external("public")]
    #[only_self]
    fn increase_public_balance_internal(to: AztecAddress, amount: u128) {
        self.internal._increase_public_balance(to, amount);

        self.emit(Transfer { from: _private_address_magic_value(), to, amount });
    }

    /// @notice Decreases the public balance of from by amount
    #[external("public")]
    #[only_self]
    fn decrease_public_balance_internal(from: AztecAddress, amount: u128) {
        self.internal._decrease_public_balance(from, amount);

        self.emit(Transfer { from, to: _private_address_magic_value(), amount });
    }

    /** ==========================================================
    * ====================== VIEW FUNCTIONS =====================
    * ======================================================== */

    /// @notice Returns the public balance of owner
    #[external("public")]
    #[view]
    fn balance_of_public(owner: AztecAddress) -> u128 {
        self.storage.public_balances.at(owner).read()
    }

    /// @notice Returns the total supply of the token
    #[external("public")]
    #[view]
    fn total_supply() -> u128 {
        self.storage.total_supply.read()
    }

    /// @notice Returns the name of the token
    #[external("public")]
    #[view]
    fn name() -> compressed_string::FieldCompressedString {
        self.storage.name.read()
    }

    /// @notice Returns the symbol of the token
    #[external("public")]
    #[view]
    fn symbol() -> compressed_string::FieldCompressedString {
        self.storage.symbol.read()
    }

    /// @notice Returns the decimals of the token
    #[external("public")]
    #[view]
    fn decimals() -> u8 {
        self.storage.decimals.read()
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    /// @notice Returns the private balance of an account
    #[external("utility")]
    unconstrained fn balance_of_private(owner: AztecAddress) -> u128 {
        self.storage.private_balances.at(owner).balance_of()
    }

    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    /// @notice Mints tokens to a private balance
    #[external("private")]
    fn mint_to_private(to: AztecAddress, amount: u128) {
        _validate_minter(
            self.msg_sender(),
            self.storage.minter.read(),
        );

        self.internal._mint_to_private(to, amount);
    }

    /// @notice Mints tokens to an address publicly
    #[external("public")]
    fn mint_to_public(to: AztecAddress, amount: u128) {
        _validate_minter(
            self.msg_sender(),
            self.storage.minter.read(),
        );

        self.internal._mint_to_public(to, amount);
    }

    /// @notice Finalizes a mint to a commitment
    #[external("public")]
    fn mint_to_commitment(commitment: Field, amount: u128) {
        let completer = self.msg_sender();
        _validate_minter(completer, self.storage.minter.read());
        self.internal._increase_total_supply(amount);
        self.internal._increase_commitment_balance(
            uint_note::PartialUintNote::from_field(commitment),
            completer,
            amount,
        );

        self.emit(Transfer {
            from: AztecAddress::zero(),
            to: _private_address_magic_value(),
            amount,
        });
    }

    /// @notice Internal function to increase the total supply by amount
    #[external("public")]
    #[only_self]
    fn increase_total_supply_internal(amount: u128) {
        self.internal._increase_total_supply(amount);

        self.emit(Transfer {
            from: AztecAddress::zero(),
            to: _private_address_magic_value(),
            amount,
        });
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    /// @notice Burns tokens from a private balance
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn burn_private(from: AztecAddress, amount: u128, _nonce: Field) {
        self.internal._burn_private(from, amount);
    }

    /// @notice Burns tokens from a public balance
    #[authorize_once("from", "_nonce")]
    #[external("public")]
    fn burn_public(from: AztecAddress, amount: u128, _nonce: Field) {
        self.internal._burn_public(from, amount);
    }

    /// @notice Decreases the total supply by amount
    #[external("public")]
    #[only_self]
    fn decrease_total_supply_internal(amount: u128) {
        self.internal._decrease_total_supply(amount);

        self.emit(Transfer {
            from: _private_address_magic_value(),
            to: AztecAddress::zero(),
            amount,
        });
    }

    /** ==========================================================
     * ==================== INITIALIZATION ======================
     * ======================================================== */

    /// Initializes the token storage fields in public context.
    ///
    /// Call this from the host constructor via `self.internal._initialize_token(params)`.
    /// The host is responsible for setting `params.minter` to the appropriate address.
    #[internal("public")]
    fn _initialize_token(params: TokenInitParams) {
        self.storage.name.initialize(
            compressed_string::FieldCompressedString::from_string(params.name),
        );
        self.storage.symbol.initialize(
            compressed_string::FieldCompressedString::from_string(params.symbol),
        );
        self.storage.decimals.initialize(params.decimals);
        self.storage.minter.initialize(params.minter);
    }

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    /// @notice gas-optimized max notes for initial transfer call
    #[contract_library_method]
    fn _initial_transfer_call_max_notes() -> u32 {
        2
    }

    /// @notice max notes transfer for recursive transfer call if initial max notes are exceeded
    #[contract_library_method]
    fn _recursive_transfer_call_max_notes() -> u32 {
        8
    }

    /// @notice Sentinel address used in Transfer events to represent the private side of a balance change.
    #[contract_library_method]
    fn _private_address_magic_value() -> AztecAddress {
        AztecAddress::from_field(0x1ea7e01501975545617c2e694d931cb576b691a4a867fed81ebd3264)
    }

    /// @notice Restricts minting to the configured minter.
    #[contract_library_method]
    fn _validate_minter(sender: AztecAddress, minter: AztecAddress) {
        assert(minter.eq(sender), "caller is not minter");
    }

    /// @notice Decreases the private balance of account by amount
    #[internal("private")]
    fn _decrease_private_balance(account: AztecAddress, amount: u128, max_notes: u32) {
        let change = self.internal._subtract_balance(account, amount, max_notes);
        self.storage.private_balances.at(account).add(change).deliver(
            aztec::messages::message_delivery::MessageDelivery.ONCHAIN_CONSTRAINED,
        );
    }

    /// @notice Increases the private balance of to by amount
    #[internal("private")]
    fn _increase_private_balance(to: AztecAddress, amount: u128) {
        self.storage.private_balances.at(to).add(amount).deliver(
            aztec::messages::message_delivery::MessageDelivery.ONCHAIN_CONSTRAINED,
        );
    }

    /// @notice Increases the public balance of to by amount
    #[internal("public")]
    fn _increase_public_balance(to: AztecAddress, amount: u128) {
        let new_balance = self.storage.public_balances.at(to).read() + amount;
        self.storage.public_balances.at(to).write(new_balance);
    }

    /// @notice Decreases the public balance of from by amount
    #[internal("public")]
    fn _decrease_public_balance(from: AztecAddress, amount: u128) {
        let new_balance = self.storage.public_balances.at(from).read() - amount;
        self.storage.public_balances.at(from).write(new_balance);
    }

    /// @notice Completes a partial note and increases the balance of the commitment by amount
    #[internal("public")]
    fn _increase_commitment_balance(
        commitment: uint_note::PartialUintNote,
        completer: AztecAddress,
        amount: u128,
    ) {
        commitment.complete(
            self.context,
            completer,
            self.storage.private_balances.get_storage_slot(),
            amount,
        );
    }

    /// @notice Subtracts balance from private balance, recursively if necessary
    #[internal("private")]
    fn _subtract_balance(account: AztecAddress, amount: u128, max_notes: u32) -> u128 {
        let subtracted = self.storage.private_balances.at(account).try_sub(amount, max_notes);
        if subtracted >= amount {
            subtracted - amount
        } else {
            assert(subtracted > 0, "Balance too low");

            let remaining = amount - subtracted;

            self.call_self.recurse_subtract_balance_internal(account, remaining)
        }
    }

    /// @notice Increases the total supply by amount
    #[internal("public")]
    fn _increase_total_supply(amount: u128) {
        let new_supply = self.storage.total_supply.read() + amount;
        self.storage.total_supply.write(new_supply);
    }

    /// @notice Decreases the total supply by amount
    #[internal("public")]
    fn _decrease_total_supply(amount: u128) {
        let new_supply = self.storage.total_supply.read() - amount;
        self.storage.total_supply.write(new_supply);
    }

    /// @notice Initializes a transfer commitment to be used for transfers/mints
    #[internal("private")]
    fn _initialize_transfer_commitment(
        to: AztecAddress,
        completer: AztecAddress,
    ) -> uint_note::PartialUintNote {
        let commitment = uint_note::UintNote::partial(to, self.context, to, completer);

        commitment
    }

    /// @notice Mints tokens to a public balance and increases the total supply
    #[internal("public")]
    fn _mint_to_public(to: AztecAddress, amount: u128) {
        self.internal._increase_public_balance(to, amount);
        self.internal._increase_total_supply(amount);

        self.emit(Transfer { from: AztecAddress::zero(), to, amount });
    }

    /// @notice Mints tokens to a private balance and enqueues a public call to increase the total supply
    #[internal("private")]
    fn _mint_to_private(to: AztecAddress, amount: u128) {
        self.internal._increase_private_balance(to, amount);
        self.enqueue_self.increase_total_supply_internal(amount);
    }

    /// @notice Burns tokens from a public balance and decreases the total supply
    #[internal("public")]
    fn _burn_public(from: AztecAddress, amount: u128) {
        self.internal._decrease_public_balance(from, amount);
        self.internal._decrease_total_supply(amount);

        self.emit(Transfer { from, to: AztecAddress::zero(), amount });
    }

    /// @notice Burns tokens from a private balance and enqueues a public call to decrease the total supply
    #[internal("private")]
    fn _burn_private(from: AztecAddress, amount: u128) {
        self.internal._decrease_private_balance(from, amount, _initial_transfer_call_max_notes());
        self.enqueue_self.decrease_total_supply_internal(amount);
    }
}

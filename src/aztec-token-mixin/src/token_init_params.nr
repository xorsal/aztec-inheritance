use aztec::protocol::address::AztecAddress;

/// Parameters for initializing the composed token storage fields.
///
/// Passed to `self.internal._initialize_token(params)` from the host constructor.
/// The host is responsible for choosing `minter` -- the token template imposes no default.
///
/// ## Example
///
/// ```noir
/// use aztec_token_mixin::TokenInitParams;
///
/// #[initializer]
/// #[external("public")]
/// fn constructor(token_a: AztecAddress, token_b: AztecAddress, name: str<31>, symbol: str<31>, decimals: u8) {
///     self.internal._initialize_token(TokenInitParams {
///         name,
///         symbol,
///         decimals,
///         minter: some_address,
///     });
///     // ... host-specific initialization
/// }
/// ```
pub struct TokenInitParams {
    pub name: str<31>,
    pub symbol: str<31>,
    pub decimals: u8,
    pub minter: AztecAddress,
}

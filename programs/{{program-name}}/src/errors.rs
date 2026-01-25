use anchor_lang::prelude::*;

#[error_code]
pub enum ErrorCode {
    #[msg("Unauthorized access")]
    Unauthorized,

    #[msg("Already initialized")]
    AlreadyInitialized,

    #[msg("Invalid parameter")]
    InvalidParameter,
}

use anchor_lang::prelude::*;

#[account]
#[derive(InitSpace)]
pub struct Config {
    /// The authority that can update the config
    pub authority: Pubkey,

    /// Bump seed for PDA derivation
    pub bump: u8,
}

impl Config {
    pub const SEED: &'static [u8] = b"config";
}

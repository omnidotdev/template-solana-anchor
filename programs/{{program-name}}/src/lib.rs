use anchor_lang::prelude::*;

pub mod errors;
pub mod instructions;
pub mod state;

use instructions::*;

#[cfg(not(feature = "no-entrypoint"))]
use solana_security_txt::security_txt;

declare_id!("11111111111111111111111111111111");

#[cfg(not(feature = "no-entrypoint"))]
security_txt! {
    name: "{{project-name}}",
    project_url: "https://example.com",
    contacts: "email:security@example.com",
    policy: "https://example.com/security",
    source_code: "https://github.com/example/{{project-name}}"
}

#[program]
pub mod {{program-name}} {
    use super::*;

    /// Initialize the program configuration
    /// Can only be called once per program deployment
    pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
        instructions::initialize::handler(ctx)
    }
}

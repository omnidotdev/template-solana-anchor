import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import * as anchor from "@coral-xyz/anchor";
import { Keypair, PublicKey } from "@solana/web3.js";

async function main() {
  const rpcUrl = process.env.ANCHOR_PROVIDER_URL || "http://localhost:8899";
  const walletPath = process.env.ANCHOR_WALLET || homedir() + "/.config/solana/id.json";
  const keypairData = JSON.parse(readFileSync(walletPath, "utf-8"));
  const wallet = new anchor.Wallet(Keypair.fromSecretKey(new Uint8Array(keypairData)));
  const connection = new anchor.web3.Connection(rpcUrl, "confirmed");
  const provider = new anchor.AnchorProvider(connection, wallet, { commitment: "confirmed" });

  const programId = new PublicKey("11111111111111111111111111111111");
  const idl = JSON.parse(readFileSync("./target/idl/program.json", "utf-8"));
  const program = new anchor.Program(idl, provider);

  const [configPda] = PublicKey.findProgramAddressSync([Buffer.from("config")], programId);

  console.log("Program ID:", programId.toBase58());
  console.log("Config PDA:", configPda.toBase58());

  try {
    const config = await program.account.config.fetch(configPda);
    console.log("Already initialized, authority:", config.authority.toBase58());
    return;
  } catch {
    console.log("Initializing...");
  }

  const tx = await program.methods.initialize().accounts({
    config: configPda,
    authority: wallet.publicKey,
    systemProgram: anchor.web3.SystemProgram.programId,
  }).rpc();

  console.log("Done! TX:", tx);
}

main().catch(console.error);

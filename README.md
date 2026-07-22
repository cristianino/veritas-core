# VeritasCore

An enterprise-grade, high-assurance governance and consensus protocol architected for the Cardano blockchain (Plutus V3). VeritasCore transitions legacy state-mutable architectures into a deterministic, high-throughput eUTXO framework, specifically optimized for zero-trust institutional environments and multi-generational wealth preservation.

The core on-chain validation logic is built natively in **Aiken**, while the off-chain orchestration layer is engineered in **Rust** utilizing `pallas` and `uplc` primitives for raw memory efficiency and ultra-low latency execution.

## Architectural Model: Parallelized Voting UTXOs

Traditional account-based smart contracts (e.g., Ethereum/Solidity) suffer from global state contention: multiple transactions compete to mutate a single central counter, leading to network bottlenecks, predictable gas spikes, and vulnerability to front-running.

VeritasCore leverages Cardano’s native eUTXO ledger to achieve **genuine parallel execution without state contention**:

1. **Minting Phase (`Issue`)**: The designated governance authority issues deterministic voter tokens based on cryptographic eligibility credentials.
2. **Casting Phase (`Cast { candidate }`)**: The voter consumes (burns) their unique identity token and creates an independent **Ballot UTXO** locked at the script address. The vote's destination is stored securely within the transaction datum. Because each ballot exists as an isolated, independent UTXO on the ledger, thousands of votes can be processed simultaneously within the same block with zero state collisions.
3. **Settlement Phase (`Close`)**: Upon reaching the immutable ledger deadline, the governance authority reclaims the script outputs. Final accounting and cryptographic auditing are performed deterministic-neutrally off-chain by aggregating the immutable script-locked UTXOs.

*Note: While the on-chain smart contract guarantees the deterministic "1 Token = 1 Vote" mathematical constraint, identity binding and token allocation are managed via the off-chain security architecture.*

## Repository Structure

* `validators/voting.ak`: On-chain validator script (Minting: `Issue`/`Cast`, Spending: `Close`) including formal property-based unit testing.
* `plutus.json`: CIP-57 ledger blueprint dynamically compiled via `aiken build`.
* `offchain/`: Multi-threaded off-chain orchestration engine written in Rust.
  * `src/main.rs`: Core initialization pipeline, parameter application, policy ID derivation, and testnet address generation.

## On-Chain Engine (Aiken)

Verify type-safety and execute unit tests:
```bash
aiken check
```

Compile and generate the CIP-57 blueprint:
```bash
aiken build
```

The validator script is heavily parameterized by `authority` (Public Key Hash), `deadline` (POSIX milliseconds), and `candidate_count`. To derive the deterministic policy ID and script address:
```bash
aiken blueprint policy -m voting -v voting
aiken blueprint address -m voting -v voting
```

## Off-Chain Engine (Rust)

### Execution Prerequisites (Windows Environment)
Ensure a functional **GNU Rust toolchain** and a compliant `gcc` compiler (required for native `secp256k1-sys` binding processing):

```powershell
rustup default stable-x86_64-pc-windows-gnu
# Recommended GCC deployment via WinLibs:
winget install BrechtSanders.WinLibs.POSIX.MSVCRT
```

### Compilation & Pipeline Execution
Execute via native PowerShell to guarantee a clean system path:

```powershell
cd offchain
cargo run
```

The initialization layer dynamically ingests `plutus.json`, injects runtime governance parameters, and derives the target network address and policy ID—fully aligned with the on-chain blueprint specification.

## Development Roadmap

- [x] On-chain Smart Contract Engine — Compiled, 7/7 formal tests passed, CIP-57 blueprint verified.
- [x] Off-chain Layer Step 1 — Deterministic runtime identity derivation (Policy ID & script-address alignment).
- [-] Off-chain Transaction Construction — Algorithmic token minting, decentralized vote execution, and automated settlement pipelines.

## License

Apache-2.0

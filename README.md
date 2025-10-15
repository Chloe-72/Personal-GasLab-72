# Anti-Fragile Web3 Journey

On-chain, non-reversible, 148-day public build of an anti-fragile DeFi protocol.

## On-Chain Clock

Tx Hash: 5602662 (Git snapshot, irreversible)
View: https://github.com/Chloe-72/Personal-GasLab-72/commit/5602662

## Anti-Fragile Experiment
- If I ship crap or go silent for 3 days, I burn 0.1 ETH as a laziness penalty.
- Every commit is minted as an on-chain SBT — irreversible work proof.
- Welcome to audit, attack, CR. Knives welcome.

## On-Chain Deliverables (148 days)

| Day | Insight | Note Taking | Chain Proof |
|-----|---------|-------------|-------------|
| 001 | AddressSkeleton baseline | Establish the address skeleton and use it as the Gas baseline for subsequent experiments. | [commit/5602662](https://github.com/Chloe-72/Personal-GasLab-72/commit/5602662) |
| 002 | SBT Stage-0 draft + SHA-256 commit | Public pledge on X: burn 0.1 ETH if no update; SBT serves as an irreversible proof-of-work. | [X pledge](https://x.com/chloecao0702/status/1976316792554631352) |
| 003 | First off-chain compile → bytecode exact match | • Finalised source; generated public bytecode & metadata; offline build bypasses Remix jitter.<br>• One-line fix (`_exists` → `ownerOf`) keeps keccak-256 intact; hash locks public commitment while allowing iteration.<br>• `forceRest()` triggers 3-day laziness penalty; `tokenURI()` renders on-chain SVG-SBT; both embedded in `0x532eda…f818`. | • [Source](https://gist.github.com/Chloe-72/3ec1a4fb7b7f83f2d57c63a59305a80d)<br>• [Bytecode](https://gist.github.com/Chloe-72/0d8ab0b6dcd7b9f037c8b8e52da8b8bf)<br>• [Metadata JSON](https://gist.github.com/Chloe-72/b6d7b738f69d2a5c1b6b1b6b1b6b1b6b)<br>• keccak-256: `0x532eda454d1bff0ebca0446c372a812e236e8b010c16630e37ed98c97d1cf818` |
| 004 | Bytecode optimization phase | viaIR + optimizer=200, 28 KB → 19 KB (still > 24 KB), next: external renderer proxy | **Tx: 
0x627801** (community alpha by @KuwaTakushi) / [PR #3](https://github.com/Chloe-72/Personal-GasLab-72/pull/3) / [commit/95ed28a](https://github.com/Chloe-72/Personal-GasLab-72/commit/95ed28a) |
| 005 | SBT v0.0.0-final deploy (planned) | Author deployment on Sepolia, runtime hash TBD; separates community alpha from author final build. | Tx: TBD / Status: planned |

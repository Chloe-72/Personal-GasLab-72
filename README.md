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
| Day | Insight | 学习内容 Learning | Chain Proof |
|-----|---------|-------------------|-------------|
| 001 | AddressSkeleton baseline | 建立地址骨架，作为后续实验的 Gas 基线 | [commit/5602662](https://github.com/Chloe-72/Personal-GasLab-72/commit/5602662) |
| 002 | SBT Stage-0 draft + SHA-256 commit | 推特公开承诺：不更新就烧 0.1 ETH，SBT 作为不可逆工作证明 | [推特承诺](https://x.com/chloecao0702/status/1976316792554631352) |
| 003 | First off-chain compile → bytecode exact match (Anti-Fragile SBT v1.0.0, Sepolia-ready, not deployed) | • Finalised source; generated public bytecode & metadata; offline build bypasses Remix jitter.<br>• One-line fix (`_exists` → `ownerOf`) keeps keccak-256 intact; hash locks public commitment while allowing iteration.<br>• `forceRest()` triggers 3-day laziness penalty; `tokenURI()` renders on-chain SVG-SBT; both embedded in `0x532eda…f818`. | Evidence permanently archived:<br>• [Source](https://gist.github.com/Chloe-72/3ec1a4fb7b7f83f2d57c63a59305a80d)<br>• [Bytecode](https://gist.github.com/Chloe-72/0d8ab0b6dcd7b9f037c8b8e52da8b8bf)<br>• [Metadata JSON](https://gist.github.com/Chloe-72/b6d7b738f69d2a5c1b6b1b6b1b6b1b6b)<br>• keccak-256: `0x532eda454d1bff0ebca0446c372a812e236e8b010c16630e37ed98c97d1cf818` |

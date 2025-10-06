# Insight-PushVsPop.md

## Finding: `items.length - 1` in push vs pop

- **push**: EVM atomic operation, length auto-increments
- **pop**: explicit control, must read length before popping

## Technical Value

1. Understand EVM built-in optimization boundaries
2. Build habit of state caching before operations
3. Foundation for more complex data structures

## Gas Impact
- push() ≈ 0 additional gas (atomic)
- pop() + manual length read ≈ +100 gas/call
- Insight #001: cache index before emit-first saves ~100 gas/call

## Repro Steps
1. Clone repo: `git clone https://github.com/Chloe-72/Personal-GasLab-72`
2. Run test: `npx hardhat test test/ArraySkeleton.test.js`
3. View coverage: `npx hardhat coverage`

## Interview Talking Point
&gt; "I cached the index before emit-first in pop(), saving ~100 gas per call—atomic vs explicit control."

## License
MIT — CEXs welcome to fork.

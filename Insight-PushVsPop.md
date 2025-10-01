# Insight-PushVsPop.md

## 发现：push vs pop 中的 `items.length - 1`
- push：EVM 原子操作，长度自动 +1
- pop：显式控制，需手动读长度再 pop

## 技术意义
1. 理解 EVM 内置优化边界
2. 培养操作前状态缓存习惯
3. 为未来学习更复杂数据结构打基础

# 开发与复核

使用 `moonc 0.10.17+093cb8f9c` 和匹配 core。逻辑包为 `model/` 与 `regression/`；`cmd/` 负责 IO 和退出码；`api/` 是 JS 字符串桥。根包是保留兼容的 0.1 命题实现。

修改语义后先运行相关 MoonBit 测试，再运行独立 oracle；不要用更新快照替代正确性解释。修改公开 API 后执行 `moon info`，审核 `.mbti` 差异并提交。最后运行 `moon fmt --check`。

```sh
moon check --target all --deny-warn
moon test --target wasm-gc --deny-warn
moon build --target js --deny-warn
moon build api --target js --deny-warn
python tools/differential.py --cases 1600
python tools/regression_differential.py --cases 800
python tools/check_cli.py
moon info
moon fmt
```

有原生 C 工具链时运行 `moon test --target native --deny-warn`。CI 中 native 是强制任务，不能通过 continue-on-error 掩盖失败。

每次新增约束、变更报告或优化行为，请更新相应原子/组合语义用例、完整性和预算路径。数据变化应执行 `python tools/generate_models.py` 并核对 diff。无外部依赖的合成 fixture 应说明含义；不提交实际客户配置、密钥、个人联系方式、构建缓存和私密申报材料。

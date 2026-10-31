# 验证证据与复现

固定环境为 MoonBit `0.10.17+093cb8f9c` 及匹配 core；本机 Windows，native 本机因缺 MSVC 不运行，Linux CI 的 native job 是必过项。README 中的测试数字指测试块，不把随机样本冒充独立单元测试。

| 核验 | 证据 |
| --- | --- |
| 原版兼容 | 69 项旧测试保留；原版 quadratic/rational 生成与 Python/MoonBit 校验进入 CI |
| 新增单元/场景 | 新增 41 项测试，总计 110；覆盖域、JSON、算术、预算、分类、优化、回归方向、最近反例、100 字段目标 |
| 解集对照 | `python tools/differential.py --cases 1600`：1700 个模型；外部固定顺序 DFS 与 MoonBit MRV/部分求值完整解集一致 |
| 变更对照 | `python tools/regression_differential.py --cases 800`：897 对模型，独立旧/新接受集的对称差与全部报告见证一致；301 次最少字段最优值对照 |
| 预算行为 | 解集对照包含 243 次中断，变更对照包含 82 次中断；检查预算计数、部分见证及 unknown 结论 |
| CLI 集成 | `python tools/check_cli.py`：28 次真正启动编译后 CLI，核验成功/差异/非法输入/预算不足退出码及篡改拒绝 |
| 固定工具链 | CI 用 `MOONBIT_INSTALL_VERSION=0.10.17+093cb8f9c` 安装二进制与匹配 core；本地读取官方 core 包核对 JSON 解析器源码哈希一致 |

原始每模型记录与摘要由脚本写入 `work/differential/` 和 `work/regression-differential/`；CI 将两者作为 `independent-evidence` artifact 上传。仓库中保存一次实测的原始记录至 `docs/evidence/`，每次 CI 会重新计算，而不是只读取静态结果。

对照解释器使用 Python 任意精度整数后检查范围，整除显式向零处理；只在一个规则的全部变量都绑定后求值。它不复用 MoonBit 的部分求值或搜索路径。最近反例 oracle 对两个独立完整解集做对称差，再对所有变化赋值逐一计算 Hamming 距离。

计时只反映一台机器上的包含 JSONL 通信的测试耗时，不作为跨机器性能宣传。候选探测预算不会限制单次表达式总指令或分配量；超大模型仍可能昂贵。未取得生产部署、第三方使用反馈或相对现有求解器的性能领先证据。

# 生态查重与差异边界

核查日期：2026-10-31。使用 Mooncakes 的 `moon search`（constraint、semantic diff、counterexample、policy、pairwise），并阅读以下项目自己的 README。检索受关键词、索引、发布状态与私有项目影响，不能证明“全生态唯一”。

| 已有项目（直接来源） | 必须承认的已有能力 | kiln 的具体边界 |
| --- | --- | --- |
| [mjfmjf879/moonbit-constraint](https://github.com/mjfmjf879/moonbit-constraint) | 有限域、约束组合、传播、MRV、优化、冲突报告、配置与调度 | 通用求解内核确实重叠；kiln 不以 CSP 从零实现为立项价值，交付两版跨字段算术接受集差异、原域扩缩及相对基线最少改动字段的反例 |
| [cn-xjr/MoonPlan](https://github.com/cn-xjr/MoonPlan) | 可解释有限域约束与排程工具 | 不宣称补齐一般排程生态，也不复制领域模板；选题仅是数据案例 |
| [CJR-ai-nb/evowitness](https://github.com/CJR-ai-nb/evowitness) | 结构契约接受集兼容分析、最小 JSON 反例与回放；README 当前明确不支持联合/条件约束 | 目标存在接受集对比重叠；kiln 输入同名有限整数变量上的跨字段算术、乘除取模、布尔、全异/表/计数约束，不做其开放对象、嵌套字段、引用、字符串或列表契约 |
| [hutingyu-nuist/moonpolicyproof](https://github.com/hutingyu-nuist/moonpolicyproof) | IPv4 五元组有序首匹配策略、BDD 编译、双向差异与见证回放 | 语义差异目标有交集；kiln 不处理网络包、CIDR 或首匹配 ACL，而是算术业务条件、有限域变更与最少字段配置反例 |
| [LF-ai-nb/caseweave](https://github.com/LF-ai-nb/caseweave) | 受约束覆盖数组、覆盖审计、用例修复与风险排序 | kiln 不声称新的组合覆盖工具，不生成覆盖数组；比较的是两版接受集，最近反例是精确 Hamming 最小化而非风险评分 |
| [sgy1023-crt/MoonCassowary](https://github.com/sgy1023-crt/MoonCassowary) / [Freon793/moonopt](https://mooncakes.io/docs/Freon793/moonopt) | 增量连续线性布局 / LP-MIP 模型与证书 | 数学求解存在邻近；kiln 是有预算的小型有限域算术解释与语义回归，不宣称能替代这些高效求解内核 |

## 为什么保留一个小型内核

比较规则需要清楚规定除零/整数越界属于“无定义”还是“拒绝”，普通否定是否能反转错误，以及旧/新声明域如何进入接受谓词。`model/` 显式提供 undefined 与 pending 的区分、`holds` 总化、checked integer 和完整搜索状态；`regression/` 在此上编译接受结果的对称差，再回放到两版原始模型。这是当前实现的工程选择，不是证明已有库不能扩展。

因此新价值应以具体用户操作评价：修改跨字段条件后，拿到一个完整、可回放、相对基线改动字段最少的区分输入；预算不足时不能被误判等价。独立测试测量完整差异与最小 Hamming 距离，而不是仅检查报告存在。

没有取得第三方采用、用户访谈或性能领先证据。所有场景均为原创合成模型；不能写“社区急需”“首个”“唯一”“已生产验证”。后续维护优先考虑与现有约束库的互操作，而不是重复扩大求解器范围。

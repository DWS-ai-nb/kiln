# kiln.model/1 与可信边界

根对象必需 `format`、`variables`、`rules`，可选 `objective` 和说明性 `description`。变量为 `{name, domain}`，规则为 `{id, assert}`。重复 JSON 键、重复名称/规则 ID、重复域值、未知字段/变量、错误参数数量、非整数拼写和超限输入会拒绝。

| 类别 | 前缀形式 |
| --- | --- |
| 常量 / 引用 | `3` / `"price"` |
| 二元算术 | `["+", a, b]`，同样支持 `- * / %` |
| 一元算术 | `["neg", a]`、`["abs", a]` |
| 布尔转整数 | `["indicator", rule]`，真 1、假 0、无定义仍无定义 |
| 比较 | `["==", a, b]`，同样支持 `!= < <= > >=` |
| 合取 / 析取 | `["all", r1, r2, ...]`、`["any", r1, r2, ...]`；空 all 真，空 any 假 |
| 否定 / 蕴含 | `["not", rule]`、`["implies", precondition, consequence]` |
| 总化接受 | `["holds", rule]`，无定义转为假，部分赋值尚不能判定时仍 pending |
| 全异 | `["distinct", term1, term2, ...]` |
| 允许元组 | `["table", [term1,term2], [[1,2],[2,3]]]` |
| 计数 | `["count", min, max, [r1,r2,...]]`，计数真谓词个数 |

整数及所有中间运算都限定 ±10^12。除法向零截断，余数随被除数符号，除零和超界为 undefined。JSON 数字必须是整数拼写，`1.0`、`1e0`、`1e-9999` 都拒绝，避免解析器浮点变换掩盖原输入。

## 三种求值状态

部分赋值下，未绑定变量是 pending；已经确定的非法算术是 undefined。合取出现确定假即为假；析取出现确定真即为真。没有决定性分支时，只要仍有 pending，就保留 pending，避免过早剪掉可能屏蔽错误的合法分支；全绑定后未被屏蔽的 undefined 仍使规则无效。

原子全异、表、计数中只要算术无定义，该原子无定义；不能靠重复值、元组失配或计数边界把该错误翻成真的否定。`not(undefined)` 和 `indicator(undefined)` 也无定义。`holds` 是明确选择“无定义即拒绝”的唯一总化运算。

模型接受一个完整对象，当且仅当变量键恰好匹配、每个值属于原始声明域、全部命名规则为真。回归编译用 `holds(all(original-domain-membership, original-rules))` 表示各版本接受谓词，因此可以正确比较除零输入、空域、域扩张与域收缩。

## 报告

- `kiln.search/1`：`solutions` 是可行见证；`complete` 仅在 `stop=exhausted` 为真。统计不是证明凭证。
- `kiln.diff/1`：`relation=changed/equivalent/unknown`，包含有限 `scope`、双向 `changes` 与命名违规。一个见证即可证明变化，但不能证明没有其它变化。
- `kiln.closest/1`：相对完整 baseline 的 Hamming 距离。只有 `minimal=true` 才证明该域内全局最少改动字段数；不保证并列最优的字典序。

对比要求相同变量名集合；增加/删除变量需要调用方先给出显式映射。不比较目标函数成本、任意程序执行、真实部署效果或未声明的实数/整数输入。报告不做签名，不认证模型来源。回放只认证所给模型与输入之间的一致性；完整性依赖搜索实现及测试证据。

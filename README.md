# kiln · 铸题

**带适定性保证的可验证命题引擎。** 把「这道题应该长什么样」写成约束，反解出题目，并让每道题自带可机器复核的答案凭证。

用 MoonBit 写，零浮点，纯确定性。同一份 schema、同一个 seed，在 wasm-gc / js / native 三个后端产出逐字节相同的卷子。

```
candidates  171  (rejected 0, duplicates 0)
unique      171
levels      L1:18  L2:29  L3:56  L4:38  L5:30
reverify    171 ok, 0 failed
```

---

## 为什么做这个

出一道题最容易的部分是「写出来」，最难的部分是**它恰好是一道好题**：有解、解唯一、没有增根、难度可控、和别的题不重复。

坏题只有三种形态，而每一种都在真实试卷里反复出现：

| 形态 | 例子 | 后果 |
|---|---|---|
| 无解 | $x^2+1=0$ 要求「求两根」 | 学生算到判别式为负，怀疑自己 |
| 多解 | 分式方程去分母后引入增根 | 答案对不上，老师要逐个解释 |
| 退化 | 十道题里四道的常数项都是 0 | 练不到东西 |

现有题库工具几乎都停在「存题 + 抽题」：题是人写的，系统只负责索引。真正的难点不在抽，在**造**——而且不在造得出来，在**造出来的题是良定的**。

与此同时，MoonBit 生态里已经有人把零件做齐了：符号计算（`maxima`、`symbit`）、排版（`moonbitlang/typst`、`pagelayout`）、约束求解（`moonplan`、`cassowary`）。**唯独没有人做「命题」这件事本身。** kiln 不去重造这些零件，它做的是把它们装配起来解决一个还没被建模的问题。

---

## 四个核心设计

### 1. 逆向命题：从答案反解参数

常见做法是随机采样参数、算出答案、不合格就丢掉——命中率常常只有个位数，难度完全不可控。

kiln 把方向反过来：先声明答案应该长什么样，再由关系式解出参数。

```kiln
answer {
  r1: int in [-9, 9]
  r2: int in [-9, 9]
}

param {
  a: 1
  b: -(a * (r1 + r2))     # 韦达定理，由根反解
  c: a * r1 * r2
}

require {
  r1 < r2
}
```

命中率 100%，难度从「事后测量」变成「事前声明」。

### 2. 适定性判定：把「题目没毛病」变成可判定的命题

Hadamard 的适定性三条件在这里落成三条可执行检查：

- **存在**：判别式非负，确实有实根
- **唯一**：解集恰好等于声明的答案集，不多不少（含增根检测）
- **稳定**：任一系数 ±1 扰动后仍是两个相异实根

前两条是硬门槛，不通过直接丢弃；第三条是**软信号**——判为 fragile 的题仍然正确，只是经不起重印或笔误，组卷时会排在后面。

判不了的部分明确返回 `Undecidable`，绝不猜。

### 3. 答案凭证：生成即证明，且两条路径不共谋

这是整个设计里最要紧的一条：**生成器与验证器不共享推导路径。**

```
生成：选根 (r1, r2) → 韦达 → 系数 (a, b, c)
验证：取系数 (a, b, c) → 判别式 → 开方 → 求根公式 → 比对解集
```

同一个符号错误不会在两条路上同时发生并互相抵消。于是 `moon test` 等价于**全题库体检**，不是抽查，是每一道。

每道题都带一份凭证：系数、判别式、精确平方根、求根公式给出的根、扰动检验结果。第三方不需要信任生成器，照着凭证重算一遍即可。

### 4. 结构指纹：跨卷不撞题

多项式按「同解」做规范化：清分母 → 约去公因子 → 首项取正。

于是 `2x²-10x+12=0`、`x²-5x+6=0`、`-x²+5x-6=0` 得到同一个指纹 `1,-5,6`——它们本来就是同一道题。这个映射对一元多项式是 **sound 且 complete** 的：指纹相同 ⇔ 同解。

再往上，组卷时用结构标签做多样性约束（`zero-root`、`no-linear-term` 硬限 1 题，`both-negative`、`unit-root` 软限 3 题），避免「十道题四道常数项为零」。

---

## 快速开始

```bash
# 构建（Windows 上没有 MSVC 时用 js 后端）
moon build --target js

# 体检：生成全题池并逐题独立复核
moon run cmd/cli --target js -- check --schema examples/quadratic.kiln

# 出卷：10 题，固定种子
moon run cmd/cli --target js -- gen --schema examples/quadratic.kiln \
  --count 10 --seed 7 --out out

# 按难度配额组卷
moon run cmd/cli --target js -- gen --schema examples/quadratic.kiln \
  --levels 1:2,2:3,3:3,4:2 --seed 2026 --out out

# 复核一份卷子：不读 schema，不重跑生成器，只凭证重算
moon run cmd/cli --target js -- verify --file out/paper.json

# 跨周复用：这周发的题，下周不再出现
moon run cmd/cli --target js -- gen --schema examples/quadratic.kiln \
  --count 8 --seed 22 --out out --exclude out/ledger.txt --record out/ledger.txt
```

账本是一行一个结构指纹的纯文本文件，可以进版本库、可以 diff，也可以手工删掉某几行把某道题放回题池。

产物三份，都是自包含的 HTML（无 CDN、无外链字体、无 JS 依赖，直接打印）：

- `out/worksheet.html` — 学生卷，题序按难度递增
- `out/answers.html` — 答案页，含难度依据与复核凭证
- `out/worksheet.md` — 便于粘贴的纯文本版
- `out/paper.json` — 卷子文件，每道题带可复核凭证

仓库里带三个示例 schema：

| 文件 | 族 | 说明 |
|---|---|---|
| `examples/quadratic.kiln` | quadratic | 整数根一元二次方程，171 道唯一题 |
| `examples/rational.kiln` | rational | 分式方程，312 道唯一题 |
| `examples/rational_with_extraneous.kiln` | rational | **反面教材**：故意不写 `r != k`，让验证器拦下 13 道增根题 |

出卷失败不会返回一张残卷，而是指名道姓地告诉你缺口：

```
组卷失败：L5 需要 30 题，可用的只有 12 题（缺口 18，可能受结构多样性上限限制）
```

---

## 任何人都能复核

这是整个项目最想被检验的一点：**卷子不是一堆文本，是一份可复核的数据**。

`paper.json` 里每道题带一段 `payload`——二次方程是 `[a, b, c]`，分式方程是 `[n₀, n₁, d₀, d₁, q]`。拿它和答案，任何人都能把答案从头算一遍：

```bash
$ python3 tools/verify_reference.py out/paper.json
schema=quadratic_int_roots items=4 passed=4 failed=0
```

这个 Python 实现 112 行有效代码，用 `fractions.Fraction` 全程精确，跟 MoonBit 那份**不共享任何代码**。CI 每次生成后都会跑它——两边结论不一致，构建就失败。

改了答案会怎样：

```bash
$ python3 tools/verify_reference.py tampered.json
1: answer-mismatch: formula gives [Fraction(-4, 1), Fraction(0, 1)], declared [Fraction(99, 1)]
schema=quadratic_int_roots items=4 passed=3 failed=1        # 退出码 1
```

格式规范在 [`docs/CERTIFICATE.md`](docs/CERTIFICATE.md)，包含每种族的 payload 定义、逐步算法，以及它**不**保证什么（题干文字不参与校验——凭证管数学，不管文风）。

---

## schema 语言

schema 是声明式的，不做计算，只描述「题族长什么样」：

| 子句 | 作用 |
|---|---|
| `schema "name"` | 唯一标识 |
| `family quadratic` | 选择验证策略 |
| `title "..."` | 卷面标题 |
| `answer { ... }` | 答案变量，必须带整数域 `[lo, hi]` |
| `param { ... }` | 参数：带域则枚举，带表达式则推导（可引用前面已绑定的变量） |
| `require { ... }` | 并列条件，多条之间是「且」；表达式引用未定义变量会在加载时报错 |
| `ask "..."` | 题面模板，`{poly}` 由验证族渲染 |

加载期做静态检查：重名、未定义变量、空域、缺失 `ask`，都会在**解析后立刻**报错并给出行号，而不是等到运行时炸掉。

---

## 架构

| 文件 | 职责 | 关键点 |
|---|---|---|
| `rat.mbt` | 精确有理数 | 归一化不变量（`den>0`、互素、零为 `0/1`）；精确开方 |
| `poly.mbt` | 一元多项式 | 正规形；`canonical_key` 做同解规范化 |
| `lexer.mbt` | 词法 | 不抛异常，坏字符变 `TBad` 由语法层定位 |
| `ast.mbt` | 表达式与求值 | 除以零返回 `None` 而非崩溃，语义上就是「此处无定义」 |
| `parse.mbt` | 递归下降语法 | 错误一律带行号；解析与校验分离 |
| `engine.mbt` | 枚举与题池 | 深度优先枚举推导链，叶子处做条件检查与去重 |
| `verify.mbt` | 独立验证 | 判别式 → 开方 → 求根公式，与生成路径完全分离 |
| `family_quadratic.mbt` | 二次族 | 逆向构造、题面渲染、可解释难度、结构标签 |
| `family_rational.mbt` | 分式族 | 交叉相乘验证、增根判定、分母零点检查 |
| `canon`（在 `poly.mbt`） | 结构指纹 | 同解规范化 |
| `paper.mbt` | 组卷 | 难度配额 + 结构多样性 + 已选集合 + 不可行解释 |
| `render.mbt` | 输出 | HTML / Markdown，全部转义 |
| `paper_io.mbt` | 卷子文件 | `kiln.paper/1` 的读写与独立校验 |
| `tools/verify_reference.py` | 参考校验器 | 112 行 Python，与实现零共享 |
| `rng.mbt` | 确定性随机 | splitmix64，20 行，不依赖平台熵 |
| `cmd/cli` | 命令行 | 三个动词，无配置文件；账本读写在 CLI 层 |
| `golden_wbtest.mbt` | 跨后端黄金测试 | 把整卷输出钉死，两个后端同时校验 |
| `properties_test.mbt` | 属性测试 | 验证器一致性、指纹缩放不变、指纹幂等 |

数据流：

```
schema.kiln ──parse──> Schema ──enumerate──> 候选参数组
                                              │
                                   family build（逆向）
                                              │
                                   verify（正向，独立）
                                              │
                          ┌───────────────────┴──────────────┐
                     WellPosed                          NotWellPosed
                          │                                  │
                    Item + 凭证 + 指纹                    计入 rejects
                          │
                    paper.assemble（配额 / 多样性 / 去重）
                          │
                    render → HTML / Markdown
```

---

## 设计决定记录

被否掉的方案比选中的方案更能说明一个项目的位置。`docs/DECISIONS.md` 记了六条真正影响结构的判断：为什么只做一元多项式、为什么生成器与验证器必须走两条路、为什么指纹按同解而不是按系数、为什么「稳定」不是硬门槛、为什么账本是纯文本、为什么组卷是贪心而不是搜索。每条都写了放弃的替代方案和代价。

---

## 工程实践

- CI 在 **wasm-gc 与 js 两个后端分别跑测试**，同时做 `moon check --target all --deny-warn` 和 `moon fmt` 的 diff 检查。警告即错误，格式必须是规范形式。
- **属性测试**用标准库 `@quickcheck`，失败时给的是收缩后的最小反例，不是一坨随机输入。
- **黄金文本**把整卷输出钉死。任何引入浮点、哈希迭代序或本地化差异的改动，会在两个后端之一先露出来。
- native 后端单独一个 job 且 `continue-on-error`：它需要 C 工具链，不该因为环境缺失就把主流程标红，但也不假装它一定通过。

---

## 设计取舍

**不重造轮子，但也不当胶水。** 生态里已有的 CAS、排版引擎、通用约束求解器一律不碰。kiln 的独有部分是「逆向构造 + 适定性判定 + 凭证 + 指纹」这条链，它不属于上面任何一类。

**零浮点。** 全程 `Int64` 有理数。原因有二：教学题目的答案本就该精确；浮点会毁掉跨后端逐字节一致性这个可验证承诺。

**自研 PRNG 而非 `@random`。** 只用 20 行 splitmix64，因为可复现性是契约：同一 seed 必须在三个后端产出同一张卷子，不能依赖平台熵的回落行为。

**难度是可解释的，不是黑箱。** 一个小的加性模型，每个因子都有名字（「根绝对值较大」「两根异号」「方程缺项（偏易）」）。老师可以不同意模型，然后去改 schema——而不是面对一个神秘数字。

**边界清楚到能写进 README。** 只做可判定子集；判不了就返回 `Undecidable`。

---

## 测试

65 个测试，`moon test` 全绿；`moon test --target wasm-gc` 与 `--target js` 各跑一遍，同一个黄金文本必须同时通过。

- **精确算术**：符号归一、约分、比较、精确开方（含非完全平方必须返回 `None`）
- **多项式**：展开、求值、同解规范化（缩放合并、不同方程不误合并、有理系数清分母）
- **词法/语法**：双字符运算符、注释、行号定位、未定义变量、空域
- **验证器**：正例、错答案、负判别式、重根、无理根——五种判定各自有独立用例
- **引擎**：题池规模与去重计数、全量复检、可复现性
- **组卷**：配额、种子可复现、不可行解释、排除集、**同卷不得重题**（回归用例）、退化结构不得霸屏（跨 12 个种子扫描）
- **属性测试**（`@quickcheck`，带收缩）：任取两个相异整数根构造的方程必被验证器接受；任意非零缩放下结构指纹不变；指纹可反向重建出同一方程
- **卷子文件**：JSON 往返后仍全部通过；篡改系数或答案必被拒；缺字段、版本不匹配、非 JSON 都给可读原因
- **跨后端黄金文本**：固定 seed 的整卷输出逐字符写死，两个后端都必须一字不差——这是 README 里「逐字节一致」那句话的证明，不是修辞

几何测试（跨种子扫描、全池复检）比单点断言更能兜住回归——上面那条「同卷重题」的 bug 就是被跨种子扫描抓出来的。

---

## 边界

明确**不做**：

- 不做完整 CAS（`maxima` / `symbit` 已经在生态里）
- 不做排版引擎（`typst` / `pagelayout` 已经在生态里）
- 不做通用约束求解器（`moonplan` / `cassowary` 已经在生态里）
- 不做几何证明、不做自然语言应用题
- 不做在线刷题平台、不做账号体系

目前已实现两个验证族：`quadratic`（整数根一元二次方程）与 `rational`（分式方程，含增根判定）。

加第三个族只需要：一个 `build_*`、一个 `verify_*`、一组结构标签，以及一条 schema。引擎的枚举、去重、组卷、渲染全部复用——不需要改 `engine.mbt` 以外的任何调度代码。

分式族是「适定性」最有说服力的证据。把它那条 `require r != k` 删掉，13 个候选会去分母解出根恰好等于分母零点——方程其实无解，属于典型增根。验证器全部拦下，reason 写作 `extraneous-root`：

```
$ moon run cmd/cli --target js -- check --schema examples/rational_with_extraneous.kiln
candidates  169  (rejected 13, duplicates 0)
rejects     1 distinct reason(s)
            - extraneous-root
```

---

## 路线图

- [x] 精确算术 / 多项式 / 规范化指纹
- [x] schema DSL（词法、语法、静态检查）
- [x] 逆向构造 + 适定性判定 + 凭证
- [x] 组卷（难度配额、结构多样性、不可行解释）
- [x] HTML / Markdown 输出、CLI
- [x] 第二个验证族：分式方程（增根检测）
- [x] 跨周去重账本（`--exclude` / `--record`）
- [x] `kiln.paper/1` 卷子格式 + `verify` 命令 + Python 参考实现
- [x] CI：双后端测试、`--deny-warn`、格式检查
- [ ] 平行卷：A/B 卷按结构指纹做统计等价匹配
- [ ] 题池 JSON 导入导出，便于与既有题库对接

---

## 许可

Apache-2.0。参考的算法与思路（Kiwi 的增量约束、QuickCheck 的收缩、Hadamard 的适定性）均在 `NOTICE` 中注明；实现独立完成，无第三方运行时依赖（仅 `moonbitlang/x` 提供文件读写）。

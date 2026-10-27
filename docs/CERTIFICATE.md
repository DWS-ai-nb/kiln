# 凭证格式 · `kiln.paper/1`

一份卷子就是一个 JSON 文件。每道题带一段 `payload`，拿 `payload` 和 `answers` 就能把答案重算一遍——不需要 schema，不需要 kiln，也不需要相信生成器。

参考实现在 `tools/verify_reference.py`，112 行 Python，`fractions.Fraction` 全程精确。它和 MoonBit 实现不共享任何代码；两边都通过，这道题基本可以认为是诚实的。

---

## 文件结构

```json
{
  "format": "kiln.paper/1",
  "schema": "quadratic_int_roots",
  "title": "一元二次方程 · 整数根",
  "seed": 7,
  "items": [
    {
      "question": "解方程 x² - 5x + 6 = 0",
      "answers": ["2", "3"],
      "level": 2,
      "fingerprint": "1,-5,6",
      "family": "quadratic",
      "payload": ["1", "-5", "6"]
    }
  ]
}
```

| 字段 | 作用 |
|---|---|
| `format` | 版本号，不匹配直接拒绝。格式变了就换号，不做兼容猜测 |
| `schema` / `title` / `seed` | 溯源信息：哪条 schema、什么标题、哪个种子 |
| `level` | 可解释难度，1–5 |
| `fingerprint` | 结构指纹，同解等价类的标识 |
| `family` | 决定 `payload` 的解释方式和验证算法 |
| `payload` | **验证所需的全部数据**，长度与顺序由族定义 |
| `answers` | 声明的答案集 |
| `question` | 渲染后的题干（展示层，见「保证与不保证」） |

### 为什么数字是字符串

JSON 的数字是双精度浮点。`1/3` 存进去就不再精确，大整数会静默丢精度。凭证的全部价值建立在「精确」上，所以所有数值一律写成字符串：整数写 `-5`，分数写 `-3/2`。

---

## 族的 payload 与验证算法

### `quadratic`

`payload = [a, b, c]`，表示 `a·x² + b·x + c = 0`。

```
1. 若 a = 0            → 失败 not-quadratic
2. D = b² − 4ac
3. 若 D < 0            → 失败 no-real-roots
4. 若 D = 0            → 失败 double-root
5. s = √D，若 D 不是有理数的完全平方 → 失败 irrational-roots
6. r₁ = (−b + s) / 2a，r₂ = (−b − s) / 2a
7. 比较 {r₁, r₂} 与 answers（多重集，顺序无关）→ 不等则 answer-mismatch
```

第 5 步的「完全平方」判定：分子与分母分别开方，两个都必须整除。

### `rational`

`payload = [n₀, n₁, d₀, d₁, q]`，表示 `(n₀ + n₁x) / (d₀ + d₁x) = q`。

```
1. 交叉相乘：(n₀ + n₁x) − q(d₀ + d₁x) = 0
   即 b₁x + b₀ = 0，其中 b₁ = n₁ − q·d₁，b₀ = n₀ − q·d₀
2. 若 b₁ = 0 且 b₀ = 0 → 失败 identity（恒等式，无穷多解）
3. 若 b₁ = 0            → 失败 no-solution
4. x = −b₀ / b₁
5. 若 d₀ + d₁x = 0      → 失败 extraneous-root（增根）
6. 与 answers[0] 比较 → 不等则 answer-mismatch
```

第 5 步是这个族的全部意义。去分母之后代数上「解出来了」，但那个解让原方程的分母为零，方程其实无解。没有这一步，生成的题会把增根当答案发给学生。

---

## 保证与不保证

**保证**：`verify` 通过，意味着 `payload` 所描述的对象，其解集与 `answers` 完全一致——在族定义的数学范围内，不多不少。

**不保证**：

- **题干文字**。`question` 是渲染结果，`payload` 才是它的结构来源。如果有人改了题干而没改 payload，`verify` 不会报错。要防这一手，就用 payload 重新渲染后与 `question` 比对——渲染规则在 schema 的 `ask` 模板里，是公开的。
- **题目是否合适**。难度标签是可解释的经验模型，不是心理测量学结论；它没有作答数据支撑。
- **表述是否清楚**。机器只认数学，不认「这题出得绕不绕」。

这条边界是刻意的：凭证管数学，不管文风。

---

## 自己实现一个校验器

最小实现只需要：

1. 一个精确有理数类型（Python 用 `fractions.Fraction`，其他语言用任意大整数对）
2. 一个精确开方（分子分母分别判完全平方）
3. 上面两段算法

`tools/verify_reference.py` 是完整例子。CI 里会在每次生成后跑一遍它——如果 MoonBit 与 Python 对同一份卷子给出不同结论，构建就失败。

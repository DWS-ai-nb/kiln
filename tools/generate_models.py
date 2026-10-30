"""Generate the original, synthetic models used in the documented scenarios.

No customer data or third-party fixtures are included. Running this script is
optional: generated JSON files are checked in so MoonBit alone can run them.
"""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1] / "examples" / "models"


def var(name, values):
    return {"name": name, "domain": list(values)}


def rule(name, assertion):
    return {"id": name, "assert": assertion}


def total(names):
    result = 0
    for name in names:
        result = ["+", result, name]
    return result


def save(name, description, variables, rules, objective=None):
    doc = {"format": "kiln.model/1", "description": description,
           "variables": variables, "rules": rules}
    if objective is not None:
        doc["objective"] = objective
    ROOT.mkdir(parents=True, exist_ok=True)
    (ROOT / f"{name}.json").write_text(
        json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    save("pricing", "合成价格规则：会员折扣与优惠券叠加，检查应付金额不为负。tier=0/1/2，金额单位为元。",
         [var("tier", range(3)), var("subtotal", [0, 50, 99, 100, 150, 200]),
          var("coupon", [0, 20, 50]), var("discount", [0, 10, 20])],
         [rule("tier-discount", ["table", ["tier", "discount"], [[0, 0], [1, 10], [2, 20]]]),
          rule("coupon-eligible", ["implies", [">", "coupon", 0], [">=", "subtotal", 50]]),
          rule("coupon-not-over-subtotal", ["<=", "coupon", "subtotal"]),
          rule("nonnegative-charge", [">=", ["-", ["-", "subtotal", "discount"], "coupon"], 0])])

    save("deployment", "合成配置约束：runtime=0 wasm-gc/1 JS/2 native；host=0 browser/1 server；storage=0 memory/1 file/2 indexedDB。",
         [var("runtime", range(3)), var("host", range(2)), var("storage", range(3)),
          var("persistent", range(2)), var("encrypted", range(2))],
         [rule("runtime-host", ["table", ["runtime", "host"], [[0, 0], [1, 0], [1, 1], [2, 1]]]),
          rule("files-need-server", ["implies", ["==", "storage", 1], ["==", "host", 1]]),
          rule("indexeddb-needs-browser", ["implies", ["==", "storage", 2], ["==", "host", 0]]),
          rule("persist-needs-storage", ["implies", ["==", "persistent", 1], ["!=", "storage", 0]]),
          rule("encryption-needs-storage", ["implies", ["==", "encrypted", 1], ["!=", "storage", 0]]),
          rule("persistence-required", ["==", "persistent", 1])],
         ["+", ["*", "runtime", 10], ["+", ["*", "host", 3], "storage"]])

    selection_vars = [var(n, [0, 1]) for n in "ABCDEF"]
    selection_rules = [
        rule("choose-three", ["==", total("ABCDEF"), 3]),
        rule("two-algebra", ["==", total("ABC"), 2]),
        rule("one-basic", ["==", total("AE"), 1]),
        rule("shared-stem-a-b", ["<=", total("AB"), 1]),
        rule("shared-stem-a-c", ["<=", total("AC"), 1]),
    ]
    objective = total([["*", n, cost] for n, cost in zip("ABCDEF", [1, 4, 5, 1, 3, 2])])
    save("selection", "精确选题：选3题，2道代数，1道基础。A与B、C共享题干不能同选；成本最小。标签与成本由用户输入，不是认知难度估计。",
         selection_vars, selection_rules, objective)
    save("selection_unsat", "与 selection 相同，但强制选 A，导致配额与禁止组合冲突。",
         selection_vars, selection_rules + [rule("require-a", ["==", "A", 1])], objective)

    save("linear_system", "通用表达式求有限域内的二元方程组：x+y=9, x-y=3。",
         [var("x", range(-10, 11)), var("y", range(-10, 11))],
         [rule("sum", ["==", ["+", "x", "y"], 9]),
          rule("difference", ["==", ["-", "x", "y"], 3])])
    save("cubic", "通用乘法 AST，非题族分派：(x-1)(x-2)(x-3)=0，仅针对声明的有限整数域。",
         [var("x", range(-8, 9))],
         [rule("polynomial", ["==", ["*", ["*", ["-", "x", 1], ["-", "x", 2]], ["-", "x", 3]], 0])])
    cells = [[f"r{r}c{c}" for c in range(4)] for r in range(4)]
    rules = [rule(f"row-{r}", ["distinct", *cells[r]]) for r in range(4)]
    rules += [rule(f"col-{c}", ["distinct", *[cells[r][c] for r in range(4)]]) for c in range(4)]
    rules += [rule(f"given-{c}", ["==", cells[0][c], c + 1]) for c in range(4)]
    save("latin_square", "4阶拉丁方，首行固定。全异约束复用同一引擎，完整解集24个。",
         [var(n, range(1, 5)) for row in cells for n in row], rules)

    # Version pairs use the same model format as standalone solving. They are
    # intentionally original synthetic data, not claimed production adoption.
    regression = ROOT.parent / "regression"
    regression.mkdir(exist_ok=True)

    def pair(name, before, after, baseline):
        directory = regression / name
        directory.mkdir(exist_ok=True)
        for file, obj in [("before", before), ("after", after), ("baseline", baseline)]:
            (directory / f"{file}.json").write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    pricing = json.loads((ROOT / "pricing.json").read_text(encoding="utf-8"))
    before = json.loads(json.dumps(pricing))
    before["rules"] = before["rules"][:-1]  # Bug: allow negative payable amounts.
    pair("pricing", before, pricing, {"tier": 1, "subtotal": 50, "coupon": 0, "discount": 10})

    deployment = json.loads((ROOT / "deployment.json").read_text(encoding="utf-8"))
    after = json.loads(json.dumps(deployment))
    after["description"] = "错误更新：把 JS/server 兼容组合从表中删除；其它条件不变。"
    after["rules"][0]["assert"][2].remove([1, 1])
    pair("deployment", deployment, after,
         {"runtime": 1, "host": 1, "storage": 1, "persistent": 1, "encrypted": 0})

    quota = json.loads((ROOT / "selection.json").read_text(encoding="utf-8"))
    after = json.loads(json.dumps(quota))
    after["description"] = "修改基础题配额为2；存在性与合法选集变化需要语义检查。"
    after["rules"][2]["assert"][2] = 2
    pair("quota", quota, after, dict(zip("ABCDEF", [0, 1, 1, 0, 1, 0])))

    equivalent = json.loads((ROOT / "linear_system.json").read_text(encoding="utf-8"))
    after = json.loads(json.dumps(equivalent))
    after["rules"][0]["assert"] = ["==", ["+", "y", "x"], 9]
    after["rules"][1]["assert"] = ["==", ["-", "y", "x"], -3]
    pair("equivalent", equivalent, after, {"x": 6, "y": 3})


if __name__ == "__main__":
    main()

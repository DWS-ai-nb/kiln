///|
fn[T] must(r : Result[T, String]) -> T {
  match r {
    Ok(v) => v
    Err(e) => abort(e)
  }
}

///|
test "acceptance totalization and indicators preserve undefined semantics" {
  let bad : @model.Rule = Eq(Div(Int(1L), Int(0L)), Int(1L))
  assert_eq(count(one(Holds(bad))), 0)
  assert_eq(count(one(Not(Holds(bad)))), 5)
  assert_true(@model.evaluate(Indicator(bad), Map([])) is Err(_))
  assert_eq(must(@model.evaluate(Indicator(Holds(bad)), Map([]))), 0L)
  let doc : @model.Document = {
    model: one(Holds(Eq(Var("x"), Int(1L)))),
    objective: Some(Indicator(Ne(Var("x"), Int(0L)))),
  }
  assert_eq(
    must(@model.parse_document(@model.document_to_json(doc).stringify())),
    doc,
  )
}

///|
fn one(
  rule : @model.Rule,
  values~ : Array[Int64] = [-2L, -1L, 0L, 1L, 2L],
) -> @model.Model {
  { variables: [{ name: "x", values, }], rules: [{ id: "rule", rule, }], }
}

///|
fn count(m : @model.Model) -> Int32 {
  let r = must(@model.solve(m))
  assert_exhausted(r)
  r.solutions.length()
}

///|
fn assert_exhausted(r : @model.SearchResult) -> Unit {
  if r.stop != @model.Exhausted {
    abort("expected complete result")
  }
}

///|
test "integer arithmetic is checked and truncates toward zero" {
  let env : Map[String, Int64] = Map([])
  assert_eq(must(@model.evaluate(Div(Int(-7L), Int(3L)), env)), -2L)
  assert_eq(must(@model.evaluate(Mod(Int(-7L), Int(3L)), env)), -1L)
  assert_eq(must(@model.evaluate(Abs(Neg(Int(5L))), env)), 5L)
  assert_true(@model.evaluate(Div(Int(1L), Int(0L)), env) is Err(_))
  assert_true(@model.evaluate(Mod(Int(1L), Int(0L)), env) is Err(_))
  assert_true(
    @model.evaluate(Mul(Int(1000000000000L), Int(1000000000000L)), env)
    is Err(_),
  )
  assert_true(@model.evaluate(Add(Int(1000000000000L), Int(1L)), env) is Err(_))
  assert_true(
    @model.evaluate(Sub(Int(-1000000000000L), Int(1L)), env) is Err(_),
  )
  assert_eq(
    must(@model.evaluate(Mul(Int(-1000000L), Int(1000000L)), env)),
    -1000000000000L,
  )
}

///|
test "all six comparisons enumerate the intended values" {
  assert_eq(count(one(Eq(Var("x"), Int(0L)))), 1)
  assert_eq(count(one(Ne(Var("x"), Int(0L)))), 4)
  assert_eq(count(one(Lt(Var("x"), Int(0L)))), 2)
  assert_eq(count(one(Le(Var("x"), Int(0L)))), 3)
  assert_eq(count(one(Gt(Var("x"), Int(0L)))), 2)
  assert_eq(count(one(Ge(Var("x"), Int(0L)))), 3)
}

///|
test "boolean composition and empty boolean identities" {
  assert_eq(count(one(All([]))), 5)
  assert_eq(count(one(Any([]))), 0)
  assert_eq(count(one(Not(Eq(Var("x"), Int(1L))))), 4)
  assert_eq(count(one(All([Ge(Var("x"), Int(0L)), Le(Var("x"), Int(1L))]))), 2)
  assert_eq(count(one(Any([Eq(Var("x"), Int(-1L)), Eq(Var("x"), Int(1L))]))), 2)
  assert_eq(
    count(one(Implies(Ge(Var("x"), Int(0L)), Eq(Var("x"), Int(2L))))),
    3,
  )
}

///|
test "undefined arithmetic cannot become valid through negation" {
  let bad : @model.Rule = Eq(Div(Int(1L), Int(0L)), Int(0L))
  assert_eq(count(one(bad)), 0)
  assert_eq(count(one(Not(bad))), 0)
  assert_eq(
    count(one(Not(AllDifferent([Int(1L), Int(1L), Div(Int(1L), Int(0L))])))),
    0,
  )
  assert_eq(
    count(one(Not(Table([Int(1L), Div(Int(1L), Int(0L))], [[2L, 3L]])))),
    0,
  )
  assert_eq(count(one(Not(Count([bad], 0, 1)))), 0)
}

///|
test "a pending boolean guard can mask undefined arithmetic" {
  let bad : @model.Rule = Eq(Div(Int(1L), Int(0L)), Int(0L))
  assert_eq(count(one(Any([bad, Eq(Var("x"), Int(1L))]))), 1)
  assert_eq(count(one(Any([Eq(Var("x"), Int(1L)), bad]))), 1)
  assert_eq(count(one(Implies(Ne(Var("x"), Int(1L)), bad))), 1)
  assert_eq(count(one(Not(All([bad, Eq(Var("x"), Int(1L))])))), 4)
}

///|
test "domain variables and values are never silently duplicated" {
  assert_true(@model.validate(one(All([]), values=[1L, 1L])) is Err(_))
  assert_true(
    @model.validate({
      variables: [{ name: "x", values: [], }, { name: "x", values: [1L], }],
      rules: [],
    })
    is Err(_),
  )
  assert_true(@model.validate(one(Eq(Var("missing"), Int(0L)))) is Err(_))
  assert_true(@model.validate(one(Count([], 0, 1))) is Err(_))
  assert_true(@model.validate(one(Table([Var("x")], [[1L, 2L]]))) is Err(_))
  assert_true(@model.validate(one(All([]), values=[1000000000001L])) is Err(_))
}

///|
test "empty domains prove unsat without spending budget" {
  let r = must(
    @model.solve(one(All([]), values=[]), config=@model.options(budget=0)),
  )
  assert_eq(r.stop, @model.Exhausted)
  assert_eq(r.stats.probes, 0)
  assert_eq(r.solutions.length(), 0)
}

///|
test "empty model has exactly one empty assignment" {
  let m : @model.Model = { variables: [], rules: [], }
  let r = must(@model.solve(m, config=@model.options(budget=0)))
  assert_eq(r.stop, @model.Exhausted)
  assert_eq(r.solutions.length(), 1)
  assert_eq(r.solutions[0].length(), 0)
  assert_true(must(@model.classify(m, budget=0)) is Unique(_))
}

///|
test "no-solution at budget zero is unknown unless a contradiction is known" {
  let m = one(All([]))
  let r = must(@model.solve(m, config=@model.options(budget=0)))
  assert_eq(r.stop, @model.BudgetLimit)
  assert_eq(r.stats.probes, 0)
  assert_true(must(@model.classify(m, budget=0)) is Unknown)
  assert_true(must(@model.classify(one(Any([])), budget=0)) is Unsatisfiable)
}

///|
test "uniqueness requires exhaustion and multiple requires two witnesses" {
  assert_true(must(@model.classify(one(Eq(Var("x"), Int(1L))))) is Unique(_))
  assert_true(must(@model.classify(one(All([])))) is Multiple(_, _))
  assert_true(
    must(@model.classify(one(Eq(Var("x"), Int(8L))))) is Unsatisfiable,
  )
  let r = must(
    @model.solve(
      one(Eq(Var("x"), Int(1L))),
      config=@model.options(max_solutions=1),
    ),
  )
  assert_eq(r.stop, @model.SolutionLimit)
  let j = @model.search_to_json(r).stringify()
  assert_true(j.contains("unknown"))
}

///|
test "budget is charged for rejected candidate probes" {
  for budget in 0..<8 {
    let r = must(
      @model.solve(one(Eq(Var("x"), Int(8L))), config=@model.options(budget~)),
    )
    assert_true(r.stats.probes <= budget)
    if budget < 5 {
      assert_eq(r.stop, @model.BudgetLimit)
    } else {
      assert_eq(r.stop, @model.Exhausted)
    }
  }
}

///|
test "all-different gives six permutations without duplicate witnesses" {
  let m : @model.Model = {
    variables: ["a", "b", "c"].map(name => @model.Variable::{
      name,
      values: [1L, 2L, 3L],
    }),
    rules: [
      { id: "different", rule: AllDifferent([Var("a"), Var("b"), Var("c")]), },
    ],
  }
  let r = must(@model.solve(m))
  assert_eq(r.stop, @model.Exhausted)
  assert_eq(r.solutions.length(), 6)
  for a in r.solutions {
    assert_true(must(@model.check_assignment(m, a)).valid)
  }
}

///|
test "allowed tables check arity, partial support and empty tables" {
  let m : @model.Model = {
    variables: [
      { name: "a", values: [1L, 2L, 3L], },
      { name: "b", values: [1L, 2L], },
    ],
    rules: [
      {
        id: "compatibility",
        rule: Table([Var("a"), Var("b")], [[1L, 2L], [3L, 1L]]),
      },
    ],
  }
  assert_eq(count(m), 2)
  assert_eq(count(one(Table([Var("x")], []))), 0)
  assert_eq(count(one(Table([], [[]]))), 5)
}

///|
test "count constraints count predicates rather than variables" {
  let r : @model.Rule = Count(
    [Ge(Var("x"), Int(0L)), Le(Var("x"), Int(0L))],
    2,
    2,
  )
  assert_eq(count(one(r)), 1)
  assert_eq(count(one(Count([], 0, 0))), 5)
}

///|
test "verifier rejects missing, extra, out-of-domain and tampered bindings" {
  let m = one(Eq(Var("x"), Int(1L)))
  assert_true(must(@model.check_assignment(m, { "x": 1L })).valid)
  assert_true(!must(@model.check_assignment(m, Map([]))).valid)
  assert_true(!must(@model.check_assignment(m, { "x": 1L, "y": 0L })).valid)
  assert_true(!must(@model.check_assignment(m, { "x": 99L })).valid)
  let report = must(@model.check_assignment(m, { "x": 2L }))
  assert_eq(report.violations, ["rule"])
}

///|
test "MRV search is deterministic and restores assignments between branches" {
  let m : @model.Model = {
    variables: [
      { name: "x", values: [3L, 1L, 2L], },
      { name: "y", values: [0L, 1L], },
    ],
    rules: [{ id: "sum", rule: Eq(Add(Var("x"), Var("y")), Int(3L)), }],
  }
  let a = must(@model.solve(m))
  let b = must(@model.solve(m))
  assert_eq(a.solutions.length(), 2)
  assert_eq(@model.search_to_json(a), @model.search_to_json(b))
  assert_eq(a.solutions[0].get("x"), Some(3L))
  assert_eq(a.solutions[1].get("x"), Some(2L))
}

///|
test "exact minimization reports proof only after complete traversal" {
  let m = one(Ge(Var("x"), Int(-1L)))
  let best = must(@model.minimize(m, Mul(Var("x"), Var("x"))))
  assert_eq(best.value, Some(0L))
  assert_true(best.optimal)
  let interrupted = must(@model.minimize(m, Var("x"), budget=0))
  assert_true(!interrupted.optimal)
  assert_eq(interrupted.stop, @model.BudgetLimit)
  assert_true(@model.minimize(m, Var("unknown")) is Err(_))
}

///|
test "undefined objective cannot be called an optimum" {
  let r = must(@model.minimize(one(All([])), Div(Int(1L), Int(0L))))
  assert_eq(r.value, None)
  assert_true(!r.optimal)
  assert_eq(r.stop, @model.Exhausted)
}

///|
test "conflicts are subset-minimal relative to domains" {
  let m : @model.Model = {
    variables: [{ name: "x", values: [0L, 1L, 2L], }],
    rules: [
      { id: "nonnegative", rule: Ge(Var("x"), Int(0L)), },
      { id: "low", rule: Le(Var("x"), Int(0L)), },
      { id: "high", rule: Ge(Var("x"), Int(1L)), },
    ],
  }
  let c = must(@model.explain(m))
  assert_eq(c.rule_ids, ["low", "high"])
  assert_true(c.irreducible)
  assert_true(@model.explain(one(All([]))) is Err(_))
  assert_true(
    @model.explain(one(Eq(Var("x"), Int(99L))), budget_per_check=0) is Err(_),
  )
}

///|
test "counterexamples negate only the named invariant" {
  let m : @model.Model = {
    variables: [{ name: "x", values: [-1L, 0L, 1L], }],
    rules: [
      { id: "precondition", rule: Ge(Var("x"), Int(0L)), },
      { id: "invariant", rule: Gt(Var("x"), Int(0L)), },
    ],
  }
  let counter = must(@model.negate_rule(m, "invariant"))
  let r = must(@model.solve(counter))
  assert_eq(r.solutions.length(), 1)
  assert_eq(r.solutions[0].get("x"), Some(0L))
  assert_eq(count(m), 1)
  assert_true(@model.negate_rule(m, "missing") is Err(_))
}

///|
test "JSON roundtrip preserves the full model and objective" {
  let doc : @model.Document = {
    model: one(
      All([
        Ne(Var("x"), Int(0L)),
        Any([Eq(Abs(Var("x")), Int(2L)), Eq(Mod(Var("x"), Int(2L)), Int(1L))]),
      ]),
    ),
    objective: Some(Add(Mul(Var("x"), Var("x")), Int(1L))),
  }
  assert_eq(
    must(@model.parse_document(@model.document_to_json(doc).stringify())),
    doc,
  )
}

///|
test "strict parser rejects malformed inputs rather than defaulting" {
  for
    s in [
      "", "[]", "{}", "{\"format\":\"kiln.model/2\",\"variables\":[],\"rules\":[]}",
      "{\"format\":\"kiln.model/1\",\"variables\":[],\"rules\":[],\"typo\":1}", "{\"format\":\"kiln.model/1\",\"variables\":[],\"rules\":[],\"format\":\"kiln.model/1\"}",
    ] {
    assert_true(@model.parse_document(s) is Err(_))
  }
}

///|
test "JSON integers never round or underflow at the input boundary" {
  for
    s in [
      "{\"x\":1.5}", "{\"x\":1.0000000000000001}", "{\"x\":1e-9999}", "{\"x\":1e0}",
      "{\"x\":1000000000001}", "{\"x\":-1000000000001}", "{\"x\":true}", "{\"x\":1,\"x\":2}",
    ] {
    assert_true(@model.parse_assignment(s) is Err(_))
  }
  assert_eq(
    must(@model.parse_assignment("{\"x\":-1000000000000}")).get("x"),
    Some(-1000000000000L),
  )
  assert_eq(must(@model.parse_assignment("{\"x\":-0}")).get("x"), Some(0L))
}

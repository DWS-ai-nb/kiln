///|
fn[T] must(r : Result[T, String]) -> T {
  match r {
    Ok(v) => v
    Err(e) => abort(e)
  }
}

///|
test "nested acceptance observes undefined atoms without losing change witnesses" {
  let atoms : Array[@model.Rule] = [
    AllDifferent([Int(1L), Int(1L), Div(Int(1L), Var("x"))]),
    Table([Int(1L), Div(Int(1L), Var("x"))], [[2L, 3L]]),
    Count([Eq(Int(1L), Int(1L)), Eq(Div(Int(1L), Var("x")), Int(1L))], 0, 0),
  ]
  for atom in atoms {
    let before = model(Not(Holds(Not(atom))), values=[0L, 1L])
    let after = model(Any([]), values=[0L, 1L])
    let r = must(@regression.compare(before, after))
    assert_eq(r.relation, @regression.Changed)
    assert_true(r.complete)
    assert_eq(r.changes.length(), 1)
    assert_eq(r.changes[0].assignment.get("x"), Some(0L))
    let closest = must(@regression.closest_change(before, after, { "x": 1L }))
    assert_eq(closest.distance, Some(1L))
    assert_true(closest.minimal)
  }
}

///|
test "large Hamming objectives stay inside the expression-depth limit" {
  let variables : Array[@model.Variable] = []
  let baseline : Map[String, Int64] = Map([])
  for i in 0..<100 {
    let name = "x\{i}"
    variables.push({ name, values: [0L], })
    baseline[name] = 0L
  }
  let before : @model.Model = { variables, rules: [], }
  let after : @model.Model = {
    variables,
    rules: [{ id: "reject", rule: Any([]), }],
  }
  let r = must(@regression.closest_change(before, after, baseline))
  assert_eq(r.distance, Some(0L))
  assert_true(r.minimal)
}

///|
fn model(
  rule : @model.Rule,
  values~ : Array[Int64] = [0L, 1L, 2L, 3L],
) -> @model.Model {
  { variables: [{ name: "x", values, }], rules: [{ id: "policy", rule, }], }
}

///|
test "equivalent arithmetic rewrites do not report syntactic changes" {
  let a = model(Eq(Add(Var("x"), Int(1L)), Int(3L)))
  let b = model(Eq(Var("x"), Int(2L)))
  let r = must(@regression.compare(a, b))
  assert_eq(r.relation, @regression.Equivalent)
  assert_true(r.complete)
  assert_eq(r.changes.length(), 0)
}

///|
test "changed acceptance is classified in both directions and replayed" {
  let a = model(Le(Var("x"), Int(1L)))
  let b = model(Ge(Var("x"), Int(1L)))
  let r = must(@regression.compare(a, b))
  assert_eq(r.relation, @regression.Changed)
  assert_true(r.complete)
  assert_eq(r.changes.length(), 3)
  assert_eq(r.changes[0].direction, @regression.RejectedByNew)
  assert_eq(r.changes[1].direction, @regression.AcceptedByNew)
  for c in r.changes {
    let replayed = must(@regression.replay(a, b, c.assignment))
    assert_eq(c.direction, replayed.direction)
    assert_true(c.before.valid != c.after.valid)
  }
}

///|
test "domain expansion and contraction are part of semantic changes" {
  let a = model(All([]), values=[0L, 1L])
  let b = model(All([]), values=[1L, 2L])
  let r = must(@regression.compare(a, b))
  assert_eq(r.scope[0].values, [0L, 1L, 2L])
  assert_eq(r.changes.length(), 2)
  assert_eq(r.changes[0].assignment.get("x"), Some(0L))
  assert_eq(r.changes[0].after.violations, ["outside domain: x"])
  assert_eq(r.changes[1].direction, @regression.AcceptedByNew)
}

///|
test "undefined arithmetic is rejected by the validator and compared correctly" {
  let a = model(All([]))
  let b = model(Eq(Div(Int(0L), Var("x")), Int(0L)))
  let r = must(@regression.compare(a, b))
  assert_eq(r.changes.length(), 1)
  assert_eq(r.changes[0].assignment.get("x"), Some(0L))
  assert_eq(r.changes[0].direction, @regression.RejectedByNew)
}

///|
test "empty original domain is not mistaken for an unrestricted one" {
  let a = model(All([]), values=[])
  let b = model(All([]), values=[1L])
  let r = must(@regression.compare(a, b))
  assert_eq(r.changes.length(), 1)
  assert_eq(r.changes[0].direction, @regression.AcceptedByNew)
}

///|
test "variable order and rule IDs do not change acceptance semantics" {
  let a : @model.Model = {
    variables: [
      { name: "x", values: [0L, 1L], },
      { name: "y", values: [0L, 1L], },
    ],
    rules: [{ id: "a", rule: Eq(Var("x"), Var("y")), }],
  }
  let b : @model.Model = {
    variables: [a.variables[1], a.variables[0]],
    rules: [{ id: "b", rule: Eq(Var("y"), Var("x")), }],
  }
  assert_eq(must(@regression.compare(a, b)).relation, @regression.Equivalent)
}

///|
test "unknown and changed-partial results never assert equivalence" {
  let a = model(All([]))
  let b = model(Any([]))
  let zero = must(@regression.compare(a, b, config=@model.options(budget=0)))
  assert_eq(zero.relation, @regression.Unknown)
  assert_true(!zero.complete)
  let one = must(
    @regression.compare(a, b, config=@model.options(max_solutions=1)),
  )
  assert_eq(one.relation, @regression.Changed)
  assert_true(!one.complete)
}

///|
test "closest counterexample minimizes changed fields rather than numeric magnitude" {
  let a : @model.Model = {
    variables: [
      { name: "x", values: [0L, 100L], },
      { name: "y", values: [0L, 1L], },
    ],
    rules: [],
  }
  let b : @model.Model = {
    variables: a.variables,
    rules: [{ id: "tightened", rule: Eq(Var("x"), Int(0L)), }],
  }
  let c = must(@regression.closest_change(a, b, { "x": 0L, "y": 0L }))
  assert_eq(c.distance, Some(1L))
  assert_true(c.minimal)
  match c.change {
    Some(change) => {
      assert_eq(change.assignment.get("x"), Some(100L))
      assert_eq(change.assignment.get("y"), Some(0L))
    }
    None => fail("expected changed assignment")
  }
}

///|
test "baseline equal to a changed assignment has distance zero" {
  let a = model(All([]))
  let b = model(Ne(Var("x"), Int(2L)))
  let c = must(@regression.closest_change(a, b, { "x": 2L }))
  assert_eq(c.distance, Some(0L))
  assert_true(c.minimal)
}

///|
test "closest-change budget is honest even if a candidate exists" {
  let a = model(All([]))
  let b = model(Any([]))
  let r = must(@regression.closest_change(a, b, { "x": 0L }, budget=0))
  assert_true(!r.minimal)
  assert_eq(r.stop, @model.BudgetLimit)
  assert_true(r.change is None)
}

///|
test "invalid baselines and mismatched variable sets are input errors" {
  let a = model(All([]))
  let b : @model.Model = {
    variables: [{ name: "y", values: [0L], }],
    rules: [],
  }
  assert_true(@regression.compare(a, b) is Err(_))
  assert_true(@regression.closest_change(a, a, { "x": 99L }) is Err(_))
  assert_true(@regression.closest_change(a, a, Map([])) is Err(_))
  assert_true(@regression.replay(a, a, { "x": 0L }) is Err(_))
}

///|
test "empty models can be compared with a constant semantic difference" {
  let a : @model.Model = { variables: [], rules: [], }
  let b : @model.Model = {
    variables: [],
    rules: [{ id: "false", rule: Any([]), }],
  }
  let r = must(@regression.compare(a, b, config=@model.options(budget=0)))
  assert_eq(r.relation, @regression.Changed)
  assert_true(r.complete)
  let c = must(@regression.closest_change(a, b, Map([]), budget=0))
  assert_eq(c.distance, Some(0L))
  assert_true(c.minimal)
}

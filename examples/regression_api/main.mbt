///|
fn[T] must(r : Result[T, String]) -> T {
  match r {
    Ok(v) => v
    Err(e) => abort(e)
  }
}

///|
/// Synthetic rule maintenance, directly embedded with no JSON/CLI or filesystem.
fn main {
  let before : @model.Model = {
    variables: [
      { name: "subtotal", values: [50L, 100L], },
      { name: "coupon", values: [0L, 50L], },
    ],
    rules: [],
  }
  let after : @model.Model = {
    variables: before.variables,
    rules: [
      {
        id: "nonnegative-charge",
        rule: Ge(Sub(Sub(Var("subtotal"), Int(10L)), Var("coupon")), Int(0L)),
      },
    ],
  }
  let diff = must(@regression.compare(before, after))
  if diff.relation != @regression.Changed ||
    !diff.complete ||
    diff.changes.length() != 1 {
    abort("expected one proven acceptance change")
  }
  let nearest = must(
    @regression.closest_change(before, after, { "subtotal": 50L, "coupon": 0L }),
  )
  if nearest.distance != Some(1L) || !nearest.minimal {
    abort("expected exact distance one")
  }
  let checked = must(
    @regression.replay(before, after, diff.changes[0].assignment),
  )
  if !checked.before.valid || checked.after.valid {
    abort("witness replay failed")
  }
  println("rule regression: changes=1, minimum_fields=1, replay=true")
  println(@regression.change_to_json(checked).stringify())
}

///|
pub(all) enum Direction {
  RejectedByNew
  AcceptedByNew
} derive(Debug, Eq)

///|
pub extend Direction with @debug.Debug::{to_repr}

///|
pub extend Direction with Eq::{equal, not_equal}

///|
pub(all) enum Relation {
  Equivalent
  Changed
  Unknown
} derive(Debug, Eq)

///|
pub extend Relation with @debug.Debug::{to_repr}

///|
pub extend Relation with Eq::{equal, not_equal}

///|
pub(all) struct Change {
  assignment : Map[String, Int64]
  direction : Direction
  before : @model.CheckReport
  after : @model.CheckReport
} derive(Debug)

///|
pub extend Change with @debug.Debug::{to_repr}

///|
pub(all) struct Comparison {
  scope : Array[@model.Variable]
  relation : Relation
  changes : Array[Change]
  /// All changed assignments in the union of the two declared finite domains.
  complete : Bool
  stop : @model.Stop
  stats : @model.Statistics
} derive(Debug)

///|
pub extend Comparison with @debug.Debug::{to_repr}

///|
pub(all) struct Closest {
  change : Change?
  /// Hamming distance: number of variables different from the baseline.
  distance : Int64?
  /// True only after exhaustive minimization; not a lexicographic guarantee.
  minimal : Bool
  stop : @model.Stop
  stats : @model.Statistics
} derive(Debug)

///|
pub extend Closest with @debug.Debug::{to_repr}

///|
/// Turn a model into its acceptance predicate, including its ORIGINAL domains.
/// Holds is necessary: malformed arithmetic is rejection for a validator,
/// whereas mathematical Not(undefined) remains undefined in the model engine.
fn accepts(model : @model.Model) -> @model.Rule {
  let predicates : Array[@model.Rule] = []
  for v in model.variables {
    predicates.push(Table([Var(v.name)], v.values.map(n => [n])))
  }
  for r in model.rules {
    predicates.push(r.rule)
  }
  Holds(All(predicates))
}

///|
/// Construct the symmetric difference in a finite, explicit union scope.
/// Variable names must agree as sets; order, domains and rule IDs may differ.
pub fn difference_model(
  before : @model.Model,
  after : @model.Model,
) -> Result[@model.Model, String] {
  if @model.validate(before) is Err(e) {
    return Err("before: " + e)
  }
  if @model.validate(after) is Err(e) {
    return Err("after: " + e)
  }
  if before.variables.length() != after.variables.length() {
    return Err("variable-name sets differ; provide an explicit mapping first")
  }
  let other : Map[String, Array[Int64]] = Map([])
  for v in after.variables {
    other[v.name] = v.values
  }
  let variables : Array[@model.Variable] = []
  for v in before.variables {
    let additional = match other.get(v.name) {
      None => return Err("variable-name sets differ: " + v.name)
      Some(a) => a
    }
    let values = v.values.copy()
    for n in additional {
      if !values.contains(n) {
        values.push(n)
      }
    }
    values.sort()
    variables.push({ name: v.name, values, })
  }
  variables.sort_by((a, b) => a.name.compare(b.name))
  let old = accepts(before)
  let new = accepts(after)
  let model : @model.Model = {
    variables,
    rules: [
      {
        id: "semantic-difference",
        rule: Any([All([old, Not(new)]), All([Not(old), new])]),
      },
    ],
  }
  match @model.validate(model) {
    Ok(_) => Ok(model)
    Err(e) => Err("combined comparison model: " + e)
  }
}

///|
/// Re-evaluate a supplied witness on both ORIGINAL models. This does not trust
/// a previous comparison report, its direction, or its search statistics.
pub fn replay(
  before : @model.Model,
  after : @model.Model,
  assignment : Map[String, Int64],
) -> Result[Change, String] {
  let old = match @model.check_assignment(before, assignment) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let new = match @model.check_assignment(after, assignment) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  if old.valid == new.valid {
    return Err("assignment does not distinguish the two models")
  }
  Ok({
    assignment: assignment.copy(),
    direction: if old.valid {
      RejectedByNew
    } else {
      AcceptedByNew
    },
    before: old,
    after: new,
  })
}

///|
/// Changed is proved by a single replayed witness. Equivalent requires complete
/// search with zero witnesses. Unknown never means compatible or equivalent.
pub fn compare(
  before : @model.Model,
  after : @model.Model,
  config~ : @model.Options = @model.options(),
) -> Result[Comparison, String] {
  let combined = match difference_model(before, after) {
    Ok(m) => m
    Err(e) => return Err(e)
  }
  let result = match @model.solve(combined, config~) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let changes : Array[Change] = []
  for assignment in result.solutions {
    match replay(before, after, assignment) {
      Ok(c) => changes.push(c)
      Err(e) => return Err("internal witness replay failed: " + e)
    }
  }
  Ok({
    scope: combined.variables,
    relation: if !changes.is_empty() {
      Changed
    } else if result.stop == @model.Exhausted {
      Equivalent
    } else {
      Unknown
    },
    changes,
    complete: result.stop == @model.Exhausted,
    stop: result.stop,
    stats: result.stats,
  })
}

///|
/// Find a distinguishing configuration with a minimum number of changed input
/// fields relative to a supplied baseline. Ties follow deterministic search
/// order. The minimum is exact ONLY when minimal=true; this can be exponential.
pub fn closest_change(
  before : @model.Model,
  after : @model.Model,
  baseline : Map[String, Int64],
  budget~ : Int32 = 100000,
) -> Result[Closest, String] {
  let combined = match difference_model(before, after) {
    Ok(m) => m
    Err(e) => return Err(e)
  }
  let domain_only : @model.Model = { variables: combined.variables, rules: [], }
  match @model.check_assignment(domain_only, baseline) {
    Err(e) => return Err(e)
    Ok(r) =>
      if !r.valid {
        return Err(
          "baseline must bind exactly the comparison variables inside their union domains",
        )
      }
  }
  let terms : Array[@model.Term] = []
  for v in combined.variables {
    let value = match baseline.get(v.name) {
      Some(n) => n
      None => return Err("missing baseline variable")
    }
    terms.push(Indicator(Ne(Var(v.name), Int(value))))
  }
  let objective = balanced_sum(terms, 0, terms.length())
  let result = match @model.minimize(combined, objective, budget~) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let change = match result.assignment {
    None => None
    Some(a) =>
      match replay(before, after, a) {
        Ok(c) => Some(c)
        Err(e) => return Err("internal witness replay failed: " + e)
      }
  }
  Ok({
    change,
    distance: result.value,
    minimal: result.optimal,
    stop: result.stop,
    stats: result.stats,
  })
}

///|
fn balanced_sum(
  terms : Array[@model.Term],
  lo : Int32,
  hi : Int32,
) -> @model.Term {
  if lo == hi {
    return Int(0L)
  }
  if hi - lo == 1 {
    return terms[lo]
  }
  let mid = lo + (hi - lo) / 2
  Add(balanced_sum(terms, lo, mid), balanced_sum(terms, mid, hi))
}

///|
pub fn change_to_json(change : Change) -> Json {
  let j : Map[String, Json] = Map([])
  j["assignment"] = @model.assignment_to_json(change.assignment)
  j["direction"] = Json::string(
    if change.direction == RejectedByNew {
      "rejected_by_new"
    } else {
      "accepted_by_new"
    },
  )
  j["before_valid"] = Json::boolean(change.before.valid)
  j["after_valid"] = Json::boolean(change.after.valid)
  j["before_violations"] = Json::array(
    change.before.violations.map(Json::string),
  )
  j["after_violations"] = Json::array(change.after.violations.map(Json::string))
  Json::object(j)
}

///|
pub fn comparison_to_json(report : Comparison) -> Json {
  let j : Map[String, Json] = Map([])
  j["format"] = Json::string("kiln.diff/1")
  j["relation"] = Json::string(
    match report.relation {
      Equivalent => "equivalent"
      Changed => "changed"
      Unknown => "unknown"
    },
  )
  j["complete"] = Json::boolean(report.complete)
  j["stop"] = Json::string(@model.stop_name(report.stop))
  j["statistics"] = @model.statistics_to_json(report.stats)
  j["changes"] = Json::array(report.changes.map(change_to_json))
  j["scope"] = @model.document_to_json({
    model: { variables: report.scope, rules: [], },
    objective: None,
  })
  Json::object(j)
}

///|
pub fn closest_to_json(report : Closest) -> Json {
  let j : Map[String, Json] = Map([])
  j["format"] = Json::string("kiln.closest/1")
  j["minimal"] = Json::boolean(report.minimal)
  j["stop"] = Json::string(@model.stop_name(report.stop))
  j["statistics"] = @model.statistics_to_json(report.stats)
  j["distance"] = match report.distance {
    Some(n) => Json::number(n.to_double())
    None => Json::null()
  }
  j["change"] = match report.change {
    Some(c) => change_to_json(c)
    None => Json::null()
  }
  Json::object(j)
}

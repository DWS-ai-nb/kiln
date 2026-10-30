///|
priv struct Search {
  model : Model
  config : Options
  objective : Term?
  solutions : Array[Map[String, Int64]]
  mut best : Int64?
  mut probes : Int32
  mut nodes : Int32
  mut pruned : Int32
  mut seen : Int32
  mut stop : Stop
}

///|
fn Search::stats(self : Search) -> Statistics {
  {
    probes: self.probes,
    nodes: self.nodes,
    pruned: self.pruned,
    solutions_seen: self.seen,
  }
}

///|
fn possible(model : Model, env : Map[String, Int64]) -> Bool {
  for r in model.rules {
    match judge(r.rule, env) {
      Ok(Some(false)) | Err(_) => return false
      _ => ()
    }
  }
  true
}

///|
fn Search::visit(self : Search, env : Map[String, Int64]) -> Unit {
  self.nodes += 1
  if !possible(self.model, env) {
    self.pruned += 1
    return
  }
  if env.length() == self.model.variables.length() {
    match self.objective {
      Some(t) =>
        match evaluate_partial(t, env) {
          Ok(Some(value)) => {
            self.seen += 1
            let improves = match self.best {
              None => true
              Some(old) => value < old
            }
            if improves {
              self.best = Some(value)
              self.solutions.clear()
              self.solutions.push(env.copy())
            }
          }
          _ => self.pruned += 1
        }
      None => {
        self.seen += 1
        self.solutions.push(env.copy())
        if self.solutions.length() >= self.config.max_solutions {
          self.stop = SolutionLimit
        }
      }
    }
    return
  }
  // A complete forward-check pass for each unbound variable. Every candidate
  // is charged before evaluation. MRV ties follow declaration/domain order.
  let mut chosen : Variable? = None
  let mut candidates : Array[Int64] = []
  for v in self.model.variables {
    if env.contains(v.name) {
      continue
    }
    let supported : Array[Int64] = []
    for n in v.values {
      if self.probes >= self.config.budget {
        self.stop = BudgetLimit
        return
      }
      self.probes += 1
      env[v.name] = n
      let ok = possible(self.model, env)
      env.remove(v.name)
      if ok {
        supported.push(n)
      } else {
        self.pruned += 1
      }
    }
    if supported.is_empty() {
      return
    }
    if chosen is None || supported.length() < candidates.length() {
      chosen = Some(v)
      candidates = supported
    }
    if candidates.length() == 1 {
      break
    }
  }
  if chosen is Some(v) {
    for n in candidates {
      env[v.name] = n
      self.visit(env)
      env.remove(v.name)
      if self.stop != Exhausted {
        return
      }
    }
  }
}

///|
fn run_search(
  model : Model,
  config : Options,
  objective : Term?,
) -> Result[Search, String] {
  if validate(model) is Err(e) {
    return Err(e)
  }
  if config.budget < 0 ||
    config.budget > 100000000 ||
    config.max_solutions < 1 ||
    config.max_solutions > 1000000 {
    return Err("budget must be 0..100000000; max_solutions must be 1..1000000")
  }
  if objective is Some(t) {
    if validate_objective(model, t) is Err(e) {
      return Err(e)
    }
  }
  let search : Search = {
    model,
    config,
    objective,
    solutions: [],
    best: None,
    probes: 0,
    nodes: 0,
    pruned: 0,
    seen: 0,
    stop: Exhausted,
  }
  // An empty domain is a complete, zero-work contradiction even at budget 0.
  for v in model.variables {
    if v.values.is_empty() {
      return Ok(search)
    }
  }
  search.visit(Map([]))
  Ok(search)
}

///|
/// Enumerate exact finite-domain solutions. Exhausted is the only signal that
/// the stored list is complete. BudgetLimit can carry useful feasible witnesses.
pub fn solve(
  model : Model,
  config~ : Options = options(),
) -> Result[SearchResult, String] {
  match run_search(model, config, None) {
    Err(e) => Err(e)
    Ok(s) => Ok({ solutions: s.solutions, stop: s.stop, stats: s.stats(), })
  }
}

///|
pub fn classify(
  model : Model,
  budget~ : Int32 = 100000,
) -> Result[Classification, String] {
  match solve(model, config=options(budget~, max_solutions=2)) {
    Err(e) => Err(e)
    Ok(r) => {
      if r.solutions.length() >= 2 {
        return Ok(Multiple(r.solutions[0], r.solutions[1]))
      }
      if r.stop != Exhausted {
        return Ok(Unknown)
      }
      if r.solutions.is_empty() {
        Ok(Unsatisfiable)
      } else {
        Ok(Unique(r.solutions[0]))
      }
    }
  }
}

///|
/// Exact minimization by enumeration, with a work budget. No claim of optimality
/// is made until all feasible assignments (and defined objectives) are visited.
/// Undefined objectives are excluded from the optimization's feasible set.
pub fn minimize(
  model : Model,
  objective : Term,
  budget~ : Int32 = 100000,
) -> Result[Optimization, String] {
  match run_search(model, options(budget~), Some(objective)) {
    Err(e) => Err(e)
    Ok(s) =>
      Ok({
        assignment: s.solutions.last(),
        value: s.best,
        optimal: s.stop == Exhausted && s.best is Some(_),
        stop: s.stop,
        stats: s.stats(),
      })
  }
}

///|
/// Explain a proved contradiction using deletion checks. Each check has the
/// supplied budget. Incomplete checks preserve a known-unsatisfiable superset
/// and set irreducible=false. Domains are implicit constraints and never removed.
pub fn explain(
  model : Model,
  budget_per_check~ : Int32 = 100000,
) -> Result[Conflict, String] {
  match solve(model, config=options(budget=budget_per_check, max_solutions=1)) {
    Err(e) => return Err(e)
    Ok(r) => {
      if !r.solutions.is_empty() {
        return Err("model is satisfiable")
      }
      if r.stop != Exhausted {
        return Err("unsatisfiability is unknown: budget exhausted")
      }
    }
  }
  let mut current = model.rules.copy()
  let mut i = 0
  let mut complete = true
  let mut checks = 1
  while i < current.length() {
    let subset : Array[NamedRule] = []
    for j, r in current {
      if j != i {
        subset.push(r)
      }
    }
    let trial : Model = { variables: model.variables, rules: subset, }
    checks += 1
    match
      solve(trial, config=options(budget=budget_per_check, max_solutions=1)) {
      Err(e) => return Err(e)
      Ok(r) =>
        if r.stop == Exhausted && r.solutions.is_empty() {
          current = subset
        } else {
          if r.solutions.is_empty() {
            complete = false
          }
          i += 1
        }
    }
  }
  Ok({ rule_ids: current.map(r => r.id), irreducible: complete, checks, })
}

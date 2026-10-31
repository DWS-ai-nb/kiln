///|
fn checked(n : Int64) -> Result[Int64, String] {
  if n < -LIMIT || n > LIMIT {
    Err("arithmetic exceeds +/-10^12")
  } else {
    Ok(n)
  }
}

///|
fn arithmetic(op : Term, a : Int64, b : Int64) -> Result[Int64, String] {
  match op {
    Add(_, _) => checked(a + b)
    Sub(_, _) => checked(a - b)
    Mul(_, _) => {
      let aa = if a < 0L { -a } else { a }
      let bb = if b < 0L { -b } else { b }
      if bb != 0L && aa > LIMIT / bb {
        Err("multiplication exceeds +/-10^12")
      } else {
        Ok(a * b)
      }
    }
    Div(_, _) => if b == 0L { Err("division by zero") } else { checked(a / b) }
    Mod(_, _) => if b == 0L { Err("modulo by zero") } else { checked(a % b) }
    _ => Err("invalid arithmetic operator")
  }
}

///|
/// None means an unbound variable. Err means undefined arithmetic. These are
/// kept separate so that Not(division-by-zero == 1) cannot become a witness.
fn evaluate_partial(
  t : Term,
  env : Map[String, Int64],
) -> Result[Int64?, String] {
  match t {
    Indicator(r) =>
      match judge(r, env) {
        Ok(Some(b)) => Ok(Some(if b { 1L } else { 0L }))
        Ok(None) => Ok(None)
        Err(e) => Err(e)
      }
    Int(n) =>
      match checked(n) {
        Ok(n) => Ok(Some(n))
        Err(e) => Err(e)
      }
    Var(n) => Ok(env.get(n))
    Neg(a) | Abs(a) =>
      match evaluate_partial(a, env) {
        Err(e) => Err(e)
        Ok(None) => Ok(None)
        Ok(Some(n)) =>
          Ok(Some(if t is Neg(_) { -n } else if n < 0L { -n } else { n }))
      }
    Add(a, b) | Sub(a, b) | Mul(a, b) | Div(a, b) | Mod(a, b) => {
      let left = evaluate_partial(a, env)
      let right = evaluate_partial(b, env)
      match (left, right) {
        (Err(e), _) | (_, Err(e)) => Err(e)
        (Ok(Some(x)), Ok(Some(y))) =>
          match arithmetic(t, x, y) {
            Ok(z) => Ok(Some(z))
            Err(e) => Err(e)
          }
        _ => Ok(None)
      }
    }
  }
}

///|
/// Evaluate a term in a complete environment. Use validate/check_assignment at
/// an untrusted boundary; this function still rejects out-of-range bindings.
pub fn evaluate(
  term : Term,
  assignment : Map[String, Int64],
) -> Result[Int64, String] {
  for _, n in assignment {
    if n < -LIMIT || n > LIMIT {
      return Err("binding outside +/-10^12")
    }
  }
  match evaluate_partial(term, assignment) {
    Ok(Some(n)) => Ok(n)
    Ok(None) => Err("unbound variable")
    Err(e) => Err(e)
  }
}

///|
fn judge(r : Rule, env : Map[String, Int64]) -> Result[Bool?, String] {
  match r {
    Holds(child) =>
      match judge(child, env) {
        Err(_) => Ok(Some(false))
        other => other
      }
    Eq(a, b) | Ne(a, b) | Lt(a, b) | Le(a, b) | Gt(a, b) | Ge(a, b) =>
      match (evaluate_partial(a, env), evaluate_partial(b, env)) {
        (Err(e), _) | (_, Err(e)) => Err(e)
        (Ok(Some(x)), Ok(Some(y))) =>
          Ok(
            Some(
              match r {
                Eq(_, _) => x == y
                Ne(_, _) => x != y
                Lt(_, _) => x < y
                Le(_, _) => x <= y
                Gt(_, _) => x > y
                _ => x >= y
              },
            ),
          )
        _ => Ok(None)
      }
    All(rs) | Any(rs) => {
      let conjunction = r is All(_)
      let mut pending = false
      let mut error : String? = None
      for child in rs {
        match judge(child, env) {
          Ok(Some(b)) => if b != conjunction { return Ok(Some(b)) }
          Ok(None) => pending = true
          Err(e) => error = Some(e)
        }
      }
      // A missing guard may eventually mask an undefined branch. Do not prune.
      if pending {
        Ok(None)
      } else {
        match error {
          Some(e) => Err(e)
          None => Ok(Some(conjunction))
        }
      }
    }
    Not(child) =>
      match judge(child, env) {
        Ok(Some(b)) => Ok(Some(!b))
        other => other
      }
    Implies(a, b) => judge(Any([Not(a), b]), env)
    AllDifferent(ts) => {
      let seen : Map[Int64, Bool] = Map([])
      let mut pending = false
      let mut error : String? = None
      let mut duplicate = false
      for t in ts {
        match evaluate_partial(t, env) {
          Err(e) => error = Some(e)
          Ok(None) => pending = true
          Ok(Some(n)) => {
            if seen.contains(n) {
              duplicate = true
            }
            seen[n] = true
          }
        }
      }
      match error {
        Some(e) => Err(e)
        None =>
          // A later undefined term changes this atom from false to undefined.
          // Holds/Not can observe that change, so false is not stable yet.
          if pending {
            Ok(None)
          } else {
            Ok(Some(!duplicate))
          }
      }
    }
    Table(ts, rows) => {
      let values : Array[Int64?] = []
      let mut pending = false
      let mut error : String? = None
      for t in ts {
        match evaluate_partial(t, env) {
          Err(e) => {
            error = Some(e)
            values.push(None)
          }
          Ok(v) => {
            if v is None {
              pending = true
            }
            values.push(v)
          }
        }
      }
      if error is Some(e) {
        return Err(e)
      }
      let mut supported = false
      for row in rows {
        let mut fits = true
        for i, v in values {
          if v is Some(n) {
            if n != row[i] {
              fits = false
            }
          }
        }
        if fits {
          supported = true
          break
        }
      }
      if pending {
        Ok(None)
      } else {
        Ok(Some(supported))
      }
    }
    Count(rs, lo, hi) => {
      let mut yes = 0
      let mut pending = 0
      let mut error : String? = None
      for child in rs {
        match judge(child, env) {
          Ok(Some(true)) => yes += 1
          Ok(Some(false)) => ()
          Ok(None) => pending += 1
          Err(e) => error = Some(e)
        }
      }
      if error is Some(e) {
        return Err(e)
      }
      // A pending predicate may become undefined, which is observable through
      // Holds. Even an already exceeded count is not a stable false result.
      if pending > 0 {
        Ok(None)
      } else {
        Ok(Some(yes >= lo && yes <= hi))
      }
    }
  }
}

///|
/// The verifier does not call the searcher or trust search statistics. It
/// checks every original domain and rule, including missing/extra bindings.
pub fn check_assignment(
  model : Model,
  assignment : Map[String, Int64],
) -> Result[CheckReport, String] {
  if validate(model) is Err(e) {
    return Err(e)
  }
  let violations : Array[String] = []
  let names : Map[String, Bool] = Map([])
  for v in model.variables {
    names[v.name] = true
    match assignment.get(v.name) {
      None => violations.push("missing variable: " + v.name)
      Some(n) =>
        if !v.values.contains(n) {
          violations.push("outside domain: " + v.name)
        }
    }
  }
  for name, _ in assignment {
    if !names.contains(name) {
      violations.push("extra variable: " + name)
    }
  }
  // Stop before arithmetic on untrusted domain values (which could overflow).
  if !violations.is_empty() {
    return Ok({ valid: false, violations, })
  }
  for rule in model.rules {
    match judge(rule.rule, assignment) {
      Ok(Some(true)) => ()
      Ok(Some(false)) => violations.push(rule.id)
      Ok(None) => violations.push(rule.id + ": unbound variable")
      Err(e) => violations.push(rule.id + ": " + e)
    }
  }
  Ok({ valid: violations.is_empty(), violations, })
}

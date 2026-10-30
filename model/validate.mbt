///|
fn term_error(
  t : Term,
  names : Map[String, Bool],
  depth : Int32,
  size : Ref[Int32],
) -> String? {
  size.val += 1
  if depth > 48 || size.val > 8192 {
    return Some("expression exceeds depth/size limit")
  }
  match t {
    Int(n) =>
      if n < -LIMIT || n > LIMIT {
        Some("integer outside +/-10^12")
      } else {
        None
      }
    Var(n) =>
      if names.contains(n) {
        None
      } else {
        Some("unknown variable: " + n)
      }
    Neg(a) | Abs(a) => term_error(a, names, depth + 1, size)
    Add(a, b) | Sub(a, b) | Mul(a, b) | Div(a, b) | Mod(a, b) =>
      match term_error(a, names, depth + 1, size) {
        Some(e) => Some(e)
        None => term_error(b, names, depth + 1, size)
      }
  }
}

///|
fn rule_error(
  r : Rule,
  names : Map[String, Bool],
  depth : Int32,
  size : Ref[Int32],
) -> String? {
  size.val += 1
  if depth > 48 || size.val > 8192 {
    return Some("rule exceeds depth/size limit")
  }
  match r {
    Eq(a, b) | Ne(a, b) | Lt(a, b) | Le(a, b) | Gt(a, b) | Ge(a, b) => {
      match term_error(a, names, depth + 1, size) {
        Some(e) => return Some(e)
        None => ()
      }
      term_error(b, names, depth + 1, size)
    }
    All(rs) | Any(rs) | Count(rs, _, _) => {
      if r is Count(_, lo, hi) {
        if lo < 0 || hi < lo || hi > rs.length() {
          return Some("invalid count bounds")
        }
      }
      for child in rs {
        if rule_error(child, names, depth + 1, size) is Some(e) {
          return Some(e)
        }
      }
      None
    }
    Not(child) => rule_error(child, names, depth + 1, size)
    Implies(a, b) =>
      match rule_error(a, names, depth + 1, size) {
        Some(e) => Some(e)
        None => rule_error(b, names, depth + 1, size)
      }
    AllDifferent(ts) | Table(ts, _) => {
      for t in ts {
        if term_error(t, names, depth + 1, size) is Some(e) {
          return Some(e)
        }
      }
      if r is Table(_, rows) {
        if rows.length() > 4096 {
          return Some("table has more than 4096 rows")
        }
        for row in rows {
          size.val += row.length()
          if size.val > 8192 {
            return Some("table exceeds model size limit")
          }
          if row.length() != ts.length() {
            return Some("table row arity mismatch")
          }
          for n in row {
            if n < -LIMIT || n > LIMIT {
              return Some("table integer outside +/-10^12")
            }
          }
        }
      }
      None
    }
  }
}

///|
/// Empty domains are legal and make a model unsatisfiable. Duplicate values,
/// names or rule IDs are errors, because they make counting/diagnosis ambiguous.
pub fn validate(model : Model) -> Result[Unit, String] {
  if model.variables.length() > 128 || model.rules.length() > 256 {
    return Err("model exceeds 128 variables / 256 rules")
  }
  let names : Map[String, Bool] = Map([])
  let mut total = 0
  for v in model.variables {
    if v.name == "" || v.name.length() > 128 {
      return Err("invalid variable name")
    }
    if names.contains(v.name) {
      return Err("duplicate variable: " + v.name)
    }
    names[v.name] = true
    total += v.values.length()
    if v.values.length() > 2048 || total > 16384 {
      return Err("domain size limit exceeded")
    }
    let values : Map[Int64, Bool] = Map([])
    for n in v.values {
      if n < -LIMIT || n > LIMIT {
        return Err(v.name + ": domain integer outside +/-10^12")
      }
      if values.contains(n) {
        return Err(v.name + ": duplicate domain value")
      }
      values[n] = true
    }
  }
  let ids : Map[String, Bool] = Map([])
  let size = Ref(0)
  for r in model.rules {
    if r.id == "" || r.id.length() > 128 {
      return Err("invalid rule id")
    }
    if ids.contains(r.id) {
      return Err("duplicate rule id: " + r.id)
    }
    ids[r.id] = true
    if rule_error(r.rule, names, 0, size) is Some(e) {
      return Err(r.id + ": " + e)
    }
  }
  Ok(())
}

///|
fn validate_objective(model : Model, term : Term) -> Result[Unit, String] {
  let names : Map[String, Bool] = Map([])
  for v in model.variables {
    names[v.name] = true
  }
  match term_error(term, names, 0, Ref(0)) {
    Some(e) => Err("objective: " + e)
    None => Ok(())
  }
}

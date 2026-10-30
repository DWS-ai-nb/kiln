///|
pub(all) struct Document {
  model : Model
  objective : Term?
} derive(Debug, Eq)

///|
pub extend Document with @debug.Debug::{to_repr}

///|
pub extend Document with Eq::{equal, not_equal}

///|
priv suberror InputError {
  InputError(String)
}

///|
fn fields(
  j : Json,
  allowed : Array[String],
  path : String,
) -> Unit raise InputError {
  match j {
    Object(m) =>
      for k, _ in m {
        if !allowed.contains(k) {
          raise InputError(path + ": unknown field " + k)
        }
      }
    _ => raise InputError(path + ": expected object")
  }
}

///|
fn field(j : Json, key : String, path : String) -> Json raise InputError {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(v) => v
        None => raise InputError(path + ": missing field " + key)
      }
    _ => raise InputError(path + ": expected object")
  }
}

///|
fn array(j : Json, path : String) -> Array[Json] raise InputError {
  match j {
    Array(a) => a
    _ => raise InputError(path + ": expected array")
  }
}

///|
fn text_value(j : Json, path : String) -> String raise InputError {
  match j {
    String(s) => s
    _ => raise InputError(path + ": expected string")
  }
}

///|
fn integer(j : Json, path : String) -> Int64 raise InputError {
  match j {
    Number(d, repr~) => {
      // Preserve lexical integers: 1.0000000000000001 must not round to 1,
      // and 1e-9999 must not silently underflow to 0 at the input boundary.
      if repr is Some(raw) {
        let cs = raw.to_array()
        let negative = !cs.is_empty() && cs[0] == '-'
        let start = if negative { 1 } else { 0 }
        let mut n = 0L
        if cs.length() == start {
          raise InputError(path + ": expected integer spelling")
        }
        for i in start..<cs.length() {
          let c = cs[i]
          if c < '0' || c > '9' {
            raise InputError(
              path + ": use an integer spelling without decimal/exponent",
            )
          }
          let digit = (c.to_int() - '0'.to_int()).to_int64()
          if n > (LIMIT - digit) / 10L {
            raise InputError(path + ": integer outside +/-10^12")
          }
          n = n * 10L + digit
        }
        return if negative { -n } else { n }
      }
      if d.is_nan() || d < -1000000000000.0 || d > 1000000000000.0 {
        raise InputError(path + ": integer outside +/-10^12")
      }
      let n = d.to_int64()
      if n.to_double() != d {
        raise InputError(path + ": expected integer")
      }
      n
    }
    _ => raise InputError(path + ": expected integer number")
  }
}

///|
fn parse_term(
  j : Json,
  depth : Int32,
  size : Ref[Int32],
  path : String,
) -> Term raise InputError {
  size.val += 1
  if depth > 48 || size.val > 8192 {
    raise InputError(path + ": expression size/depth exceeded")
  }
  match j {
    Number(_, ..) => Int(integer(j, path))
    String(s) => Var(s)
    Array(a) => {
      if a.is_empty() {
        raise InputError(path + ": empty term")
      }
      let op = text_value(a[0], path + "[0]")
      if op == "indicator" {
        if a.length() != 2 {
          raise InputError(path + ": indicator expects one rule")
        }
        return Indicator(parse_rule(a[1], depth + 1, size, path + "[1]"))
      }
      let arity = if op == "neg" || op == "abs" { 2 } else { 3 }
      if a.length() != arity {
        raise InputError(path + ": wrong term arity for " + op)
      }
      let x = parse_term(a[1], depth + 1, size, path + "[1]")
      if arity == 2 {
        if op == "neg" {
          Neg(x)
        } else {
          Abs(x)
        }
      } else {
        let y = parse_term(a[2], depth + 1, size, path + "[2]")
        match op {
          "+" => Add(x, y)
          "-" => Sub(x, y)
          "*" => Mul(x, y)
          "/" => Div(x, y)
          "%" => Mod(x, y)
          _ => raise InputError(path + ": unknown arithmetic operator " + op)
        }
      }
    }
    _ =>
      raise InputError(path + ": expected number, variable name or term array")
  }
}

///|
fn parse_rule(
  j : Json,
  depth : Int32,
  size : Ref[Int32],
  path : String,
) -> Rule raise InputError {
  size.val += 1
  if depth > 48 || size.val > 8192 {
    raise InputError(path + ": rule size/depth exceeded")
  }
  let a = array(j, path)
  if a.is_empty() {
    raise InputError(path + ": empty rule")
  }
  let op = text_value(a[0], path + "[0]")
  if op == "all" || op == "any" {
    let rs : Array[Rule] = []
    for i in 1..<a.length() {
      rs.push(parse_rule(a[i], depth + 1, size, path + "[\{i}]"))
    }
    return if op == "all" { All(rs) } else { Any(rs) }
  }
  if op == "not" || op == "holds" {
    if a.length() != 2 {
      raise InputError(path + ": not expects one rule")
    }
    let child = parse_rule(a[1], depth + 1, size, path + "[1]")
    return if op == "not" { Not(child) } else { Holds(child) }
  }
  if op == "distinct" {
    let ts : Array[Term] = []
    for i in 1..<a.length() {
      ts.push(parse_term(a[i], depth + 1, size, path + "[\{i}]"))
    }
    return AllDifferent(ts)
  }
  if op == "count" {
    if a.length() != 4 {
      raise InputError(path + ": count expects lower, upper, rules")
    }
    let lo = integer(a[1], path + "[1]")
    let hi = integer(a[2], path + "[2]")
    if lo < 0L || hi > 8192L || lo > hi {
      raise InputError(path + ": invalid count bounds")
    }
    let rs : Array[Rule] = []
    for i, child in array(a[3], path + "[3]") {
      rs.push(parse_rule(child, depth + 1, size, path + "[3][\{i}]"))
    }
    return Count(rs, lo.to_int(), hi.to_int())
  }
  if a.length() != 3 {
    raise InputError(path + ": wrong rule arity for " + op)
  }
  if op == "implies" {
    return Implies(
      parse_rule(a[1], depth + 1, size, path + "[1]"),
      parse_rule(a[2], depth + 1, size, path + "[2]"),
    )
  }
  if op == "table" {
    let ts : Array[Term] = []
    for i, t in array(a[1], path + "[1]") {
      ts.push(parse_term(t, depth + 1, size, path + "[1][\{i}]"))
    }
    let rows : Array[Array[Int64]] = []
    for i, row in array(a[2], path + "[2]") {
      let values : Array[Int64] = []
      for k, value in array(row, path + "[2][\{i}]") {
        values.push(integer(value, path + "[2][\{i}][\{k}]"))
      }
      size.val += values.length()
      if size.val > 8192 {
        raise InputError(path + ": table size exceeded")
      }
      rows.push(values)
    }
    return Table(ts, rows)
  }
  let x = parse_term(a[1], depth + 1, size, path + "[1]")
  let y = parse_term(a[2], depth + 1, size, path + "[2]")
  match op {
    "==" => Eq(x, y)
    "!=" => Ne(x, y)
    "<" => Lt(x, y)
    "<=" => Le(x, y)
    ">" => Gt(x, y)
    ">=" => Ge(x, y)
    _ => raise InputError(path + ": unknown rule operator " + op)
  }
}

///|
/// Strict, versioned JSON: duplicate keys, unknown fields, fractional integers,
/// dangling variables and oversized input are rejected with a useful path.
pub fn parse_document(src : String) -> Result[Document, String] {
  if src.length() > 1048576 {
    return Err("input exceeds 1 MiB of UTF-16 units")
  }
  try {
    let root = @json.parse(
      src,
      max_nesting_depth=64,
      reject_duplicate_keys=true,
      preserve_number_repr=true,
    )
    fields(
      root,
      ["format", "variables", "rules", "objective", "description"],
      "$",
    )
    let format = text_value(field(root, "format", "$"), "$.format")
    if format != "kiln.model/1" {
      raise InputError("$.format: expected kiln.model/1")
    }
    let vs = array(field(root, "variables", "$"), "$.variables")
    let rs = array(field(root, "rules", "$"), "$.rules")
    if vs.length() > 128 || rs.length() > 256 {
      raise InputError("model exceeds variable/rule limit")
    }
    let variables : Array[Variable] = []
    for i, v in vs {
      let path = "$.variables[\{i}]"
      fields(v, ["name", "domain"], path)
      let name = text_value(field(v, "name", path), path + ".name")
      let domain = array(field(v, "domain", path), path + ".domain")
      if domain.length() > 2048 {
        raise InputError(path + ": domain size exceeded")
      }
      let values : Array[Int64] = []
      for k, n in domain {
        values.push(integer(n, path + ".domain[\{k}]"))
      }
      variables.push({ name, values, })
    }
    let rules : Array[NamedRule] = []
    let size = Ref(0)
    for i, r in rs {
      let path = "$.rules[\{i}]"
      fields(r, ["id", "assert"], path)
      rules.push({
        id: text_value(field(r, "id", path), path + ".id"),
        rule: parse_rule(field(r, "assert", path), 0, size, path + ".assert"),
      })
    }
    let model : Model = { variables, rules, }
    if validate(model) is Err(e) {
      raise InputError(e)
    }
    let objective = match root {
      Object(m) =>
        match m.get("objective") {
          None => None
          Some(t) => Some(parse_term(t, 0, size, "$.objective"))
        }
      _ => None
    }
    if objective is Some(t) {
      if validate_objective(model, t) is Err(e) {
        raise InputError(e)
      }
    }
    Ok({ model, objective, })
  } catch {
    InputError(msg) => Err(msg)
    e => Err("invalid JSON: " + e.to_string())
  }
}

///|
pub fn term_to_json(t : Term) -> Json {
  match t {
    Indicator(r) => Json::array([Json::string("indicator"), rule_to_json(r)])
    Int(n) => Json::number(n.to_double())
    Var(n) => Json::string(n)
    Neg(a) => Json::array([Json::string("neg"), term_to_json(a)])
    Abs(a) => Json::array([Json::string("abs"), term_to_json(a)])
    Add(a, b) | Sub(a, b) | Mul(a, b) | Div(a, b) | Mod(a, b) => {
      let op = match t {
        Add(_, _) => "+"
        Sub(_, _) => "-"
        Mul(_, _) => "*"
        Div(_, _) => "/"
        _ => "%"
      }
      Json::array([Json::string(op), term_to_json(a), term_to_json(b)])
    }
  }
}

///|
pub fn rule_to_json(r : Rule) -> Json {
  match r {
    Holds(r) => Json::array([Json::string("holds"), rule_to_json(r)])
    Eq(a, b) | Ne(a, b) | Lt(a, b) | Le(a, b) | Gt(a, b) | Ge(a, b) => {
      let op = match r {
        Eq(_, _) => "=="
        Ne(_, _) => "!="
        Lt(_, _) => "<"
        Le(_, _) => "<="
        Gt(_, _) => ">"
        _ => ">="
      }
      Json::array([Json::string(op), term_to_json(a), term_to_json(b)])
    }
    All(rs) | Any(rs) => {
      let a = [Json::string(if r is All(_) { "all" } else { "any" })]
      for child in rs {
        a.push(rule_to_json(child))
      }
      Json::array(a)
    }
    Not(child) => Json::array([Json::string("not"), rule_to_json(child)])
    Implies(a, b) =>
      Json::array([Json::string("implies"), rule_to_json(a), rule_to_json(b)])
    AllDifferent(ts) => {
      let a = [Json::string("distinct")]
      for t in ts {
        a.push(term_to_json(t))
      }
      Json::array(a)
    }
    Count(rs, lo, hi) =>
      Json::array([
        Json::string("count"),
        Json::number(lo.to_double()),
        Json::number(hi.to_double()),
        Json::array(rs.map(rule_to_json)),
      ])
    Table(ts, rows) =>
      Json::array([
        Json::string("table"),
        Json::array(ts.map(term_to_json)),
        Json::array(
          rows.map(row => Json::array(row.map(n => Json::number(n.to_double())))),
        ),
      ])
  }
}

///|
pub fn document_to_json(doc : Document) -> Json {
  let m : Map[String, Json] = Map([])
  m["format"] = Json::string("kiln.model/1")
  m["variables"] = Json::array(
    doc.model.variables.map(v => {
      let j : Map[String, Json] = Map([])
      j["name"] = Json::string(v.name)
      j["domain"] = Json::array(v.values.map(n => Json::number(n.to_double())))
      Json::object(j)
    }),
  )
  m["rules"] = Json::array(
    doc.model.rules.map(r => {
      let j : Map[String, Json] = Map([])
      j["id"] = Json::string(r.id)
      j["assert"] = rule_to_json(r.rule)
      Json::object(j)
    }),
  )
  if doc.objective is Some(t) {
    m["objective"] = term_to_json(t)
  }
  Json::object(m)
}

///|
pub fn assignment_to_json(assignment : Map[String, Int64]) -> Json {
  let m : Map[String, Json] = Map([])
  for k, v in assignment {
    m[k] = Json::number(v.to_double())
  }
  Json::object(m)
}

///|
pub fn parse_assignment(src : String) -> Result[Map[String, Int64], String] {
  if src.length() > 1048576 {
    return Err("assignment exceeds size limit")
  }
  try {
    let j = @json.parse(
      src,
      max_nesting_depth=4,
      reject_duplicate_keys=true,
      preserve_number_repr=true,
    )
    match j {
      Object(m) => {
        if m.length() > 128 {
          raise InputError("too many assignment keys")
        }
        let env : Map[String, Int64] = Map([])
        for k, v in m {
          env[k] = integer(v, "$[" + k + "]")
        }
        Ok(env)
      }
      _ => Err("assignment must be an object")
    }
  } catch {
    InputError(msg) => Err(msg)
    e => Err("invalid JSON: " + e.to_string())
  }
}

///|
pub fn statistics_to_json(s : Statistics) -> Json {
  let j : Map[String, Json] = Map([])
  j["probes"] = Json::number(s.probes.to_double())
  j["nodes"] = Json::number(s.nodes.to_double())
  j["pruned"] = Json::number(s.pruned.to_double())
  j["solutions_seen"] = Json::number(s.solutions_seen.to_double())
  Json::object(j)
}

///|
pub fn stop_name(s : Stop) -> String {
  match s {
    Exhausted => "exhausted"
    SolutionLimit => "solution_limit"
    BudgetLimit => "budget_limit"
  }
}

///|
/// Statistics are operational measurements, not a learner-difficulty score or
/// a proof certificate. Independent verification checks only feasible witnesses.
pub fn search_to_json(result : SearchResult) -> Json {
  let j : Map[String, Json] = Map([])
  j["format"] = Json::string("kiln.search/1")
  j["complete"] = Json::boolean(result.stop == Exhausted)
  j["stop"] = Json::string(stop_name(result.stop))
  j["solutions"] = Json::array(result.solutions.map(assignment_to_json))
  j["statistics"] = statistics_to_json(result.stats)
  j["classification"] = Json::string(
    if result.solutions.length() > 1 {
      "multiple"
    } else if result.stop != Exhausted {
      "unknown"
    } else if result.solutions.is_empty() {
      "unsatisfiable"
    } else {
      "unique"
    },
  )
  Json::object(j)
}

///|
/// Keep all other rules as preconditions and search for a violation of this rule.
pub fn negate_rule(model : Model, rule_id : String) -> Result[Model, String] {
  if validate(model) is Err(e) {
    return Err(e)
  }
  let mut found = false
  let rules = model.rules.map(r => {
    if r.id == rule_id {
      found = true
      NamedRule::{ id: r.id, rule: Not(r.rule), }
    } else {
      r
    }
  })
  if found {
    Ok({ variables: model.variables, rules, })
  } else {
    Err("unknown rule id: " + rule_id)
  }
}

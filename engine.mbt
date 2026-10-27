///|
/// The generated artifact: one problem, its answers, why it is rated the way it
/// is, and the certificate that lets anyone re-check it.
pub(all) struct Item {
  schema_name : String
  question : String
  answers : Array[Rat]
  level : Int32
  reasons : Array[String]
  fingerprint : String
  certificate : Certificate
  robust : Bool
  signature : String
  ///
  /// Structural tags used by the assembler to keep a paper diverse, e.g. two
  /// items in a row that both have a zero root.
  tags : Array[String]
}

///|
pub fn Item::answer_text(self : Item) -> String {
  let subs = ["₁", "₂", "₃", "₄"]
  let sb = StringBuilder()
  if self.answers.length() == 1 {
    sb.write_string("x = \{self.answers[0].to_string()}")
  } else {
    for i, r in self.answers {
      if i > 0 {
        sb.write_string("，")
      }
      sb.write_string("x")
      if i < subs.length() {
        sb.write_string(subs[i])
      }
      sb.write_string(" = \{r.to_string()}")
    }
  }
  sb.to_string()
}

///|
pub fn Item::level_label(self : Item) -> String {
  "L\{self.level}"
}

///|
pub fn Item::reasons_text(self : Item) -> String {
  if self.reasons.length() == 0 {
    "基础"
  } else {
    let sb = StringBuilder()
    for i, r in self.reasons {
      if i > 0 {
        sb.write_string("、")
      }
      sb.write_string(r)
    }
    sb.to_string()
  }
}

///|
/// A generation run. The counters are part of the product: "1083 candidates,
/// 0 rejected, 41 duplicates" is a much better claim than "it works".
pub(all) struct Pool {
  items : Array[Item]
  attempted : Int32
  rejected : Int32
  duplicates : Int32
  rejects : Array[String]
}

///|
pub fn Pool::size(self : Pool) -> Int32 {
  self.items.length()
}

///|
pub fn Pool::count_at(self : Pool, level : Int32) -> Int32 {
  let mut n = 0
  for it in self.items {
    if it.level == level {
      n = n + 1
    }
  }
  n
}

///|
pub fn Pool::level_histogram(self : Pool) -> String {
  let sb = StringBuilder()
  for level in 1..<=5 {
    if level > 1 {
      sb.write_string("  ")
    }
    sb.write_string("L\{level}:\{self.count_at(level)}")
  }
  sb.to_string()
}

///|
priv struct Step {
  name : String
  domain : (Int32, Int32)?
  expr : Expr?
}

///|
fn build_steps(schema : Schema) -> Array[Step] {
  let out : Array[Step] = []
  for v in schema.answers {
    out.push({ name: v.name, domain: v.domain, expr: v.expr, })
  }
  for v in schema.params {
    out.push({ name: v.name, domain: v.domain, expr: v.expr, })
  }
  out
}

///|
/// Bind the first `upto` steps into an environment.
fn env_of(
  steps : Array[Step],
  values : Array[Rat],
  upto : Int32,
) -> Map[String, Rat] {
  let env : Map[String, Rat] = Map([])
  for i in 0..<upto {
    env[steps[i].name] = values[i]
  }
  env
}

///|
/// Depth-first enumeration of the declared product space.
///
/// Enumerated variables walk their interval in ascending order and derived
/// variables are evaluated exactly where they are declared, so a later
/// expression can depend on an earlier derived one. Undefined intermediate
/// values (division by zero) prune the branch instead of raising.
fn walk(
  steps : Array[Step],
  idx : Int32,
  values : Array[Rat],
  out : Array[Array[Rat]],
) -> Unit {
  if idx == steps.length() {
    out.push(values.copy())
    return
  }
  let step = steps[idx]
  match step.domain {
    Some(bounds) => {
      let (lo, hi) = bounds
      let mut v = lo
      while v <= hi {
        values[idx] = rat_int(v.to_int64())
        walk(steps, idx + 1, values, out)
        v = v + 1
      }
    }
    None =>
      match step.expr {
        Some(e) => {
          let env = env_of(steps, values, idx)
          match e.eval(env) {
            Some(v) => {
              values[idx] = v
              walk(steps, idx + 1, values, out)
            }
            None => ()
          }
        }
        None => ()
      }
  }
}

///|
fn requirements_hold(
  schema : Schema,
  steps : Array[Step],
  values : Array[Rat],
) -> Bool {
  let env = env_of(steps, values, steps.length())
  let mut ok = true
  for r in schema.requires {
    match r.check(env) {
      Some(true) => ()
      _ => ok = false
    }
  }
  ok
}

///|
fn make_item(schema : Schema, env : Map[String, Rat]) -> Result[Item, String] {
  match schema.family {
    FQuadratic => build_quadratic(schema, env)
  }
}

///|
/// Generate a pool of verified items.
///
/// `limit = 0` means "no limit". Items are produced in a deterministic order,
/// and the first occurrence of a fingerprint wins, so the same schema always
/// yields the same pool.
pub fn generate(schema : Schema, limit : Int32) -> Pool {
  let steps = build_steps(schema)
  let seed_values : Array[Rat] = []
  for _ in 0..<steps.length() {
    seed_values.push(rat_zero())
  }
  let raw : Array[Array[Rat]] = []
  walk(steps, 0, seed_values, raw)
  let items : Array[Item] = []
  let seen : Array[String] = []
  let rejects : Array[String] = []
  let mut attempted = 0
  let mut rejected = 0
  let mut duplicates = 0
  for values in raw {
    if limit > 0 && items.length() >= limit {
      break
    }
    if !requirements_hold(schema, steps, values) {
      continue
    }
    attempted = attempted + 1
    let env = env_of(steps, values, steps.length())
    match make_item(schema, env) {
      Ok(item) =>
        if contains_str(seen, item.fingerprint) {
          duplicates = duplicates + 1
        } else {
          seen.push(item.fingerprint)
          items.push(item)
        }
      Err(reason) => {
        rejected = rejected + 1
        rejects.push(reason)
      }
    }
  }
  { items, attempted, rejected, duplicates, rejects, }
}

///|
test "generation only emits well-posed items and dedupes by fingerprint" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(e) => abort("schema error: \{e}")
  }
  let pool = generate(schema, 0)
  inspect(pool.size() > 0, content="true")
  inspect(pool.rejected, content="0")
  // 19 * 19 root pairs, 171 of them satisfy r1 < r2.
  inspect(pool.attempted, content="171")
  // With a fixed leading coefficient no two distinct parameter tuples describe
  // the same equation, so nothing collapses.
  inspect(pool.duplicates, content="0")
}

///|
test "every generated item re-verifies independently" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(e) => abort("schema error: \{e}")
  }
  let pool = generate(schema, 120)
  let mut bad = 0
  for item in pool.items {
    let p = Poly::new([
      item.certificate.c,
      item.certificate.b,
      item.certificate.a,
    ])
    let (v, _) = verify_quadratic(p, item.answers)
    if !v.is_well_posed() {
      bad = bad + 1
    }
  }
  inspect(bad, content="0")
}

///|
/// A schema that *does* produce scale duplicates, to prove the fingerprint
/// collapses them instead of inflating the pool.
const DUP_SCHEMA : String =
  #|schema "quadratic_dup"
  #|family quadratic
  #|answer {
  #|  r1: int in [-4, 4]
  #|  r2: int in [-4, 4]
  #|}
  #|param {
  #|  a: int in [1, 3]
  #|  b: -(a * (r1 + r2))
  #|  c: a * r1 * r2
  #|}
  #|require {
  #|  r1 < r2
  #|}
  #|ask "解方程 {poly} = 0"
  #|

///|
test "scaled duplicates collapse into one item" {
  let schema = match load_schema(DUP_SCHEMA) {
    Ok(s) => s
    Err(e) => abort("schema error: \{e}")
  }
  let pool = generate(schema, 0)
  inspect(pool.attempted > 0, content="true")
  inspect(pool.duplicates > 0, content="true")
  // Every surviving item is the primitive representative of its class.
  let p = Poly::new([
    pool.items[0].certificate.c,
    pool.items[0].certificate.b,
    pool.items[0].certificate.a,
  ])
  inspect(p.leading().to_string(), content="1")
}

///|
test "generation is reproducible" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(_) => abort("schema error")
  }
  let a = generate(schema, 50)
  let b = generate(schema, 50)
  inspect(a.size(), content="50")
  let mut same = true
  for i in 0..<a.size() {
    if a.items[i].fingerprint != b.items[i].fingerprint {
      same = false
    }
  }
  inspect(same, content="true")
}

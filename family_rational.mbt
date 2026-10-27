///|
/// Rational family: `(x + p) / (x - k) = q`.
///
/// This family exists to show what the well-posedness gate is really for. A
/// rational equation has an *excluded value* — the zero of its denominator. If
/// the solution produced by clearing denominators happens to be that excluded
/// value, the equation has **no** solution, yet the algebra "succeeds". That is
/// the classic extraneous root, and it is exactly the failure a generator
/// without a verifier ships to students.
///
/// Construction goes forward from the intended root; verification clears
/// denominators and then checks the excluded value. Different paths, as always.

///|
pub fn verify_rational(
  num : Poly,
  den : Poly,
  rhs : Rat,
  declared : Array[Rat],
) -> (Verdict, Certificate) {
  // Cross-multiply: num - rhs * den = 0.
  let cleared = num.sub(den.scale(rhs))
  let robust = rational_robust(num, den, rhs)
  if cleared.is_zero() {
    return (Identity, rational_certificate(num, den, rhs, cleared, robust))
  }
  if cleared.degree() != 1 {
    return (NotLinear, rational_certificate(num, den, rhs, cleared, robust))
  }
  let b = cleared.coeff(1)
  let c = cleared.coeff(0)
  let x = c.neg().div(b)
  let at_den = den.eval(x)
  let cert = rational_certificate(num, den, rhs, cleared, robust)
  if at_den.is_zero() {
    return (ExtraneousRoot, cert)
  }
  if declared.length() != 1 {
    return (
      AnswerMismatch("declared \{declared.length()} roots, equation has 1"),
      cert,
    )
  }
  if !declared[0].equal(x) {
    return (
      AnswerMismatch(
        "equation gives \{x.to_string()} but declared \{declared[0].to_string()}",
      ),
      cert,
    )
  }
  (WellPosed, cert)
}

///|
fn rational_certificate(
  num : Poly,
  den : Poly,
  rhs : Rat,
  cleared : Poly,
  robust : Bool,
) -> Certificate {
  let fields : Array[(String, String)] = []
  fields.push(("分子", num.to_string("x")))
  fields.push(("分母", den.to_string("x")))
  fields.push(("右端", rhs.to_string()))
  fields.push(("去分母后", cleared.to_string("x")))
  let excluded = den
  // The excluded value is the root of a linear denominator.
  if excluded.degree() == 1 {
    let k = excluded.coeff(0).neg().div(excluded.coeff(1))
    fields.push(("分母零点", k.to_string()))
  }
  fields.push(("robust", if robust { "true" } else { "false" }))
  {
    fields,
    payload: [num.coeff(0), num.coeff(1), den.coeff(0), den.coeff(1), rhs],
    robust,
  }
}

///|
/// Fragile here means: the solution sits one integer step away from the excluded
/// value. Such an item is correct but a single typo turns it into a problem with
/// no solution at all.
fn rational_robust(num : Poly, den : Poly, rhs : Rat) -> Bool {
  let cleared = num.sub(den.scale(rhs))
  if cleared.degree() != 1 {
    return false
  }
  let x = cleared.coeff(0).neg().div(cleared.coeff(1))
  let k = excluded_value(den)
  match k {
    None => false
    Some(kv) => {
      let gap = x.sub(kv).abs()
      gap.compare(rat_one()) > 0
    }
  }
}

///|
fn excluded_value(den : Poly) -> Rat? {
  if den.degree() == 1 && !den.coeff(1).is_zero() {
    Some(den.coeff(0).neg().div(den.coeff(1)))
  } else {
    None
  }
}

///|
/// Build one rational item from a parameter environment.
///
/// Declared parameters: `p` (numerator offset), `k` (denominator offset),
/// `q` (right-hand side), and the answer variable (the intended root).
pub fn build_rational(
  schema : Schema,
  env : Map[String, Rat],
) -> Result[Item, String] {
  let p = get_rat(env, "p")
  let k = get_rat(env, "k")
  let q = get_rat(env, "q")
  let r = get_rat(env, schema.answers[0].name)
  let num = Poly::new([p, rat_one()])
  let den = Poly::new([k.neg(), rat_one()])
  let (verdict, cert) = verify_rational(num, den, q, [r])
  if !verdict.is_well_posed() {
    return Err(verdict.to_string())
  }
  let filled_num = num.to_string("x")
  let filled_den = den.to_string("x")
  let question = replace_all(
    replace_all(
      replace_all(schema.ask, "{num}", filled_num),
      "{den}",
      filled_den,
    ),
    "{q}",
    q.to_string(),
  )
  let (level, reasons) = classify_rational(r, k, q)
  // The fingerprint is the *visible* equation, not its cross-multiplied form:
  // `(x-8)/(x-4)=2` and `(x-12)/(x-4)=3` share a solution but are different
  // problems to a student, so they must not collapse.
  let fingerprint = num.canonical_key() +
    "/" +
    den.canonical_key() +
    "=" +
    q.to_string()
  Ok({
    schema_name: schema.name,
    question,
    answers: [r],
    level,
    reasons,
    fingerprint,
    certificate: cert,
    robust: cert.robust,
    signature: "p=\{p.to_string()}, k=\{k.to_string()}, q=\{q.to_string()}",
    family: FRational,
    tags: rational_tags(r, k),
  })
}

///|
fn rational_tags(r : Rat, k : Rat) -> Array[String] {
  let tags : Array[String] = []
  if k.is_negative() {
    tags.push("negative-excluded")
  }
  if r.sub(k).abs().equal(rat_one()) {
    tags.push("near-extraneous")
  }
  if r.sign() < 0 {
    tags.push("negative-root")
  }
  tags
}

///|
pub fn classify_rational(r : Rat, k : Rat, q : Rat) -> (Int32, Array[String]) {
  let reasons : Array[String] = []
  let mut score = 2
  if !q.equal(rat_int(2L)) {
    score = score + 1
    reasons.push("右端不是 2")
  }
  if r.sign() < 0 {
    score = score + 1
    reasons.push("解为负数")
  }
  if k.is_negative() {
    score = score + 1
    reasons.push("分母零点为负")
  }
  if r.abs().compare(rat_int(5L)) > 0 {
    score = score + 1
    reasons.push("解绝对值较大")
  }
  let mut level = score
  if level < 1 {
    level = 1
  }
  if level > 5 {
    level = 5
  }
  (level, reasons)
}

///|
test "rational verifier accepts a clean equation" {
  // (x - 1) / (x + 3) = 2  →  x = -7
  let num = Poly::new([rat_int(-1L), rat_one()])
  let den = Poly::new([rat_int(3L), rat_one()])
  let (v, _) = verify_rational(num, den, rat_int(2L), [rat_int(-7L)])
  inspect(v.is_well_posed(), content="true")
}

///|
test "rational verifier catches an extraneous root" {
  // (x - 3) / (x - 3) = 2 clears to x - 3 = 2x - 6 → x = 3, which is excluded.
  let num = Poly::new([rat_int(-3L), rat_one()])
  let den = Poly::new([rat_int(-3L), rat_one()])
  let (v, _) = verify_rational(num, den, rat_int(2L), [rat_int(3L)])
  inspect(v.to_string(), content="extraneous-root")
}

///|
test "rational verifier catches a wrong declared root" {
  let num = Poly::new([rat_int(-1L), rat_one()])
  let den = Poly::new([rat_int(3L), rat_one()])
  let (v, _) = verify_rational(num, den, rat_int(2L), [rat_int(-6L)])
  inspect(v.to_string().contains("answer-mismatch"), content="true")
}

///|
const RATIONAL_SCHEMA : String =
  #|schema "r"
  #|family rational
  #|answer {
  #|  r: int in [-6, 6]
  #|}
  #|param {
  #|  k: int in [-6, 6]
  #|  q: int in [2, 3]
  #|  p: q * (r - k) - r
  #|}
  #|require {
  #|  r != k
  #|}
  #|ask "解方程 ({num})/({den}) = {q}"
  #|

///|
test "rational pool is non-empty and every item re-verifies" {
  let schema = match load_schema(RATIONAL_SCHEMA) {
    Ok(s) => s
    Err(e) => abort("schema error: \{e}")
  }
  let pool = generate(schema, 0)
  inspect(pool.size() > 0, content="true")
  inspect(pool.rejected, content="0")
  let mut bad = 0
  for item in pool.items {
    let y = item.certificate.payload
    let num = Poly::new([y[0], y[1]])
    let den = Poly::new([y[2], y[3]])
    let (v, _) = verify_rational(num, den, y[4], item.answers)
    if !v.is_well_posed() {
      bad = bad + 1
    }
  }
  inspect(bad, content="0")
}

///|
test "dropping the guard lets the extraneous-root gate fire" {
  let loose = replace_all(RATIONAL_SCHEMA, "  r != k\n", "  r == r\n")
  let schema = match load_schema(loose) {
    Ok(s) => s
    Err(e) => abort("schema error: \{e}")
  }
  let pool = generate(schema, 0)
  inspect(pool.rejected > 0, content="true")
  let mut saw_extraneous = false
  for reason in pool.rejects {
    if reason == "extraneous-root" {
      saw_extraneous = true
    }
  }
  inspect(saw_extraneous, content="true")
}

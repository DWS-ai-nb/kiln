///|
/// Independent verification of a quadratic item.
///
/// This file deliberately shares **no** derivation path with the generator.
/// The generator goes forward: pick roots, build coefficients by Vieta.
/// The verifier goes backward: take coefficients, compute the discriminant, take
/// square roots, compare solution sets. A single sign slip in either path shows
/// up as a disagreement instead of silently cancelling out.
pub enum Verdict {
  WellPosed
  NotQuadratic
  NoRealRoots
  DoubleRoot
  IrrationalRoots
  ExtraneousRoot
  Identity
  NotLinear
  AnswerMismatch(String)
}

///|
pub fn Verdict::to_string(self : Verdict) -> String {
  match self {
    WellPosed => "well-posed"
    NotQuadratic => "not-quadratic"
    NoRealRoots => "no-real-roots"
    DoubleRoot => "double-root"
    IrrationalRoots => "irrational-roots"
    ExtraneousRoot => "extraneous-root"
    Identity => "identity"
    NotLinear => "not-linear"
    AnswerMismatch(d) => "answer-mismatch: \{d}"
  }
}

///|
pub fn Verdict::is_well_posed(self : Verdict) -> Bool {
  match self {
    WellPosed => true
    _ => false
  }
}

///|
/// What a third party needs to re-check an item without trusting the generator.
///
/// `fields` is human-readable evidence; `payload` is the raw data the verifier
/// consumes, in family-defined order. Keeping the payload numeric (and exact)
/// is what makes independent re-verification possible from the outside.
pub(all) struct Certificate {
  fields : Array[(String, String)]
  payload : Array[Rat]
  robust : Bool
}

///|
pub fn Certificate::to_lines(self : Certificate) -> Array[String] {
  let out : Array[String] = []
  for entry in self.fields {
    let (k, v) = entry
    out.push("\{k} = \{v}")
  }
  out
}

///|
pub fn Certificate::field(self : Certificate, key : String) -> String? {
  let mut found : String? = None
  for entry in self.fields {
    let (k, v) = entry
    if k == key {
      found = Some(v)
    }
  }
  found
}

///|
fn sort_rats(xs : Array[Rat]) -> Array[Rat] {
  let out = xs.copy()
  let mut i = 1
  while i < out.length() {
    let key = out[i]
    let mut j = i - 1
    while j >= 0 && out[j].compare(key) > 0 {
      out[j + 1] = out[j]
      j = j - 1
    }
    out[j + 1] = key
    i = i + 1
  }
  out
}

///|
fn same_multiset(xs : Array[Rat], ys : Array[Rat]) -> Bool {
  if xs.length() != ys.length() {
    return false
  }
  let a = sort_rats(xs)
  let b = sort_rats(ys)
  let mut ok = true
  for i, x in a {
    if !x.equal(b[i]) {
      ok = false
    }
  }
  ok
}

///|
fn discriminant(a : Rat, b : Rat, c : Rat) -> Rat {
  b.mul(b).sub(rat_int(4L).mul(a).mul(c))
}

///|
/// Robustness is a *soft* signal, not a gate.
///
/// A problem is fragile when nudging a single coefficient by one flips it from
/// "two real roots" to "no real roots" or "a double root". Such a problem is
/// still correct today, but it is a knife-edge: any reprint or typo changes the
/// answer. We record it, and the paper assembler prefers robust items when it
/// has a choice. Perturbing `a` to zero is skipped — that changes the problem
/// class, not the conditioning.
fn is_robust(a : Rat, b : Rat, c : Rat) -> Bool {
  let deltas = [
    (1L, 0L, 0L),
    (-1L, 0L, 0L),
    (0L, 1L, 0L),
    (0L, -1L, 0L),
    (0L, 0L, 1L),
    (0L, 0L, -1L),
  ]
  let mut ok = true
  for d in deltas {
    let (da, db, dc) = d
    let a2 = a.add(rat_int(da))
    let b2 = b.add(rat_int(db))
    let c2 = c.add(rat_int(dc))
    if a2.is_zero() {
      continue
    }
    if discriminant(a2, b2, c2).sign() <= 0 {
      ok = false
    }
  }
  ok
}

///|
fn quadratic_certificate(
  a : Rat,
  b : Rat,
  c : Rat,
  d : Rat,
  sqrt_d : Rat?,
  roots : Array[Rat],
  robust : Bool,
) -> Certificate {
  let fields : Array[(String, String)] = []
  fields.push(("a", a.to_string()))
  fields.push(("b", b.to_string()))
  fields.push(("c", c.to_string()))
  fields.push(("Δ = b² - 4ac", d.to_string()))
  match sqrt_d {
    Some(s) => fields.push(("√Δ", s.to_string()))
    None => fields.push(("√Δ", "无精确值"))
  }
  let sb = StringBuilder()
  for i, r in roots {
    if i > 0 {
      sb.write_string(", ")
    }
    sb.write_string(r.to_string())
  }
  fields.push(("求根公式给出", sb.to_string()))
  fields.push(("robust", if robust { "true" } else { "false" }))
  { fields, payload: [a, b, c], robust, }
}

///|
/// Verify that `p(x) = 0` has exactly the declared solution set, with two
/// distinct rational roots.
pub fn verify_quadratic(
  p : Poly,
  declared : Array[Rat],
) -> (Verdict, Certificate) {
  let a = p.coeff(2)
  let b = p.coeff(1)
  let c = p.coeff(0)
  let d = discriminant(a, b, c)
  let robust = is_robust(a, b, c)
  if a.is_zero() || p.degree() != 2 {
    return (NotQuadratic, quadratic_certificate(a, b, c, d, None, [], robust))
  }
  if d.sign() < 0 {
    return (NoRealRoots, quadratic_certificate(a, b, c, d, None, [], robust))
  }
  if d.is_zero() {
    let r = b.neg().div(a.mul(rat_int(2L)))
    return (
      DoubleRoot,
      quadratic_certificate(a, b, c, d, Some(rat_zero()), [r], robust),
    )
  }
  match d.sqrt_exact() {
    None =>
      (IrrationalRoots, quadratic_certificate(a, b, c, d, None, [], robust))
    Some(s) => {
      let two_a = a.mul(rat_int(2L))
      let r1 = b.neg().add(s).div(two_a)
      let r2 = b.neg().sub(s).div(two_a)
      let cert = quadratic_certificate(a, b, c, d, Some(s), [r1, r2], robust)
      if r1.equal(r2) {
        return (DoubleRoot, cert)
      }
      if declared.length() != 2 {
        return (
          AnswerMismatch("declared \{declared.length()} roots, formula gives 2"),
          cert,
        )
      }
      if !same_multiset([r1, r2], declared) {
        let got = StringBuilder()
        for i, r in sort_rats([r1, r2]) {
          if i > 0 {
            got.write_string(", ")
          }
          got.write_string(r.to_string())
        }
        let want = StringBuilder()
        for i, r in sort_rats(declared) {
          if i > 0 {
            want.write_string(", ")
          }
          want.write_string(r.to_string())
        }
        return (
          AnswerMismatch(
            "formula gives {\{got.to_string()}} but declared {\{want.to_string()}}",
          ),
          cert,
        )
      }
      (WellPosed, cert)
    }
  }
}

///|
test "verifier accepts a well-posed quadratic" {
  // x² - 5x + 6 = 0
  let p = Poly::new([rat_int(6L), rat_int(-5L), rat_one()])
  let (v, cert) = verify_quadratic(p, [rat_int(2L), rat_int(3L)])
  inspect(v.is_well_posed(), content="true")
  debug_inspect(cert.field("Δ = b² - 4ac"), content="Some(\"1\")")
  inspect(cert.robust, content="false")
}

///|
test "verifier catches a wrong declared answer" {
  let p = Poly::new([rat_int(6L), rat_int(-5L), rat_one()])
  let (v, _) = verify_quadratic(p, [rat_int(2L), rat_int(4L)])
  inspect(v.is_well_posed(), content="false")
  inspect(v.to_string().contains("answer-mismatch"), content="true")
}

///|
test "verifier rejects a negative discriminant" {
  let p = Poly::new([rat_int(1L), rat_zero(), rat_one()])
  let (v, _) = verify_quadratic(p, [rat_int(1L), rat_int(-1L)])
  inspect(v.to_string(), content="no-real-roots")
}

///|
test "verifier rejects a double root" {
  // x² - 2x + 1 = 0
  let p = Poly::new([rat_one(), rat_int(-2L), rat_one()])
  let (v, _) = verify_quadratic(p, [rat_one(), rat_one()])
  inspect(v.to_string(), content="double-root")
}

///|
test "verifier rejects irrational roots" {
  // x² - 2 = 0
  let p = Poly::new([rat_int(-2L), rat_zero(), rat_one()])
  let (v, _) = verify_quadratic(p, [rat_int(1L), rat_int(-1L)])
  inspect(v.to_string(), content="irrational-roots")
}

///|
test "certificate payload is enough to rebuild the polynomial" {
  let p = Poly::new([rat_int(6L), rat_int(-5L), rat_one()])
  let (_, cert) = verify_quadratic(p, [rat_int(2L), rat_int(3L)])
  inspect(cert.payload.length(), content="3")
  let rebuilt = Poly::new([cert.payload[2], cert.payload[1], cert.payload[0]])
  inspect(rebuilt.canonical_key(), content="1,-5,6")
}

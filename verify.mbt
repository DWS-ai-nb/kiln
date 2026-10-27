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
/// Everything a third party needs to re-check the item without trusting the
/// generator: the coefficients, the discriminant, its exact square root, and
/// the roots the quadratic formula produces.
pub(all) struct Certificate {
  a : Rat
  b : Rat
  c : Rat
  discriminant : Rat
  sqrt_discriminant : Rat?
  formula_roots : Array[Rat]
  robust : Bool
}

///|
pub fn Certificate::to_lines(self : Certificate) -> Array[String] {
  let lines : Array[String] = []
  lines.push("a = \{self.a.to_string()}")
  lines.push("b = \{self.b.to_string()}")
  lines.push("c = \{self.c.to_string()}")
  lines.push("Δ = b² - 4ac = \{self.discriminant.to_string()}")
  match self.sqrt_discriminant {
    Some(r) => lines.push("√Δ = \{r.to_string()}")
    None => lines.push("√Δ has no exact value")
  }
  let rs = StringBuilder()
  for i, r in self.formula_roots {
    if i > 0 {
      rs.write_string(", ")
    }
    rs.write_string(r.to_string())
  }
  lines.push("roots = \{rs.to_string()}")
  lines.push("robust = \{self.robust}")
  lines
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
    return (
      NotQuadratic,
      {
        a,
        b,
        c,
        discriminant: d,
        sqrt_discriminant: None,
        formula_roots: [],
        robust,
      },
    )
  }
  if d.sign() < 0 {
    return (
      NoRealRoots,
      {
        a,
        b,
        c,
        discriminant: d,
        sqrt_discriminant: None,
        formula_roots: [],
        robust,
      },
    )
  }
  if d.is_zero() {
    let r = b.neg().div(a.mul(rat_int(2L)))
    return (
      DoubleRoot,
      {
        a,
        b,
        c,
        discriminant: d,
        sqrt_discriminant: Some(rat_zero()),
        formula_roots: [r],
        robust,
      },
    )
  }
  match d.sqrt_exact() {
    None =>
      (
        IrrationalRoots,
        {
          a,
          b,
          c,
          discriminant: d,
          sqrt_discriminant: None,
          formula_roots: [],
          robust,
        },
      )
    Some(s) => {
      let two_a = a.mul(rat_int(2L))
      let r1 = b.neg().add(s).div(two_a)
      let r2 = b.neg().sub(s).div(two_a)
      let cert = {
        a,
        b,
        c,
        discriminant: d,
        sqrt_discriminant: Some(s),
        formula_roots: [r1, r2],
        robust,
      }
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
  inspect(cert.discriminant.to_string(), content="1")
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

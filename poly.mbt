///|
/// Univariate polynomials with exact rational coefficients.
///
/// `coeffs[i]` is the coefficient of `x^i`. Trailing zero coefficients are
/// stripped by every constructor, so two polynomials are structurally equal iff
/// their coefficient arrays are equal.
///
/// Scope note: the engine is deliberately univariate. Multivariate symbolic
/// algebra already exists in the MoonBit ecosystem (`maxima`, `symbit`); this
/// project is about *constructing well-posed instances*, not about being a CAS.
pub struct Poly {
  coeffs : Array[Rat]
}

///|
pub fn Poly::new(coeffs : Array[Rat]) -> Poly {
  let trimmed = []
  let mut last = 0
  for i, c in coeffs {
    if !c.is_zero() {
      last = i + 1
    }
  }
  for i in 0..<last {
    trimmed.push(coeffs[i])
  }
  { coeffs: trimmed, }
}

///|
pub fn Poly::zero() -> Poly {
  { coeffs: [], }
}

///|
pub fn Poly::constant(c : Rat) -> Poly {
  Poly::new([c])
}

///|
/// The polynomial `x`.
pub fn Poly::x() -> Poly {
  Poly::new([rat_zero(), rat_one()])
}

///|
pub fn Poly::degree(self : Poly) -> Int32 {
  self.coeffs.length() - 1
}

///|
pub fn Poly::is_zero(self : Poly) -> Bool {
  self.coeffs.length() == 0
}

///|
pub fn Poly::coeff(self : Poly, i : Int32) -> Rat {
  if i < 0 || i >= self.coeffs.length() {
    rat_zero()
  } else {
    self.coeffs[i]
  }
}

///|
pub fn Poly::leading(self : Poly) -> Rat {
  self.coeff(self.degree())
}

///|
pub fn Poly::neg(self : Poly) -> Poly {
  Poly::new(self.coeffs.map(fn(c) { c.neg() }))
}

///|
pub fn Poly::add(self : Poly, other : Poly) -> Poly {
  let n = if self.coeffs.length() > other.coeffs.length() {
    self.coeffs.length()
  } else {
    other.coeffs.length()
  }
  let out = []
  for i in 0..<n {
    out.push(self.coeff(i).add(other.coeff(i)))
  }
  Poly::new(out)
}

///|
pub fn Poly::sub(self : Poly, other : Poly) -> Poly {
  self.add(other.neg())
}

///|
pub fn Poly::scale(self : Poly, k : Rat) -> Poly {
  Poly::new(self.coeffs.map(fn(c) { c.mul(k) }))
}

///|
pub fn Poly::mul(self : Poly, other : Poly) -> Poly {
  if self.is_zero() || other.is_zero() {
    return Poly::zero()
  }
  let n = self.coeffs.length() + other.coeffs.length() - 1
  let out = []
  for _ in 0..<n {
    out.push(rat_zero())
  }
  for i, a in self.coeffs {
    for j, b in other.coeffs {
      out[i + j] = out[i + j].add(a.mul(b))
    }
  }
  Poly::new(out)
}

///|
pub fn Poly::pow(self : Poly, exp : Int32) -> Poly {
  let mut result = Poly::constant(rat_one())
  let mut i = 0
  while i < exp {
    result = result.mul(self)
    i = i + 1
  }
  result
}

///|
/// Evaluate the polynomial at an exact point (Horner, exact arithmetic).
pub fn Poly::eval(self : Poly, at : Rat) -> Rat {
  let mut acc = rat_zero()
  let mut i = self.coeffs.length() - 1
  while i >= 0 {
    acc = acc.mul(at).add(self.coeff(i))
    i = i - 1
  }
  acc
}

///|
fn superscript(n : Int32) -> String {
  if n < 0 || n > 9 {
    return "^\{n}"
  }
  let digits = [
    "⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹",
  ]
  digits[n]
}

///|
/// Human-readable form such as `2x² - 5x + 6`.
pub fn Poly::to_string(self : Poly, v : String) -> String {
  if self.is_zero() {
    return "0"
  }
  let sb = StringBuilder()
  let mut first = true
  let mut i = self.coeffs.length() - 1
  while i >= 0 {
    let c = self.coeff(i)
    if !c.is_zero() {
      let neg = c.is_negative()
      let magnitude = c.abs()
      if first {
        if neg {
          sb.write_string("-")
        }
      } else if neg {
        sb.write_string(" - ")
      } else {
        sb.write_string(" + ")
      }
      let show_coeff = if i == 0 { true } else { !magnitude.equal(rat_one()) }
      if show_coeff {
        sb.write_string(magnitude.to_string())
      }
      if i >= 1 {
        sb.write_string(v)
        if i > 1 {
          sb.write_string(superscript(i))
        }
      }
      first = false
    }
    i = i - 1
  }
  sb.to_string()
}

///|
/// Canonical key of the *equation* `P(x) = 0`, invariant under scaling.
///
/// Scaling is a genuine equivalence for equations: `2x²-10x+12=0` and
/// `x²-5x+6=0` have the same solution set. Coercing coefficients to primitive
/// integers with a positive leading coefficient therefore merges exactly the
/// polynomials that describe the same equation — and nothing else.
///
/// The map is sound (equal keys ⇒ same equation) and, for univariate
/// polynomials, also complete (same equation over ℚ ⇒ equal keys).
pub fn Poly::canonical_key(self : Poly) -> String {
  if self.is_zero() {
    return "0"
  }
  // Step 1: clear denominators with the LCM of all denominators.
  let mut lcm : Int64 = 1L
  for c in self.coeffs {
    let d = c.den()
    lcm = lcm / gcd64(lcm, d) * d
  }
  let ints = self.coeffs.map(fn(c) { c.num() * (lcm / c.den()) })
  // Step 2: divide out the content.
  let mut g : Int64 = 0L
  for v in ints {
    g = gcd64(g, v)
  }
  if g == 0L {
    g = 1L
  }
  let primitive = ints.map(fn(v) { v / g })
  // Step 3: force a positive leading coefficient.
  let lead = primitive[primitive.length() - 1]
  let sign : Int64 = if lead < 0L { -1L } else { 1L }
  let sb = StringBuilder()
  let mut i = primitive.length() - 1
  while i >= 0 {
    if i < primitive.length() - 1 {
      sb.write_string(",")
    }
    sb.write_string((primitive[i] * sign).to_string())
    i = i - 1
  }
  sb.to_string()
}

///|
test "poly constructor strips trailing zeros" {
  let p = Poly::new([rat_one(), rat_zero(), rat_zero()])
  inspect(p.degree(), content="0")
  inspect(p.is_zero(), content="false")
  inspect(Poly::zero().is_zero(), content="true")
}

///|
test "poly arithmetic matches hand expansion" {
  // (x - 1)(x - 2) = x² - 3x + 2
  let p = Poly::new([rat_int(-1L), rat_one()]).mul(
    Poly::new([rat_int(-2L), rat_one()]),
  )
  inspect(p.to_string("x"), content="x² - 3x + 2")
  inspect(p.eval(rat_int(3L)).to_string(), content="2")
}

///|
test "canonical key merges scaled equations" {
  let a = Poly::new([rat_int(12L), rat_int(-10L), rat_int(2L)])
  let b = Poly::new([rat_int(6L), rat_int(-5L), rat_one()])
  let c = Poly::new([rat_int(-6L), rat_int(5L), rat_int(-1L)])
  inspect(a.canonical_key() == b.canonical_key(), content="true")
  inspect(b.canonical_key() == c.canonical_key(), content="true")
  inspect(a.canonical_key(), content="1,-5,6")
}

///|
test "canonical key separates different equations" {
  let a = Poly::new([rat_int(6L), rat_int(-5L), rat_one()])
  let b = Poly::new([rat_int(2L), rat_int(-3L), rat_one()])
  inspect(a.canonical_key() == b.canonical_key(), content="false")
}

///|
test "canonical key clears rational coefficients" {
  let a = Poly::new([rat_int(1L), rat(1L, 2L)])
  inspect(a.canonical_key(), content="1,2")
}

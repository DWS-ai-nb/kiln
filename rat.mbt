///|
/// Exact rational arithmetic.
///
/// Invariants maintained by every constructor in this file:
///   * `den > 0`
///   * `gcd(|num|, den) == 1`
///   * zero is always represented as `0/1`
///
/// The engine never uses `Double`. Every quantity that ends up on a worksheet
/// is an exact rational, which is what makes byte-identical output across the
/// wasm-gc / js / native backends possible.
pub struct Rat {
  num : Int64
  den : Int64
}

///|
fn abs64(x : Int64) -> Int64 {
  if x < 0L {
    -x
  } else {
    x
  }
}

///|
fn gcd64(a : Int64, b : Int64) -> Int64 {
  let mut x = abs64(a)
  let mut y = abs64(b)
  while y != 0L {
    let t = x % y
    x = y
    y = t
  }
  x
}

///|
/// Build a normalized rational. Aborts on a zero denominator: that is a
/// programming error in the engine, never a user-facing condition. Callers that
/// must *detect* a zero denominator check it before dividing.
pub fn rat(num : Int64, den : Int64) -> Rat {
  if den == 0L {
    abort("rat: zero denominator")
  }
  let mut n = num
  let mut d = den
  if d < 0L {
    n = -n
    d = -d
  }
  if n == 0L {
    return { num: 0L, den: 1L, }
  }
  let g = gcd64(n, d)
  { num: n / g, den: d / g, }
}

///|
pub fn rat_int(n : Int64) -> Rat {
  { num: n, den: 1L, }
}

///|
pub fn rat_zero() -> Rat {
  { num: 0L, den: 1L, }
}

///|
pub fn rat_one() -> Rat {
  { num: 1L, den: 1L, }
}

///|
pub fn Rat::is_zero(self : Rat) -> Bool {
  self.num == 0L
}

///|
pub fn Rat::is_integer(self : Rat) -> Bool {
  self.den == 1L
}

///|
pub fn Rat::is_negative(self : Rat) -> Bool {
  self.num < 0L
}

///|
pub fn Rat::num(self : Rat) -> Int64 {
  self.num
}

///|
pub fn Rat::den(self : Rat) -> Int64 {
  self.den
}

///|
pub fn Rat::neg(self : Rat) -> Rat {
  { num: -self.num, den: self.den, }
}

///|
pub fn Rat::abs(self : Rat) -> Rat {
  { num: abs64(self.num), den: self.den, }
}

///|
pub fn Rat::add(self : Rat, other : Rat) -> Rat {
  rat(self.num * other.den + other.num * self.den, self.den * other.den)
}

///|
pub fn Rat::sub(self : Rat, other : Rat) -> Rat {
  rat(self.num * other.den - other.num * self.den, self.den * other.den)
}

///|
pub fn Rat::mul(self : Rat, other : Rat) -> Rat {
  rat(self.num * other.num, self.den * other.den)
}

///|
pub fn Rat::div(self : Rat, other : Rat) -> Rat {
  if other.num == 0L {
    abort("rat: division by zero")
  }
  rat(self.num * other.den, self.den * other.num)
}

///|
/// Sign of the rational: -1, 0, or 1.
pub fn Rat::sign(self : Rat) -> Int32 {
  if self.num < 0L {
    -1
  } else if self.num > 0L {
    1
  } else {
    0
  }
}

///|
pub fn Rat::compare(self : Rat, other : Rat) -> Int32 {
  let left = self.num * other.den
  let right = other.num * self.den
  if left < right {
    -1
  } else if left > right {
    1
  } else {
    0
  }
}

///|
pub fn Rat::equal(self : Rat, other : Rat) -> Bool {
  self.num == other.num && self.den == other.den
}

///|
pub fn Rat::pow(self : Rat, exp : Int32) -> Rat {
  if exp < 0 {
    abort("rat: negative exponent")
  }
  let mut result = rat_one()
  let mut i = 0
  while i < exp {
    result = result.mul(self)
    i = i + 1
  }
  result
}

///|
/// Render as `p/q`, or as a bare integer when the denominator is one.
pub fn Rat::to_string(self : Rat) -> String {
  if self.den == 1L {
    self.num.to_string()
  } else {
    "\{self.num}/\{self.den}"
  }
}

///|
/// Integer square root: `Some(k)` when `n` is a perfect square.
fn isqrt64(n : Int64) -> Int64? {
  if n < 0L {
    return None
  }
  if n == 0L {
    return Some(0L)
  }
  let mut lo = 0L
  let mut hi = n
  if hi > 3037000499L {
    hi = 3037000499L
  }
  while lo <= hi {
    let mid = lo + (hi - lo) / 2L
    let sq = mid * mid
    if sq == n {
      return Some(mid)
    } else if sq < n {
      lo = mid + 1L
    } else {
      if mid == 0L {
        break
      }
      hi = mid - 1L
    }
  }
  None
}

///|
/// Exact square root of a non-negative rational, when it exists.
///
/// `Some(5)` for `25`, `Some(1/2)` for `1/4`, `None` for `2` or `1/3`.
pub fn Rat::sqrt_exact(self : Rat) -> Rat? {
  if self.num < 0L {
    return None
  }
  match (isqrt64(self.num), isqrt64(self.den)) {
    (Some(n), Some(d)) => Some({ num: n, den: d, })
    _ => None
  }
}

///|
/// Integer square root: returns `Some(k)` when `self` is a perfect square of a
/// non-negative integer. The engine uses this to decide whether a discriminant
/// of a quadratic yields rational roots.
pub fn Rat::integer_sqrt(self : Rat) -> Int64? {
  if self.den != 1L {
    return None
  }
  isqrt64(self.num)
}

///|
test "rat normalizes sign and reduces" {
  let a = rat(6L, -8L)
  inspect(a.to_string(), content="-3/4")
  inspect(a.num(), content="-3")
  inspect(a.den(), content="4")
}

///|
test "rat zero has denominator one" {
  inspect(rat(0L, 5L).to_string(), content="0")
  inspect(rat(0L, 5L).den(), content="1")
}

///|
test "rat arithmetic stays exact" {
  let third = rat(1L, 3L)
  let sixth = rat(1L, 6L)
  inspect(third.add(sixth).to_string(), content="1/2")
  inspect(third.sub(sixth).to_string(), content="1/6")
  inspect(third.mul(sixth).to_string(), content="1/18")
  inspect(third.div(sixth).to_string(), content="2")
}

///|
test "rat compare is sign correct" {
  inspect(rat(-1L, 2L).compare(rat(1L, 3L)), content="-1")
  inspect(rat(1L, 3L).compare(rat(2L, 6L)), content="0")
  inspect(rat(3L, 4L).compare(rat(1L, 2L)), content="1")
}

///|
test "integer_sqrt only answers on perfect squares" {
  debug_inspect(rat_int(49L).integer_sqrt(), content="Some(7)")
  debug_inspect(rat_int(50L).integer_sqrt(), content="None")
  debug_inspect(rat(1L, 4L).integer_sqrt(), content="None")
}

///|
/// Property-based tests.
///
/// The example-based tests elsewhere check specific cases; these check the two
/// claims the whole design rests on, over a few hundred generated inputs each:
///
///   1. anything built from two distinct integer roots is accepted by the
///      verifier — i.e. the backward path agrees with the forward path;
///   2. the structural fingerprint really is invariant under scaling, which is
///      what makes de-duplication sound.
///
/// Both use MoonBit's standard `@quickcheck`, including its shrinker, so a
/// failure arrives as a minimal counterexample rather than a random blob.

///|
test "quadratics built from two integer roots always verify" {
  @quickcheck.check((seed : Int32) => {
    let r1 = seed % 9
    let quotient = seed / 9
    let magnitude = if quotient < 0 { -quotient } else { quotient }
    let r2 = r1 + 1 + magnitude % 5
    if r2 <= r1 {
      return true
    }
    let a = @kiln.rat_int(1L)
    let b = @kiln.rat_int((-(r1 + r2)).to_int64())
    let c = @kiln.rat_int((r1 * r2).to_int64())
    let p = @kiln.Poly::new([c, b, a])
    // The roots really are roots: this exercises multiplication, not the verifier.
    let zero = @kiln.rat_zero()
    if !p.eval(@kiln.rat_int(r1.to_int64())).equal(zero) {
      return false
    }
    if !p.eval(@kiln.rat_int(r2.to_int64())).equal(zero) {
      return false
    }
    let (verdict, _) = @kiln.verify_quadratic(p, [
      @kiln.rat_int(r1.to_int64()),
      @kiln.rat_int(r2.to_int64()),
    ])
    verdict.is_well_posed()
  })
}

///|
test "canonical key survives any non-zero scaling" {
  @quickcheck.check((input : (Int32, Int32)) => {
    let (k, raw) = input
    if k == 0 {
      return true
    }
    // Derive coefficients from one integer so the property needs no custom
    // generator, while still covering sign and magnitude variety.
    let a = raw % 7 + 1
    let b = raw / 7 % 13 - 6
    let c = raw / 91 % 11 - 5
    let p = @kiln.Poly::new([
      @kiln.rat_int(c.to_int64()),
      @kiln.rat_int(b.to_int64()),
      @kiln.rat_int(a.to_int64()),
    ])
    let scaled = p.scale(@kiln.rat_int(k.to_int64()))
    p.canonical_key() == scaled.canonical_key()
  })
}

///|
test "a canonical key round-trips to an equal equation" {
  @quickcheck.check((raw : Int32) => {
    let a = raw % 5
    let b = raw / 5 % 11 - 5
    let c = raw / 55 % 9 - 4
    // Degree must stay 2: a linear or constant polynomial has a shorter key.
    if a == 0 {
      return true
    }
    let p = @kiln.Poly::new([
      @kiln.rat_int(c.to_int64()),
      @kiln.rat_int(b.to_int64()),
      @kiln.rat_int(a.to_int64()),
    ])
    // The key of a degree-2 equation must round-trip back to the same equation
    // when its coefficients are read off the key.
    let key = p.canonical_key()
    let parts = @kiln.split_on(key, ',')
    if parts.length() != 3 {
      return false
    }
    let rebuilt : Array[@kiln.Rat] = []
    for token in parts {
      match @kiln.parse_int_opt(token) {
        Some(v) => rebuilt.push(@kiln.rat_int(v.to_int64()))
        None => return false
      }
    }
    let q = @kiln.Poly::new([rebuilt[2], rebuilt[1], rebuilt[0]])
    q.canonical_key() == key
  })
}

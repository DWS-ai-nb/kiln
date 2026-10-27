///|
/// Quadratic family: inverse construction, presentation, and difficulty model.
///
/// Construction runs *forward from the answer*: the schema fixes the roots and
/// the leading coefficient, and Vieta's relations produce `b` and `c`. The
/// verifier in `verify.mbt` runs *backward from the coefficients*. Nothing is
/// shared between the two except the definition of the discriminant.

///|
pub fn build_quadratic(
  schema : Schema,
  env : Map[String, Rat],
) -> Result[Item, String] {
  let a = get_rat(env, "a")
  let b = get_rat(env, "b")
  let c = get_rat(env, "c")
  let r1 = get_rat(env, schema.answers[0].name)
  let r2 = get_rat(env, schema.answers[1].name)
  let p = Poly::new([c, b, a])
  let (verdict, cert) = verify_quadratic(p, [r1, r2])
  if !verdict.is_well_posed() {
    return Err(verdict.to_string())
  }
  let roots = sort_roots([r1, r2])
  let poly_text = p.to_string("x")
  let question = replace_all(schema.ask, "{poly}", poly_text)
  let (level, reasons) = classify_quadratic(b, c, roots)
  let tags = quadratic_tags(b, c, roots)
  Ok({
    schema_name: schema.name,
    question,
    answers: roots,
    level,
    reasons,
    fingerprint: p.canonical_key(),
    certificate: cert,
    robust: cert.robust,
    signature: "a=\{a.to_string()}, b=\{b.to_string()}, c=\{c.to_string()}",
    tags,
  })
}

///|
/// Structural tags. These exist so the assembler can refuse a paper where four
/// out of ten problems happen to have a zero root — which is what happens if you
/// select purely by difficulty.
fn quadratic_tags(b : Rat, c : Rat, roots : Array[Rat]) -> Array[String] {
  let tags : Array[String] = []
  if c.is_zero() {
    tags.push("zero-root")
  }
  if b.is_zero() {
    tags.push("no-linear-term")
  }
  if c.sign() < 0 {
    tags.push("opposite-signs")
  }
  let mut both_negative = true
  let mut unit = false
  for r in roots {
    if r.sign() >= 0 {
      both_negative = false
    }
    if r.abs().equal(rat_one()) {
      unit = true
    }
  }
  if both_negative && roots.length() == 2 {
    tags.push("both-negative")
  }
  if unit {
    tags.push("unit-root")
  }
  tags
}

///|
fn get_rat(env : Map[String, Rat], name : String) -> Rat {
  match env.get(name) {
    Some(v) => v
    None => abort("missing value for '\{name}'")
  }
}

///|
fn sort_roots(xs : Array[Rat]) -> Array[Rat] {
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
fn abs_int64(x : Int64) -> Int64 {
  if x < 0L {
    -x
  } else {
    x
  }
}

///|
/// Explainable difficulty: a small additive model over *named* factors.
///
/// The point is not psychometric precision — that needs response data we do not
/// have. The point is that every level comes with the reasons that produced it,
/// so a teacher can disagree with the model and tune the schema instead of
/// treating the number as magic.
pub fn classify_quadratic(
  b : Rat,
  c : Rat,
  roots : Array[Rat],
) -> (Int32, Array[String]) {
  let reasons : Array[String] = []
  let mut score = 1
  let mut biggest : Int64 = 0L
  for r in roots {
    if r.is_integer() {
      let v = abs_int64(r.num())
      if v > biggest {
        biggest = v
      }
    } else {
      biggest = 99L
    }
  }
  if biggest >= 7L {
    score = score + 2
    reasons.push("根绝对值较大")
  } else if biggest >= 4L {
    score = score + 1
    reasons.push("根超出最小整数区间")
  }
  if c.sign() < 0 {
    score = score + 1
    reasons.push("两根异号")
  }
  let mut both_negative = true
  for r in roots {
    if r.sign() >= 0 {
      both_negative = false
    }
  }
  if both_negative && roots.length() == 2 {
    score = score + 1
    reasons.push("两根同为负")
  }
  if b.is_zero() || c.is_zero() {
    score = score - 1
    reasons.push("方程缺项（偏易）")
  }
  let d = b.mul(b).sub(rat_int(4L).mul(c))
  if d.compare(rat_int(100L)) > 0 {
    score = score + 1
    reasons.push("判别式较大")
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

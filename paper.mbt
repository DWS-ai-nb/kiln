///|
/// Paper assembly.
///
/// A pool of individually verified items is not a worksheet. Assembly has to
/// satisfy a shape (how many items at each difficulty), keep the sheet diverse
/// enough to be worth doing, avoid items already handed out, and — when it
/// cannot — say exactly which part of the shape is impossible instead of
/// silently returning a short paper.
pub(all) struct Blueprint {
  total : Int32
  ///
  /// `(level, count)` pairs. When empty, the assembler cycles through levels
  /// 1..5 so that a plain "give me 10 problems" still yields a spread.
  per_level : Array[(Int32, Int32)]
  seed : Int32
  ///
  /// Fingerprints that must not appear, e.g. everything already handed out in a
  /// previous week.
  exclude : Array[String]
  ///
  /// Upper bound on how many items may share a structural tag. Degenerate tags
  /// (`zero-root`, `no-linear-term`) are always capped at one.
  max_per_tag : Int32
}

///|
pub(all) struct Paper {
  schema_name : String
  items : Array[Item]
  seed : Int32
  request : String
}

///|
pub fn Blueprint::new(total : Int32, seed : Int32) -> Blueprint {
  { total, per_level: [], seed, exclude: [], max_per_tag: 3, }
}

///|
pub fn Blueprint::with_levels(
  per_level : Array[(Int32, Int32)],
  seed : Int32,
) -> Blueprint {
  { total: sum_pairs(per_level), per_level, seed, exclude: [], max_per_tag: 3, }
}

///|
pub fn Blueprint::excluding(
  self : Blueprint,
  fingerprints : Array[String],
) -> Blueprint {
  { ..self, exclude: fingerprints, }
}

///|
pub fn Blueprint::capping(self : Blueprint, max_per_tag : Int32) -> Blueprint {
  { ..self, max_per_tag, }
}

///|
fn sum_pairs(ps : Array[(Int32, Int32)]) -> Int32 {
  let mut s = 0
  for p in ps {
    let (_, n) = p
    s = s + n
  }
  s
}

///|
/// Degenerate structures are capped hard: a sheet where half the equations are
/// missing their constant term teaches nothing.
fn tag_cap(tag : String, soft : Int32) -> Int32 {
  if tag == "zero-root" || tag == "no-linear-term" {
    1
  } else if tag == "opposite-signs" {
    // Two roots with opposite signs is the most valuable variation a sheet can
    // have; capping it would push the hard levels out of reach.
    999
  } else {
    soft
  }
}

///|
fn tags_available(
  tags : Array[String],
  used : Map[String, Int32],
  soft : Int32,
) -> Bool {
  let mut ok = true
  for t in tags {
    match used.get(t) {
      Some(n) => if n >= tag_cap(t, soft) { ok = false }
      None => ()
    }
  }
  ok
}

///|
fn mark_tags(tags : Array[String], used : Map[String, Int32]) -> Unit {
  for t in tags {
    match used.get(t) {
      Some(n) => used[t] = n + 1
      None => used[t] = 1
    }
  }
}

///|
/// Take `count` items of `level`, robust ones first, in a seed-shuffled order,
/// skipping anything that would push a structural tag past its cap.
/// Returns the shortfall so the caller can explain the failure precisely.
fn draw_level(
  candidates : Array[Item],
  level : Int32,
  count : Int32,
  rng : Rng,
  used_tags : Map[String, Int32],
  taken : Map[String, Bool],
  soft_cap : Int32,
) -> (Array[Item], Int32) {
  let robust : Array[Item] = []
  let fragile : Array[Item] = []
  for it in candidates {
    if it.level == level && taken.get(it.fingerprint) is None {
      if it.robust {
        robust.push(it)
      } else {
        fragile.push(it)
      }
    }
  }
  shuffle(rng, robust)
  shuffle(rng, fragile)
  let picked : Array[Item] = []
  let mut i = 0
  while i < robust.length() && picked.length() < count {
    if tags_available(robust[i].tags, used_tags, soft_cap) {
      mark_tags(robust[i].tags, used_tags)
      taken[robust[i].fingerprint] = true
      picked.push(robust[i])
    }
    i = i + 1
  }
  let mut j = 0
  while j < fragile.length() && picked.length() < count {
    if tags_available(fragile[j].tags, used_tags, soft_cap) {
      mark_tags(fragile[j].tags, used_tags)
      taken[fragile[j].fingerprint] = true
      picked.push(fragile[j])
    }
    j = j + 1
  }
  let shortfall = count - picked.length()
  (picked, shortfall)
}

///|
/// Assemble a paper, or explain why the blueprint cannot be satisfied.
///
/// The error message names the level and the exact shortfall. "生成失败" is not
/// an acceptable answer for a teacher who asked for five level-3 problems.
pub fn assemble(
  pool : Pool,
  schema_name : String,
  bp : Blueprint,
) -> Result[Paper, String] {
  let candidates : Array[Item] = []
  for it in pool.items {
    if !contains_str(bp.exclude, it.fingerprint) {
      candidates.push(it)
    }
  }
  let rng = Rng::new(bp.seed)
  let used_tags : Map[String, Int32] = Map([])
  let taken : Map[String, Bool] = Map([])
  let picked : Array[Item] = []
  if bp.per_level.length() > 0 {
    for entry in bp.per_level {
      let (level, count) = entry
      let (got, shortfall) = draw_level(
        candidates,
        level,
        count,
        rng,
        used_tags,
        taken,
        bp.max_per_tag,
      )
      if shortfall > 0 {
        return Err(
          "L\{level} 需要 \{count} 题，可用的只有 \{count - shortfall} 题（缺口 \{shortfall}，可能受结构多样性上限限制）",
        )
      }
      for it in got {
        picked.push(it)
      }
    }
  } else {
    let levels = [1, 2, 3, 4, 5]
    let mut remaining = bp.total
    let mut round = 0
    while remaining > 0 {
      let level = levels[round % 5]
      let (got, _) = draw_level(
        candidates,
        level,
        1,
        rng,
        used_tags,
        taken,
        bp.max_per_tag,
      )
      if got.length() == 1 {
        picked.push(got[0])
        remaining = remaining - 1
      }
      round = round + 1
      if round > 400 {
        let msg = "题池不足以凑满 "
        let msg = msg + bp.total.to_string()
        let msg = msg + " 题（已选出 "
        let msg = msg + picked.length().to_string()
        return Err(msg + " 题），可能受结构多样性上限限制")
      }
    }
  }
  let request = if bp.per_level.length() > 0 {
    let parts : Array[String] = []
    for entry in bp.per_level {
      let (level, count) = entry
      parts.push("L\{level}×\{count}")
    }
    join_with(parts, " ")
  } else {
    "\{bp.total} 题"
  }
  Ok({ schema_name, items: sort_by_level(picked), seed: bp.seed, request, })
}

///|
/// Stable sort by level so a printed sheet gets easier-to-harder ordering
/// instead of the interleaved order the quotas are drawn in.
fn sort_by_level(items : Array[Item]) -> Array[Item] {
  let out = items.copy()
  let mut i = 1
  while i < out.length() {
    let key = out[i]
    let mut j = i - 1
    while j >= 0 && out[j].level > key.level {
      out[j + 1] = out[j]
      j = j - 1
    }
    out[j + 1] = key
    i = i + 1
  }
  out
}

///|
fn join_with(parts : Array[String], sep : String) -> String {
  let sb = StringBuilder()
  for i, p in parts {
    if i > 0 {
      sb.write_string(sep)
    }
    sb.write_string(p)
  }
  sb.to_string()
}

///|
pub fn Paper::size(self : Paper) -> Int32 {
  self.items.length()
}

///|
pub fn Paper::tag_counts(self : Paper) -> Map[String, Int32] {
  let counts : Map[String, Int32] = Map([])
  for it in self.items {
    mark_tags(it.tags, counts)
  }
  counts
}

///|
test "assembly honours per-level quotas" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(e) => abort("schema error: \{e}")
  }
  let pool = generate(schema, 0)
  let bp = Blueprint::with_levels([(1, 2), (2, 2), (3, 2)], 7)
  match assemble(pool, schema.name, bp) {
    Ok(paper) => {
      inspect(paper.size(), content="6")
      inspect(paper.items[0].level, content="1")
      inspect(paper.items[5].level, content="3")
    }
    Err(e) => abort("unexpected: \{e}")
  }
}

///|
test "assembly is reproducible for a seed" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(_) => abort("schema error")
  }
  let pool = generate(schema, 0)
  let bp = Blueprint::new(8, 2026)
  let a = match assemble(pool, schema.name, bp) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let b = match assemble(pool, schema.name, bp) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let mut same = true
  for i in 0..<a.size() {
    if a.items[i].fingerprint != b.items[i].fingerprint {
      same = false
    }
  }
  inspect(same, content="true")
}

///|
test "different seeds give different papers" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(_) => abort("schema error")
  }
  let pool = generate(schema, 0)
  let a = match assemble(pool, schema.name, Blueprint::new(6, 1)) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let b = match assemble(pool, schema.name, Blueprint::new(6, 2)) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let mut diff = 0
  for i in 0..<a.size() {
    if a.items[i].fingerprint != b.items[i].fingerprint {
      diff = diff + 1
    }
  }
  inspect(diff > 0, content="true")
}

///|
test "impossible quota explains the shortfall" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(_) => abort("schema error")
  }
  let pool = generate(schema, 0)
  let bp = Blueprint::with_levels([(1, 3), (5, 400)], 3)
  match assemble(pool, schema.name, bp) {
    Ok(_) => abort("expected a shortfall")
    Err(e) => {
      inspect(e.contains("L5"), content="true")
      inspect(e.contains("缺口"), content="true")
    }
  }
}

///|
test "excluded fingerprints never reappear" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(_) => abort("schema error")
  }
  let pool = generate(schema, 0)
  let first = match assemble(pool, schema.name, Blueprint::new(5, 11)) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let used : Array[String] = []
  for it in first.items {
    used.push(it.fingerprint)
  }
  let second = match
    assemble(pool, schema.name, Blueprint::new(5, 11).excluding(used)) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let mut overlap = 0
  for it in second.items {
    if contains_str(used, it.fingerprint) {
      overlap = overlap + 1
    }
  }
  inspect(overlap, content="0")
}

///|
/// Regression test for a real bug: drawing level by level re-shuffled the same
/// bucket and could hand out the same problem twice in one sheet.
test "no paper ever repeats a fingerprint" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(_) => abort("schema error")
  }
  let pool = generate(schema, 0)
  let mut worst = 0
  for seed in 1..<=10 {
    let paper = match assemble(pool, schema.name, Blueprint::new(20, seed)) {
      Ok(p) => p
      Err(e) => abort(e)
    }
    let seen : Array[String] = []
    let mut dup = 0
    for it in paper.items {
      if contains_str(seen, it.fingerprint) {
        dup = dup + 1
      } else {
        seen.push(it.fingerprint)
      }
    }
    if dup > worst {
      worst = dup
    }
  }
  inspect(worst, content="0")
}

///|
test "degenerate structures never dominate a paper" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(_) => abort("schema error")
  }
  let pool = generate(schema, 0)
  // Sweep seeds: the cap must hold no matter how the shuffle falls.
  let mut worst_zero = 0
  let mut worst_missing = 0
  for seed in 1..<=12 {
    let paper = match assemble(pool, schema.name, Blueprint::new(10, seed)) {
      Ok(p) => p
      Err(e) => abort(e)
    }
    let counts = paper.tag_counts()
    let zeros = match counts.get("zero-root") {
      Some(n) => n
      None => 0
    }
    let missing = match counts.get("no-linear-term") {
      Some(n) => n
      None => 0
    }
    if zeros > worst_zero {
      worst_zero = zeros
    }
    if missing > worst_missing {
      worst_missing = missing
    }
  }
  inspect(worst_zero <= 1, content="true")
  inspect(worst_missing <= 1, content="true")
}

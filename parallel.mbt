///|
/// Equivalent forms (parallel papers, A/B 卷).
///
/// The claim here is *structural equivalence*, not textual: form B is made by
/// swapping every item of form A for a *different* item with the same
/// difficulty and the same structural tags. The two forms therefore have the
/// same level histogram and the same tag profile, so a teacher can hand them to
/// two groups and grade both against the same rubric.
///
/// Matching is greedy and deterministic. An exact-tag replacement is preferred;
/// when none is left, a same-level replacement is accepted and the fact is
/// recorded so the caller can decide whether to reject the form.
fn count_str(xs : Array[String], x : String) -> Int32 {
  let mut n = 0
  for y in xs {
    if y == x {
      n = n + 1
    }
  }
  n
}

///|
/// Order-insensitive equality of tag lists.
fn same_tags(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for x in a {
    if count_str(a, x) != count_str(b, x) {
      return false
    }
  }
  true
}

///|
/// A single replacement decision: the chosen item and whether the match was on
/// exact tags (`true`) or only on difficulty (`false`).
priv struct Pick {
  item : Item
  exact : Bool
}

///|
/// Find one replacement for `slot` from the pool, excluding fingerprints that
/// are already in form A or already taken into form B.
fn pick_replacement(
  pool : Pool,
  level : Int32,
  tags : Array[String],
  taken : Map[String, Bool],
  rng : Rng,
) -> Pick? {
  let exact : Array[Item] = []
  let fallback : Array[Item] = []
  for it in pool.items {
    if it.level == level && taken.get(it.fingerprint) is None {
      if same_tags(it.tags, tags) {
        exact.push(it)
      } else {
        fallback.push(it)
      }
    }
  }
  shuffle(rng, exact)
  shuffle(rng, fallback)
  if exact.length() > 0 {
    let chosen = exact[0]
    taken[chosen.fingerprint] = true
    return Some({ item: chosen, exact: true, })
  }
  if fallback.length() > 0 {
    let chosen = fallback[0]
    taken[chosen.fingerprint] = true
    return Some({ item: chosen, exact: false, })
  }
  None
}

///|
/// Build a parallel form.
///
/// `seed` selects the swap; the same seed always yields the same form. Fails
/// with a precise message when any slot cannot be filled — a short paper is
/// never returned.
fn build_form(
  pool : Pool,
  slots : Array[Slot],
  schema_name : String,
  request : String,
  seed : Int32,
) -> Result[Paper, String] {
  let taken : Map[String, Bool] = Map([])
  // Everything already on form A is off-limits.
  for slot in slots {
    taken[slot.fingerprint] = true
  }
  let rng = Rng::new(seed)
  let items : Array[Item] = []
  let mut relaxed = 0
  for i, slot in slots {
    match pick_replacement(pool, slot.level, slot.tags, taken, rng) {
      Some(p) => {
        if !p.exact {
          relaxed = relaxed + 1
        }
        items.push(p.item)
      }
      None =>
        return Err(
          "第 \{i + 1} 题（L\{slot.level}）找不到等价替换，题池已耗尽或结构过于单一",
        )
    }
  }
  if relaxed > 0 {
    return Err(
      "\{relaxed} 道题只能按难度等价、无法按结构标签精确匹配，请放宽 schema 的 domain 后重试",
    )
  }
  Ok({ schema_name, items, seed, request: request + "（平行卷）", })
}

///|
/// The structural profile of one slot: difficulty plus tags. Both the in-memory
/// `Paper` and the on-disk `PaperFile` reduce to this, so the same matcher works
/// for either.
pub(all) struct Slot {
  level : Int32
  tags : Array[String]
  fingerprint : String
}

///|
/// Build a parallel form from an assembled paper.
pub fn parallel_form(
  pool : Pool,
  paper : Paper,
  seed : Int32,
) -> Result[Paper, String] {
  let slots : Array[Slot] = []
  for it in paper.items {
    slots.push({ level: it.level, tags: it.tags, fingerprint: it.fingerprint, })
  }
  build_form(pool, slots, paper.schema_name, paper.request, seed)
}

///|
/// Build a parallel form straight from a paper file, without going through the
/// generator. This is the path the CLI takes: `A.json` in, `B.json` out.
pub fn parallel_paper_file(
  pool : Pool,
  pf : PaperFile,
  seed : Int32,
) -> Result[Paper, String] {
  let slots : Array[Slot] = []
  for it in pf.items {
    slots.push({ level: it.level, tags: it.tags, fingerprint: it.fingerprint, })
  }
  build_form(pool, slots, pf.schema_name, "平行卷", seed)
}

///|
test "parallel form has identical level and tag histograms" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(e) => abort(e)
  }
  let pool = generate(schema, 0)
  let a = match assemble(pool, schema.name, Blueprint::new(8, 7)) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let b = match parallel_form(pool, a, 99) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  inspect(b.size(), content="8")
  let ha = a.tag_counts()
  let hb = b.tag_counts()
  for t in ["zero-root", "no-linear-term", "opposite-signs", "both-negative"] {
    let ca = match ha.get(t) {
      Some(n) => n
      None => 0
    }
    let cb = match hb.get(t) {
      Some(n) => n
      None => 0
    }
    inspect(ca == cb, content="true")
  }
}

///|
test "parallel form never reuses a fingerprint" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(e) => abort(e)
  }
  let pool = generate(schema, 0)
  let a = match assemble(pool, schema.name, Blueprint::new(6, 3)) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let b = match parallel_form(pool, a, 5) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let used : Array[String] = []
  for it in a.items {
    used.push(it.fingerprint)
  }
  let mut overlap = 0
  for it in b.items {
    if contains_str(used, it.fingerprint) {
      overlap = overlap + 1
    }
  }
  inspect(overlap, content="0")
}

///|
test "parallel form is reproducible per seed" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(e) => abort(e)
  }
  let pool = generate(schema, 0)
  let a = match assemble(pool, schema.name, Blueprint::new(5, 11)) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let b1 = match parallel_form(pool, a, 42) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let b2 = match parallel_form(pool, a, 42) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let mut same = true
  for i in 0..<b1.size() {
    if b1.items[i].fingerprint != b2.items[i].fingerprint {
      same = false
    }
  }
  inspect(same, content="true")
}

///|
test "parallel form fails cleanly when the pool is exhausted" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(e) => abort(e)
  }
  let pool = generate(schema, 0)
  let a = match assemble(pool, schema.name, Blueprint::new(5, 2)) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  // A synthetic pool that contains only form A's own items: no replacement
  // can exist, and the failure must name the offending slot instead of
  // returning a short paper.
  let exhausted : Pool = {
    items: a.items.copy(),
    attempted: a.size(),
    rejected: 0,
    duplicates: 0,
    rejects: [],
  }
  match parallel_form(exhausted, a, 3) {
    Ok(_) => abort("expected an error: pool has no spare items")
    Err(e) => inspect(e.contains("找不到等价替换"), content="true")
  }
}

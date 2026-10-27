///|
/// Blackbox tests: these see kiln exactly as an embedder would — only what is
/// exported, with no access to internals. If a refactor breaks the public
/// contract without breaking these, the contract was not worth much.
///
/// A minimal schema kept inline so the test is self-contained.
const MINI_SCHEMA : String =
  #|schema "mini"
  #|family quadratic
  #|answer {
  #|  r1: int in [-5, 5]
  #|  r2: int in [-5, 5]
  #|}
  #|param {
  #|  a: 1
  #|  b: -(r1 + r2)
  #|  c: r1 * r2
  #|}
  #|require {
  #|  r1 < r2
  #|}
  #|ask "解方程 {poly} = 0"
  #|

///|
test "an embedder can go from text to a paper in one call" {
  let paper = match @kiln.quick_paper(MINI_SCHEMA, 6, 99) {
    Ok(p) => p
    Err(e) => abort("unexpected: \{e}")
  }
  inspect(paper.size(), content="6")
  // Levels must be non-decreasing: the sheet reads easier to harder.
  let mut ordered = true
  let mut prev = 0
  for it in paper.items {
    if it.level < prev {
      ordered = false
    }
    prev = it.level
  }
  inspect(ordered, content="true")
}

///|
test "every exported item can be re-checked with exported functions only" {
  let paper = match @kiln.quick_paper(MINI_SCHEMA, 8, 4) {
    Ok(p) => p
    Err(e) => abort("unexpected: \{e}")
  }
  for item in paper.items {
    let cert = item.certificate
    let poly = @kiln.Poly::new([cert.c, cert.b, cert.a])
    let (verdict, _) = @kiln.verify_quadratic(poly, item.answers)
    if !verdict.is_well_posed() {
      abort("item failed re-verification: \{item.question}")
    }
  }
  inspect(paper.size(), content="8")
}

///|
test "renderers produce documents that need no network" {
  let paper = match @kiln.quick_paper(MINI_SCHEMA, 3, 1) {
    Ok(p) => p
    Err(e) => abort("unexpected: \{e}")
  }
  let html = @kiln.render_worksheet(paper, "测试卷")
  inspect(html.contains("<script"), content="false")
  inspect(html.contains("http://"), content="false")
  inspect(html.contains("https://"), content="false")
  let md = @kiln.render_markdown(paper, "测试卷")
  inspect(md.contains("## 答案"), content="true")
}

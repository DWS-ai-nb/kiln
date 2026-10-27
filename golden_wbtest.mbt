///|
/// Cross-backend parity, pinned as golden text.
///
/// These tests are not here to detect feature changes — the behavioural tests
/// cover that. They exist to make a specific claim checkable: *the same seed
/// produces byte-identical output on every backend*. Run
/// `moon test --target wasm-gc` and `moon test --target js` and the same
/// expected strings must pass on both.
///
/// If a future change introduces floating point, hash-order dependence or
/// locale-sensitive formatting, one of the two backends will drift and this file
/// is where it shows up first.
fn render_golden(paper : Paper) -> String {
  let sb = StringBuilder()
  for it in paper.items {
    sb.write_string(it.fingerprint)
    sb.write_string(" | ")
    sb.write_string(it.question)
    sb.write_string(" | ")
    sb.write_string(it.answer_text())
    sb.write_string("\n")
  }
  sb.to_string()
}

///|
test "quadratic: seed 11 pins an exact sheet" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(e) => abort(e)
  }
  let pool = generate(schema, 0)
  let paper = match assemble(pool, schema.name, Blueprint::new(8, 11)) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  inspect(
    render_golden(paper),
    content=(
      #|1,-5,0 | 解方程 x² - 5x = 0 | x₁ = 0，x₂ = 5
      #|1,0,-9 | 解方程 x² - 9 = 0 | x₁ = -3，x₂ = 3
      #|1,2,-3 | 解方程 x² + 2x - 3 = 0 | x₁ = -3，x₂ = 1
      #|1,-7,6 | 解方程 x² - 7x + 6 = 0 | x₁ = 1，x₂ = 6
      #|1,4,-5 | 解方程 x² + 4x - 5 = 0 | x₁ = -5，x₂ = 1
      #|1,2,-8 | 解方程 x² + 2x - 8 = 0 | x₁ = -4，x₂ = 2
      #|1,-5,-14 | 解方程 x² - 5x - 14 = 0 | x₁ = -2，x₂ = 7
      #|1,-1,-56 | 解方程 x² - x - 56 = 0 | x₁ = -7，x₂ = 8
      #|
    ),
  )
}

///|
test "rational: seed 3 pins an exact sheet" {
  let schema = match load_schema(RATIONAL_SCHEMA) {
    Ok(s) => s
    Err(e) => abort(e)
  }
  let pool = generate(schema, 0)
  let paper = match assemble(pool, schema.name, Blueprint::new(6, 3)) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  inspect(
    render_golden(paper),
    content=(
      #|1,3/1,0=2 | 解方程 (x + 3)/x = 2 | x = 3
      #|1,4/1,0=2 | 解方程 (x + 4)/x = 2 | x = 4
      #|1,4/1,1=2 | 解方程 (x + 4)/(x + 1) = 2 | x = 2
      #|1,-10/1,-3=2 | 解方程 (x - 10)/(x - 3) = 2 | x = -4
      #|1,-10/1,-2=2 | 解方程 (x - 10)/(x - 2) = 2 | x = -6
      #|1,-4/1,2=3 | 解方程 (x - 4)/(x + 2) = 3 | x = -5
      #|
    ),
  )
}

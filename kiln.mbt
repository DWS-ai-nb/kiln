///|
/// kiln — well-posed problem generation with machine-checkable certificates.
///
/// The library is arranged as a pipeline, and each stage is usable on its own:
///
///   1. `load_schema`   text → `Schema` (parse + static validation)
///   2. `generate`      `Schema` → `Pool` of independently verified `Item`s
///   3. `assemble`      `Pool` + `Blueprint` → `Paper`
///   4. `render_*`      `Paper` → self-contained HTML / Markdown
///
/// The convenience entry point for embedders is `quick_paper`, which runs the
/// first three stages and reports every failure as a string instead of raising.
pub fn quick_paper(
  schema_src : String,
  count : Int32,
  seed : Int32,
) -> Result[Paper, String] {
  match load_schema(schema_src) {
    Err(e) => Err(e)
    Ok(schema) => {
      let pool = generate(schema, 0)
      if pool.size() == 0 {
        return Err("schema '\{schema.name}' 没有产出任何题目")
      }
      assemble(pool, schema.name, Blueprint::new(count, seed))
    }
  }
}

///|
/// Same as `quick_paper`, but with an explicit difficulty shape.
pub fn quick_paper_with(
  schema_src : String,
  per_level : Array[(Int32, Int32)],
  seed : Int32,
) -> Result[Paper, String] {
  match load_schema(schema_src) {
    Err(e) => Err(e)
    Ok(schema) => {
      let pool = generate(schema, 0)
      if pool.size() == 0 {
        return Err("schema '\{schema.name}' 没有产出任何题目")
      }
      assemble(pool, schema.name, Blueprint::with_levels(per_level, seed))
    }
  }
}

///|
test "quick_paper runs the whole pipeline" {
  match quick_paper(SAMPLE_SCHEMA, 5, 3) {
    Ok(paper) => {
      inspect(paper.size(), content="5")
      inspect(paper.schema_name, content="quadratic_int_roots")
    }
    Err(e) => abort("unexpected: \{e}")
  }
}

///|
test "quick_paper surfaces schema errors instead of raising" {
  match quick_paper("schema \"bad\"\nfamily quadratic\n", 3, 1) {
    Ok(_) => abort("expected an error")
    Err(e) => inspect(e.contains("answer"), content="true")
  }
}

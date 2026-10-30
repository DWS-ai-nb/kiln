///|
/// An application can use the model library without the legacy generator,
/// filesystem, CLI, Python, FFI or a network service.
fn main {
  let model : @model.Model = {
    variables: [
      { name: "x", values: [0L, 1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L, 9L], },
      { name: "y", values: [0L, 1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L, 9L], },
    ],
    rules: [
      { id: "sum", rule: Eq(Add(Var("x"), Var("y")), Int(9L)), },
      { id: "difference", rule: Eq(Sub(Var("x"), Var("y")), Int(3L)), },
    ],
  }
  match @model.classify(model) {
    Ok(Unique(assignment)) => {
      println("unique: " + @model.assignment_to_json(assignment).stringify())
      match @model.check_assignment(model, assignment) {
        Ok(report) => println("verified: " + report.valid.to_string())
        Err(e) => abort(e)
      }
    }
    Ok(_) => abort("expected a unique solution")
    Err(e) => abort(e)
  }
}

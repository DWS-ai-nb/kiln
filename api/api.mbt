///|
fn failure(message : String) -> String {
  let j : Json = { "error": message }
  j.stringify()
}

///|
/// JavaScript/browser bridge. Budgets are validated by the model library.
pub fn solve_json(
  source : String,
  budget : Int32,
  max_solutions : Int32,
) -> String {
  match @model.parse_document(source) {
    Err(e) => failure(e)
    Ok(doc) =>
      match
        @model.solve(doc.model, config=@model.options(budget~, max_solutions~)) {
        Err(e) => failure(e)
        Ok(r) => @model.search_to_json(r).stringify()
      }
  }
}

///|
pub fn verify_json(source : String, assignment : String) -> String {
  match (@model.parse_document(source), @model.parse_assignment(assignment)) {
    (Err(e), _) | (_, Err(e)) => failure(e)
    (Ok(doc), Ok(a)) =>
      match @model.check_assignment(doc.model, a) {
        Err(e) => failure(e)
        Ok(r) => {
          let j : Json = { "valid": r.valid, "violations": r.violations }
          j.stringify()
        }
      }
  }
}

///|
pub fn minimize_json(source : String, budget : Int32) -> String {
  match @model.parse_document(source) {
    Err(e) => failure(e)
    Ok(doc) =>
      match doc.objective {
        None => failure("document has no objective")
        Some(t) =>
          match @model.minimize(doc.model, t, budget~) {
            Err(e) => failure(e)
            Ok(r) => {
              let j : Map[String, Json] = Map([])
              j["format"] = Json::string("kiln.optimization/1")
              j["optimal"] = Json::boolean(r.optimal)
              j["stop"] = Json::string(@model.stop_name(r.stop))
              j["statistics"] = @model.statistics_to_json(r.stats)
              j["value"] = match r.value {
                Some(n) => Json::number(n.to_double())
                None => Json::null()
              }
              j["assignment"] = match r.assignment {
                Some(a) => @model.assignment_to_json(a)
                None => Json::null()
              }
              Json::object(j).stringify()
            }
          }
      }
  }
}

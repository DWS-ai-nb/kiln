///|
fn failure(message : String) -> String {
  let j : Json = { "error": message }
  j.stringify()
}

///|
// The JS ABI does not enforce MoonBit parameter types. Validate actual JS
// values before numeric conversion; this guard contains no solver logic.
#cfg(target="js")
extern "js" fn integer_parameter(
  value : Double,
  low : Double,
  high : Double,
) -> Bool =
  #| (value, low, high) => typeof value === "number" && Number.isInteger(value) && value >= low && value <= high

///|
#cfg(not(target="js"))
fn integer_parameter(value : Double, low : Double, high : Double) -> Bool {
  value >= low && value <= high && value.to_int().to_double() == value
}

///|
pub fn compare_json(
  before : String,
  after : String,
  budget : Double,
  max_solutions : Double,
) -> String {
  if !integer_parameter(budget, 0.0, 100000000.0) ||
    !integer_parameter(max_solutions, 1.0, 1000000.0) {
    return failure("budget and limit must be finite integer numbers in range")
  }
  match (@model.parse_document(before), @model.parse_document(after)) {
    (Err(e), _) | (_, Err(e)) => failure(e)
    (Ok(a), Ok(b)) =>
      match
        @regression.compare(
          a.model,
          b.model,
          config=@model.options(
            budget=budget.to_int(),
            max_solutions=max_solutions.to_int(),
          ),
        ) {
        Err(e) => failure(e)
        Ok(r) => @regression.comparison_to_json(r).stringify()
      }
  }
}

///|
pub fn closest_json(
  before : String,
  after : String,
  baseline : String,
  budget : Double,
) -> String {
  if !integer_parameter(budget, 0.0, 100000000.0) {
    return failure("budget must be a finite integer number in range")
  }
  match
    (
      @model.parse_document(before),
      @model.parse_document(after),
      @model.parse_assignment(baseline),
    ) {
    (Err(e), _, _) | (_, Err(e), _) | (_, _, Err(e)) => failure(e)
    (Ok(a), Ok(b), Ok(env)) =>
      match
        @regression.closest_change(
          a.model,
          b.model,
          env,
          budget=budget.to_int(),
        ) {
        Err(e) => failure(e)
        Ok(r) => @regression.closest_to_json(r).stringify()
      }
  }
}

///|
/// JavaScript/browser bridge. Validate actual JS numbers before conversion.
pub fn solve_json(
  source : String,
  budget : Double,
  max_solutions : Double,
) -> String {
  if !integer_parameter(budget, 0.0, 100000000.0) ||
    !integer_parameter(max_solutions, 1.0, 1000000.0) {
    return failure("budget and limit must be finite integer numbers in range")
  }
  match @model.parse_document(source) {
    Err(e) => failure(e)
    Ok(doc) =>
      match
        @model.solve(
          doc.model,
          config=@model.options(
            budget=budget.to_int(),
            max_solutions=max_solutions.to_int(),
          ),
        ) {
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
pub fn minimize_json(source : String, budget : Double) -> String {
  if !integer_parameter(budget, 0.0, 100000000.0) {
    return failure("budget must be a finite integer number in range")
  }
  match @model.parse_document(source) {
    Err(e) => failure(e)
    Ok(doc) =>
      match doc.objective {
        None => failure("document has no objective")
        Some(t) =>
          match @model.minimize(doc.model, t, budget=budget.to_int()) {
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

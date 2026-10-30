///|
fn die(message : String) -> Unit {
  let j : Json = { "error": message }
  println(j.stringify())
  @sys.exit(2)
}

///|
fn[T] must(value : Result[T, String]) -> T {
  match value {
    Ok(v) => v
    Err(e) => {
      die(e)
      abort(e)
    }
  }
}

///|
fn read(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    _ => {
      die("cannot read " + path)
      abort("read failed")
    }
  }
}

///|
fn usage() -> Unit {
  println("kiln model 0.2 — finite-domain rule verification")
  println("moon run cmd/model -- <command> <model.json> [options]")
  println("  solve           enumerate solutions; --budget N --limit N")
  println(
    "  counterexample  violate one named rule; --rule ID --budget N --limit N",
  )
  println("  verify          check a witness; --assignment assignment.json")
  println("  minimize        minimize document.objective; --budget N")
  println(
    "  explain         diagnose an unsat model; --budget N (per deletion check)",
  )
  println("  validate        validate only; does not search")
  println(
    "Exit: 0 completed/valid; 1 invalid witness; 2 input error; 3 incomplete search.",
  )
}

///|
fn parse_option_int(value : String) -> Int32 {
  let mut n = 0
  if value == "" {
    die("expected nonnegative integer")
    return 0
  }
  for c in value {
    if c < '0' || c > '9' || n > 10000000 {
      die("invalid integer option: " + value)
      return 0
    }
    n = n * 10 + c.to_int() - '0'.to_int()
  }
  n
}

///|
fn main {
  let argv = @env.args()
  if argv.length() < 2 || argv[1] == "help" || argv[1] == "--help" {
    usage()
    return
  }
  if argv.length() < 3 {
    die("expected command and model path")
    return
  }
  let command = argv[1]
  if !["solve", "counterexample", "verify", "minimize", "explain", "validate"].contains(
      command,
    ) {
    die("unknown command: " + command)
    return
  }
  let flags : Map[String, String] = Map([])
  let mut i = 3
  while i < argv.length() {
    let name = argv[i]
    let allowed = match command {
      "solve" => ["--budget", "--limit"]
      "counterexample" => ["--budget", "--limit", "--rule"]
      "verify" => ["--assignment"]
      "minimize" | "explain" => ["--budget"]
      _ => []
    }
    if !allowed.contains(name) || flags.contains(name) || i + 1 >= argv.length() {
      die("unknown, duplicate or incomplete option: " + name)
      return
    }
    flags[name] = argv[i + 1]
    i += 2
  }
  let mut budget = 100000
  let mut limit = 1000
  for key, value in flags {
    if key == "--budget" || key == "--limit" {
      let n = parse_option_int(value)
      if key == "--budget" {
        budget = n
      } else {
        limit = n
      }
    }
  }
  // Consistent validation even for operations which never start a search.
  if budget < 0 || budget > 100000000 || limit < 1 || limit > 1000000 {
    die("budget/limit out of range")
    return
  }
  let source = read(argv[2])
  let doc = must(@csp.parse_document(source))
  let mut model = doc.model
  if command == "counterexample" {
    let id = match flags.get("--rule") {
      Some(v) => v
      None => {
        die("--rule is required")
        return
      }
    }
    model = must(@csp.negate_rule(model, id))
  }
  match command {
    "validate" => println("{\"valid\":true}")
    "solve" | "counterexample" => {
      let r = must(
        @csp.solve(model, config=@csp.options(budget~, max_solutions=limit)),
      )
      let j = @csp.search_to_json(r)
      if j is Object(m) {
        m["model"] = @csp.document_to_json({ model, objective: None, })
        m["operation"] = Json::string(command)
      }
      println(j.stringify(indent=2))
      if r.stop != @csp.Exhausted {
        @sys.exit(3)
      }
    }
    "verify" => {
      let file = match flags.get("--assignment") {
        Some(f) => f
        None => {
          die("--assignment is required")
          return
        }
      }
      let assignment = must(@csp.parse_assignment(read(file)))
      let report = must(@csp.check_assignment(model, assignment))
      let j : Json = { "valid": report.valid, "violations": report.violations }
      println(j.stringify(indent=2))
      if !report.valid {
        @sys.exit(1)
      }
    }
    "minimize" => {
      if doc.objective is None {
        die("document has no objective")
        return
      }
      let objective = match doc.objective {
        Some(t) => t
        None => {
          die("missing objective")
          return
        }
      }
      let result = must(@csp.minimize(model, objective, budget~))
      let j : Map[String, Json] = Map([])
      j["format"] = Json::string("kiln.optimization/1")
      j["optimal"] = Json::boolean(result.optimal)
      j["stop"] = Json::string(@csp.stop_name(result.stop))
      j["statistics"] = @csp.statistics_to_json(result.stats)
      j["value"] = match result.value {
        Some(n) => Json::number(n.to_double())
        None => Json::null()
      }
      j["assignment"] = match result.assignment {
        Some(a) => @csp.assignment_to_json(a)
        None => Json::null()
      }
      println(Json::object(j).stringify(indent=2))
      if result.stop != @csp.Exhausted {
        @sys.exit(3)
      }
    }
    "explain" => {
      let c = must(@csp.explain(model, budget_per_check=budget))
      let j : Json = {
        "rule_ids": c.rule_ids,
        "irreducible": c.irreducible,
        "checks": c.checks,
      }
      println(j.stringify(indent=2))
      if !c.irreducible {
        @sys.exit(3)
      }
    }
    _ => ()
  }
}

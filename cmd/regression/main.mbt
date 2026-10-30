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
fn nonnegative(value : String) -> Int32 {
  let mut n = 0
  if value == "" {
    die("empty integer option")
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
  let raw = @env.args()
  let args : Array[String] = []
  let offset = if raw.length() > 1 && raw[1].has_suffix(".js") { 1 } else { 0 }
  for i in offset..<raw.length() {
    args.push(raw[i])
  }
  if args.length() < 2 || args[1] == "--help" || args[1] == "help" {
    println(
      "kiln regression 0.2 — semantic regression for finite arithmetic rules",
    )
    println(
      "moon run cmd/regression -- diff BEFORE.json AFTER.json [--budget N --limit N]",
    )
    println(
      "moon run cmd/regression -- closest BEFORE.json AFTER.json --baseline BASE.json [--budget N]",
    )
    println(
      "moon run cmd/regression -- replay BEFORE.json AFTER.json --assignment CASE.json",
    )
    println(
      "Exit: 0 equivalent/replayed; 1 changed/not a witness; 2 input error; 3 unknown.",
    )
    return
  }
  if args.length() < 4 {
    die("expected operation and two model paths")
    return
  }
  let op = args[1]
  if !["diff", "closest", "replay"].contains(op) {
    die("unknown operation: " + op)
    return
  }
  let flags : Map[String, String] = Map([])
  let mut i = 4
  while i < args.length() {
    let key = args[i]
    let allowed = match op {
      "diff" => ["--budget", "--limit"]
      "closest" => ["--budget", "--baseline"]
      _ => ["--assignment"]
    }
    if !allowed.contains(key) || flags.contains(key) || i + 1 >= args.length() {
      die("unknown, duplicate or incomplete option: " + key)
      return
    }
    flags[key] = args[i + 1]
    i += 2
  }
  let budget = match flags.get("--budget") {
    None => 100000
    Some(s) => nonnegative(s)
  }
  let limit = match flags.get("--limit") {
    None => 1000
    Some(s) => nonnegative(s)
  }
  if budget > 100000000 || limit < 1 || limit > 1000000 {
    die("budget/limit out of range")
    return
  }
  let before = must(@model.parse_document(read(args[2]))).model
  let after = must(@model.parse_document(read(args[3]))).model
  match op {
    "diff" => {
      let r = must(
        @delta.compare(
          before,
          after,
          config=@model.options(budget~, max_solutions=limit),
        ),
      )
      println(@delta.comparison_to_json(r).stringify(indent=2))
      match r.relation {
        Changed => @sys.exit(1)
        Unknown => @sys.exit(3)
        Equivalent => ()
      }
    }
    "closest" => {
      let path = match flags.get("--baseline") {
        Some(p) => p
        None => {
          die("--baseline is required")
          return
        }
      }
      let baseline = must(@model.parse_assignment(read(path)))
      let r = must(@delta.closest_change(before, after, baseline, budget~))
      println(@delta.closest_to_json(r).stringify(indent=2))
      if r.change is Some(_) {
        @sys.exit(1)
      }
      if r.stop != @model.Exhausted {
        @sys.exit(3)
      }
    }
    "replay" => {
      let path = match flags.get("--assignment") {
        Some(p) => p
        None => {
          die("--assignment is required")
          return
        }
      }
      let assignment = must(@model.parse_assignment(read(path)))
      match @delta.replay(before, after, assignment) {
        Ok(c) => println(@delta.change_to_json(c).stringify(indent=2))
        Err(e) => {
          let j : Json = { "witness": false, "reason": e }
          println(j.stringify())
          @sys.exit(1)
        }
      }
    }
    _ => ()
  }
}

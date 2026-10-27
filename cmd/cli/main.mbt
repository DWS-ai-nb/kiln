///|
/// `kiln` command line.
///
/// Three verbs, no configuration files, no global state:
///   gen    generate a paper and its answer key
///   check  re-verify every item in the pool and report
///   pool   inspect the candidate pool without drawing a paper
fn usage() -> Unit {
  println("kiln — 可验证命题引擎")
  println("")
  println("用法：")
  println(
    "  kiln gen   --schema <file> [--count N] [--levels 1:2,2:3] [--seed S] [--out DIR] [--title T]",
  )
  println("  kiln check --schema <file> [--verbose]")
  println("  kiln pool  --schema <file> [--limit N] [--show N]")
}

///|
fn flag(argv : Array[String], name : String) -> String? {
  let mut i = 0
  while i + 1 < argv.length() {
    if argv[i] == name {
      return Some(argv[i + 1])
    }
    i = i + 1
  }
  None
}

///|
fn has_flag(argv : Array[String], name : String) -> Bool {
  let mut found = false
  for a in argv {
    if a == name {
      found = true
    }
  }
  found
}

///|
fn flag_int(argv : Array[String], name : String, fallback : Int32) -> Int32 {
  match flag(argv, name) {
    Some(v) =>
      match @kiln.parse_int_opt(v) {
        Some(n) => n
        None => fallback
      }
    None => fallback
  }
}

///|
fn parse_levels(s : String) -> Array[(Int32, Int32)] {
  let out : Array[(Int32, Int32)] = []
  for part in @kiln.split_on(s, ',') {
    let kv = @kiln.split_on(part, ':')
    if kv.length() == 2 {
      match (@kiln.parse_int_opt(kv[0]), @kiln.parse_int_opt(kv[1])) {
        (Some(level), Some(count)) => out.push((level, count))
        _ => ()
      }
    }
  }
  out
}

///|
fn load_schema_file(path : String) -> Result[@kiln.Schema, String] {
  let src = @fs.read_file_to_string(path) catch {
    _ => return Err("无法读取文件：\{path}")
  }
  @kiln.load_schema(src)
}

///|
fn ensure_dir(path : String) -> Unit {
  try {
    if !@fs.path_exists(path) {
      @fs.create_dir(path)
    }
  } catch {
    _ => ()
  }
}

///|
fn save(path : String, content : String) -> Bool {
  try {
    @fs.write_string_to_file(path, content)
    true
  } catch {
    _ => false
  }
}

///|
/// Independent re-check: rebuild the polynomial from the certificate and run the
/// verifier again. This is the same path a third party would take.
fn reverify(pool : @kiln.Pool) -> (Int32, Int32) {
  let mut ok = 0
  let mut bad = 0
  for item in pool.items {
    let cert = item.certificate
    let verdict = match item.family {
      FQuadratic => {
        let p = @kiln.rebuild_quadratic(cert)
        let (v, _) = @kiln.verify_quadratic(p, item.answers)
        v
      }
      FRational => {
        let y = cert.payload
        let num = @kiln.Poly::new([y[0], y[1]])
        let den = @kiln.Poly::new([y[2], y[3]])
        let (v, _) = @kiln.verify_rational(num, den, y[4], item.answers)
        v
      }
    }
    if verdict.is_well_posed() {
      ok = ok + 1
    } else {
      bad = bad + 1
    }
  }
  (ok, bad)
}

///|
fn print_pool_report(schema : @kiln.Schema, pool : @kiln.Pool) -> Unit {
  println("schema      \{schema.name}")
  println(
    "candidates  \{pool.attempted}  (rejected \{pool.rejected}, duplicates \{pool.duplicates})",
  )
  println("unique      \{pool.size()}")
  println("levels      \{pool.level_histogram()}")
  if pool.rejects.length() > 0 {
    let seen : Array[String] = []
    for r in pool.rejects {
      if !seen.contains(r) {
        seen.push(r)
      }
    }
    println("rejects     \{seen.length()} distinct reason(s)")
    for r in seen {
      println("            - \{r}")
    }
  }
}

///|
fn cmd_pool(argv : Array[String]) -> Unit {
  let path = match flag(argv, "--schema") {
    Some(p) => p
    None => {
      println("缺少 --schema")
      usage()
      return
    }
  }
  let schema = match load_schema_file(path) {
    Ok(s) => s
    Err(e) => {
      println("读入失败：\{e}")
      return
    }
  }
  let limit = flag_int(argv, "--limit", 0)
  let show = flag_int(argv, "--show", 3)
  let pool = @kiln.generate(schema, limit)
  print_pool_report(schema, pool)
  let (ok, bad) = reverify(pool)
  println("reverify    \{ok} ok, \{bad} failed")
  if show > 0 {
    println("")
    println("sample:")
    let mut n = 0
    for item in pool.items {
      if n < show {
        println(
          "  \{n + 1}. [\{item.level_label()}] \{item.question}    → \{item.answer_text()}",
        )
        n = n + 1
      }
    }
  }
}

///|
fn cmd_check(argv : Array[String]) -> Unit {
  let path = match flag(argv, "--schema") {
    Some(p) => p
    None => {
      println("缺少 --schema")
      usage()
      return
    }
  }
  let schema = match load_schema_file(path) {
    Ok(s) => s
    Err(e) => {
      println("读入失败：\{e}")
      return
    }
  }
  let pool = @kiln.generate(schema, 0)
  print_pool_report(schema, pool)
  let (ok, bad) = reverify(pool)
  println("reverify    \{ok} ok, \{bad} failed")
  if has_flag(argv, "--verbose") {
    println("")
    for item in pool.items {
      println(
        "\{item.fingerprint}  [\{item.level_label()}]  \{item.answer_text()}",
      )
    }
  }
  if bad > 0 {
    println("结果        存在未通过复核的题目")
  } else {
    println("结果        全部通过独立复核")
  }
}

///|
fn cmd_gen(argv : Array[String]) -> Unit {
  let path = match flag(argv, "--schema") {
    Some(p) => p
    None => {
      println("缺少 --schema")
      usage()
      return
    }
  }
  let schema = match load_schema_file(path) {
    Ok(s) => s
    Err(e) => {
      println("读入失败：\{e}")
      return
    }
  }
  let seed = flag_int(argv, "--seed", 42)
  let count = flag_int(argv, "--count", 10)
  let out = match flag(argv, "--out") {
    Some(d) => d
    None => "out"
  }
  let title = match flag(argv, "--title") {
    Some(t) => t
    None => if schema.title == "" { schema.name } else { schema.title }
  }
  let levels = match flag(argv, "--levels") {
    Some(s) => parse_levels(s)
    None => []
  }
  let max_per_tag = flag_int(argv, "--max-per-tag", 3)
  let pool = @kiln.generate(schema, 0)
  print_pool_report(schema, pool)
  let bp = if levels.length() > 0 {
    @kiln.Blueprint::with_levels(levels, seed).capping(max_per_tag)
  } else {
    @kiln.Blueprint::new(count, seed).capping(max_per_tag)
  }
  let paper = match @kiln.assemble(pool, schema.name, bp) {
    Ok(p) => p
    Err(e) => {
      println("")
      println("组卷失败：\{e}")
      println("提示：放宽题池 domain 或降低该难度配额。")
      return
    }
  }
  let (ok, bad) = reverify(pool)
  println("")
  println(
    "paper       \{paper.size()} 题 · 结构 \{paper.request} · seed \{seed}",
  )
  println("reverify    \{ok} ok, \{bad} failed")
  ensure_dir(out)
  let ws = @kiln.render_worksheet(paper, title)
  let key = @kiln.render_answer_key(paper, title)
  let md = @kiln.render_markdown(paper, title)
  let f1 = save("\{out}/worksheet.html", ws)
  let f2 = save("\{out}/answers.html", key)
  let f3 = save("\{out}/worksheet.md", md)
  println("")
  println("\{if f1 { "ok  " } else { "fail" }} \{out}/worksheet.html")
  println("\{if f2 { "ok  " } else { "fail" }} \{out}/answers.html")
  println("\{if f3 { "ok  " } else { "fail" }} \{out}/worksheet.md")
  println("")
  for i, item in paper.items {
    println("\{i + 1}. [\{item.level_label()}] \{item.question}")
  }
}

///|
/// Find the verb anywhere in `argv`.
///
/// The wasm runner passes only the user arguments, while the JS runner passes
/// `node`, the script path and then the arguments. Scanning for the verb keeps
/// the same binary usable on both without backend-specific branching.
fn find_cmd(argv : Array[String]) -> String {
  let mut i = 0
  while i < argv.length() {
    let a = argv[i]
    if a == "gen" || a == "check" || a == "pool" || a == "help" {
      return a
    }
    i = i + 1
  }
  ""
}

///|
fn main {
  let argv = @env.args()
  let cmd = find_cmd(argv)
  if cmd == "gen" {
    cmd_gen(argv)
  } else if cmd == "check" {
    cmd_check(argv)
  } else if cmd == "pool" {
    cmd_pool(argv)
  } else {
    usage()
  }
}

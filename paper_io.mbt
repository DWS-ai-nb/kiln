///|
/// The paper file: a self-contained, verifiable record of a generated sheet.
///
/// This is what turns "the generator checked itself" into "anyone can check it".
/// The file carries, for every item, the exact payload the family's verifier
/// consumes — no schema, no source code, no trust required.
///
/// Two deliberate choices:
///
///   * **All numbers are strings.** JSON numbers are doubles; a fraction like
///     `1/3` would lose exactness, and a large integer would silently round.
///   * **The payload is opaque and family-defined.** The format does not try to
///     be a general math AST. Each family documents its own arity, which keeps
///     the verifier small and the format honest.
const PAPER_FORMAT : String = "kiln.paper/1"

///|
pub(all) struct ItemFile {
  question : String
  answers : Array[Rat]
  level : Int32
  fingerprint : String
  family : Family
  payload : Array[Rat]
  tags : Array[String]
}

///|
pub(all) struct PaperFile {
  format : String
  schema_name : String
  title : String
  seed : Int32
  items : Array[ItemFile]
}

///|
pub(all) struct VerifyReport {
  total : Int32
  passed : Int32
  failures : Array[String]
}

///|
pub fn VerifyReport::all_passed(self : VerifyReport) -> Bool {
  self.failures.length() == 0
}

///|
fn rats_to_json(values : Array[Rat]) -> Json {
  let out : Array[Json] = []
  for v in values {
    out.push(Json::string(v.to_string()))
  }
  Json::array(out)
}

///|
pub fn paper_to_json(paper : Paper, title : String) -> Json {
  let items : Array[Json] = []
  for it in paper.items {
    let obj : Map[String, Json] = Map([])
    obj["question"] = Json::string(it.question)
    obj["answers"] = rats_to_json(it.answers)
    obj["level"] = Json::number(it.level.to_double())
    obj["fingerprint"] = Json::string(it.fingerprint)
    obj["family"] = Json::string(it.family.to_string())
    obj["payload"] = rats_to_json(it.certificate.payload)
    obj["tags"] = Json::array(it.tags.map(fn(t) { Json::string(t) }))
    items.push(Json::object(obj))
  }
  let root : Map[String, Json] = Map([])
  root["format"] = Json::string(PAPER_FORMAT)
  root["schema"] = Json::string(paper.schema_name)
  root["title"] = Json::string(title)
  root["seed"] = Json::number(paper.seed.to_double())
  root["items"] = Json::array(items)
  Json::object(root)
}

///|
pub fn paper_to_json_string(paper : Paper, title : String) -> String {
  paper_to_json(paper, title).stringify(indent=2)
}

///|
priv suberror PaperError {
  PaperError(String)
}

///|
fn field_json(obj : Json, key : String) -> Json? {
  if obj is Object(map) {
    map.get(key)
  } else {
    None
  }
}

///|
fn as_text(j : Json) -> String? {
  if j is String(s) {
    Some(s)
  } else {
    None
  }
}

///|
fn as_number(j : Json) -> Double? {
  if j is Number(d, ..) {
    Some(d)
  } else {
    None
  }
}

///|
fn as_items(j : Json) -> Array[Json]? {
  if j is Array(xs) {
    Some(xs)
  } else {
    None
  }
}

///|
fn field_string(obj : Json, key : String) -> String raise PaperError {
  match field_json(obj, key) {
    Some(v) =>
      match as_text(v) {
        Some(s) => s
        None => raise PaperError("字段 '\{key}' 应为字符串")
      }
    None => raise PaperError("缺少字段 '\{key}'")
  }
}

///|
fn field_int(obj : Json, key : String) -> Int32 raise PaperError {
  match field_json(obj, key) {
    Some(v) =>
      match as_number(v) {
        Some(d) => d.to_int()
        None => raise PaperError("字段 '\{key}' 应为数字")
      }
    None => raise PaperError("缺少字段 '\{key}'")
  }
}

///|
fn field_array(obj : Json, key : String) -> Array[Json] raise PaperError {
  match field_json(obj, key) {
    Some(v) =>
      match as_items(v) {
        Some(a) => a
        None => raise PaperError("字段 '\{key}' 应为数组")
      }
    None => raise PaperError("缺少字段 '\{key}'")
  }
}

///|
fn field_strings(obj : Json, key : String) -> Array[String] raise PaperError {
  let out : Array[String] = []
  for entry in field_array(obj, key) {
    match as_text(entry) {
      Some(t) => out.push(t)
      None => raise PaperError("字段 '\{key}' 的元素应为字符串")
    }
  }
  out
}

///|
fn field_rats(obj : Json, key : String) -> Array[Rat] raise PaperError {
  let out : Array[Rat] = []
  for entry in field_array(obj, key) {
    match as_text(entry) {
      Some(s) =>
        match parse_rat(s) {
          Some(r) => out.push(r)
          None =>
            raise PaperError("字段 '\{key}' 含无法解析的数：\{s}")
        }
      None => raise PaperError("字段 '\{key}' 的元素应为字符串")
    }
  }
  out
}

///|
pub fn paper_from_json_string(src : String) -> Result[PaperFile, String] {
  try {
    let root = @json.parse(src)
    let format = field_string(root, "format")
    if format != PAPER_FORMAT {
      raise PaperError(
        "格式版本不匹配：读到 \{format}，本工具支持 \{PAPER_FORMAT}",
      )
    }
    let items : Array[ItemFile] = []
    for entry in field_array(root, "items") {
      let family_text = field_string(entry, "family")
      let family = match Family::from_string(family_text) {
        Some(f) => f
        None => raise PaperError("未知验证族：\{family_text}")
      }
      items.push({
        question: field_string(entry, "question"),
        answers: field_rats(entry, "answers"),
        level: field_int(entry, "level"),
        fingerprint: field_string(entry, "fingerprint"),
        family,
        payload: field_rats(entry, "payload"),
        tags: field_strings(entry, "tags"),
      })
    }
    Ok({
      format,
      schema_name: field_string(root, "schema"),
      title: field_string(root, "title"),
      seed: field_int(root, "seed"),
      items,
    })
  } catch {
    PaperError(msg) => Err(msg)
    _ => Err("不是合法的 JSON")
  }
}

///|
/// Re-check one item from its payload alone. This is the function a third party
/// implements in their own language; see `docs/CERTIFICATE.md`.
pub fn verify_item_file(item : ItemFile) -> Verdict {
  match item.family {
    FQuadratic => {
      if item.payload.length() != 3 {
        return AnswerMismatch(
          "quadratic payload 应为 3 个数，实际 \{item.payload.length()}",
        )
      }
      let p = Poly::new([item.payload[2], item.payload[1], item.payload[0]])
      let (verdict, _) = verify_quadratic(p, item.answers)
      verdict
    }
    FRational => {
      if item.payload.length() != 5 {
        return AnswerMismatch(
          "rational payload 应为 5 个数，实际 \{item.payload.length()}",
        )
      }
      let num = Poly::new([item.payload[0], item.payload[1]])
      let den = Poly::new([item.payload[2], item.payload[3]])
      let (verdict, _) = verify_rational(
        num,
        den,
        item.payload[4],
        item.answers,
      )
      verdict
    }
  }
}

///|
/// Verify a whole paper. Failures carry the item index and the verdict, so a
/// tampered file points at exactly which item stopped adding up.
pub fn verify_paper_file(pf : PaperFile) -> VerifyReport {
  let failures : Array[String] = []
  let mut passed = 0
  for i, item in pf.items {
    let verdict = verify_item_file(item)
    if verdict.is_well_posed() {
      passed = passed + 1
    } else {
      failures.push(
        "第 \{i + 1} 题：\{verdict.to_string()}（\{item.question}）",
      )
    }
  }
  { total: pf.items.length(), passed, failures, }
}

///|
test "a paper round-trips through JSON and still verifies" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(e) => abort(e)
  }
  let pool = generate(schema, 0)
  let paper = match assemble(pool, schema.name, Blueprint::new(6, 9)) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let text = paper_to_json_string(paper, "测试卷")
  let parsed = match paper_from_json_string(text) {
    Ok(pf) => pf
    Err(e) => abort("解析失败：\{e}")
  }
  inspect(parsed.items.length(), content="6")
  inspect(parsed.schema_name, content="quadratic_int_roots")
  let report = verify_paper_file(parsed)
  inspect(report.total, content="6")
  inspect(report.passed, content="6")
  inspect(report.all_passed(), content="true")
}

///|
test "a tampered payload is caught" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(e) => abort(e)
  }
  let pool = generate(schema, 0)
  let paper = match assemble(pool, schema.name, Blueprint::new(3, 4)) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let parsed = match
    paper_from_json_string(paper_to_json_string(paper, "测试卷")) {
    Ok(pf) => pf
    Err(e) => abort(e)
  }
  // Flip the constant term of the first item: the answers no longer match.
  let payload = parsed.items[0].payload
  payload[0] = payload[0].add(rat_one())
  let report = verify_paper_file(parsed)
  inspect(report.passed, content="2")
  inspect(report.failures.length(), content="1")
  inspect(report.failures[0].contains("第 1 题"), content="true")
}

///|
test "a tampered answer is caught" {
  let schema = match load_schema(RATIONAL_SCHEMA) {
    Ok(s) => s
    Err(e) => abort(e)
  }
  let pool = generate(schema, 0)
  let paper = match assemble(pool, schema.name, Blueprint::new(3, 4)) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let parsed = match
    paper_from_json_string(paper_to_json_string(paper, "分式")) {
    Ok(pf) => pf
    Err(e) => abort(e)
  }
  parsed.items[0].answers[0] = parsed.items[0].answers[0].add(rat_one())
  let report = verify_paper_file(parsed)
  inspect(report.all_passed(), content="false")
}

///|
test "malformed files are rejected with a reason" {
  match paper_from_json_string("{\"format\":\"kiln.paper/1\"}") {
    Ok(_) => abort("expected an error")
    Err(e) => inspect(e.contains("缺少字段"), content="true")
  }
  match paper_from_json_string("not json at all") {
    Ok(_) => abort("expected an error")
    Err(e) => inspect(e.contains("JSON"), content="true")
  }
  match paper_from_json_string("{\"format\":\"kiln.paper/99\"}") {
    Ok(_) => abort("expected an error")
    Err(e) => inspect(e.contains("格式版本"), content="true")
  }
}

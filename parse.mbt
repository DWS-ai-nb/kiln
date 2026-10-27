///|
/// Recursive-descent parser for `.kiln` schema files.
///
/// Errors are reported as `line N: ...` strings and always point at the token
/// that broke the grammar, never at an internal function.
pub suberror SchemaError {
  SchemaError(String)
}

///|
priv struct Parser {
  toks : Array[Token]
  mut pos : Int32
}

///|
fn Parser::new(toks : Array[Token]) -> Parser {
  { toks, pos: 0, }
}

///|
fn Parser::peek(self : Parser) -> Token {
  if self.pos >= self.toks.length() {
    self.toks[self.toks.length() - 1]
  } else {
    self.toks[self.pos]
  }
}

///|
fn Parser::advance(self : Parser) -> Token {
  let t = self.peek()
  if self.pos < self.toks.length() - 1 {
    self.pos = self.pos + 1
  }
  t
}

///|
fn Parser::at_eof(self : Parser) -> Bool {
  match self.peek().kind {
    TEof => true
    _ => false
  }
}

///|
fn Parser::at_punct(self : Parser, p : String) -> Bool {
  match self.peek().kind {
    TPunct(q) => q == p
    _ => false
  }
}

///|
fn Parser::at_ident(self : Parser, name : String) -> Bool {
  match self.peek().kind {
    TIdent(s) => s == name
    _ => false
  }
}

///|
fn Parser::eat_punct(self : Parser, p : String) -> Bool {
  if self.at_punct(p) {
    let _ = self.advance()
    true
  } else {
    false
  }
}

///|
fn Parser::expect_punct(self : Parser, p : String) -> Unit raise SchemaError {
  if !self.eat_punct(p) {
    let t = self.peek()
    raise SchemaError(
      "line \{t.line}: expected '\{p}' but found \{describe(t.kind)}",
    )
  }
}

///|
fn Parser::expect_ident(self : Parser) -> String raise SchemaError {
  let t = self.advance()
  match t.kind {
    TIdent(s) => s
    k =>
      raise SchemaError(
        "line \{t.line}: expected an identifier but found \{describe(k)}",
      )
  }
}

///|
fn Parser::expect_string(self : Parser) -> String raise SchemaError {
  let t = self.advance()
  match t.kind {
    TStr(s) => s
    k =>
      raise SchemaError(
        "line \{t.line}: expected a string but found \{describe(k)}",
      )
  }
}

///|
fn describe(k : Tok) -> String {
  match k {
    TIdent(s) => "identifier '\{s}'"
    TNum(n) => "number \{n}"
    TStr(_) => "string"
    TPunct(p) => "'\{p}'"
    TBad(c) => "unexpected character '\{c}'"
    TEof => "end of file"
  }
}

///|
fn Parser::parse_family(self : Parser) -> Family raise SchemaError {
  let t = self.peek()
  let name = self.expect_ident()
  match name {
    "quadratic" => FQuadratic
    "rational" => FRational
    other =>
      raise SchemaError(
        "line \{t.line}: unknown family '\{other}' (supported: quadratic, rational)",
      )
  }
}

///|
fn Parser::parse_domain(self : Parser) -> (Int32, Int32) raise SchemaError {
  self.expect_punct("[")
  let lo = self.parse_signed_int()
  self.expect_punct(",")
  let hi = self.parse_signed_int()
  self.expect_punct("]")
  if lo > hi {
    raise SchemaError("empty domain [\{lo}, \{hi}]: lower bound exceeds upper")
  }
  (lo, hi)
}

///|
fn Parser::parse_signed_int(self : Parser) -> Int32 raise SchemaError {
  let t = self.peek()
  let neg = self.eat_punct("-")
  let n = self.advance()
  match n.kind {
    TNum(v) => if neg { (-v).to_int() } else { v.to_int() }
    k =>
      raise SchemaError(
        "line \{t.line}: expected an integer bound but found \{describe(k)}",
      )
  }
}

///|
fn Parser::parse_vardecls(self : Parser) -> Array[VarDecl] raise SchemaError {
  self.expect_punct("{")
  let out : Array[VarDecl] = []
  while !self.at_punct("}") {
    if self.at_eof() {
      raise SchemaError("unexpected end of file inside a block")
    }
    let name = self.expect_ident()
    self.expect_punct(":")
    if self.at_ident("int") {
      let _ = self.advance()
      if !self.at_ident("in") {
        raise SchemaError("line \{self.peek().line}: expected 'in' after 'int'")
      }
      let _ = self.advance()
      let (lo, hi) = self.parse_domain()
      out.push({ name, domain: Some((lo, hi)), expr: None, })
    } else {
      let e = self.parse_expr()
      out.push({ name, domain: None, expr: Some(e), })
    }
    let _ = self.eat_punct(",")
  }
  self.expect_punct("}")
  out
}

///|
fn Parser::parse_requires(self : Parser) -> Array[Require] raise SchemaError {
  self.expect_punct("{")
  let out : Array[Require] = []
  while !self.at_punct("}") {
    if self.at_eof() {
      raise SchemaError("unexpected end of file inside a require block")
    }
    let left = self.parse_expr()
    let op = self.parse_cmp()
    let right = self.parse_expr()
    out.push({ left, op, right, })
    let _ = self.eat_punct(",")
  }
  self.expect_punct("}")
  out
}

///|
fn Parser::parse_cmp(self : Parser) -> CmpOp raise SchemaError {
  let t = self.advance()
  match t.kind {
    TPunct("<") => CLt
    TPunct("<=") => CLe
    TPunct(">") => CGt
    TPunct(">=") => CGe
    TPunct("==") => CEq
    TPunct("!=") => CNe
    k =>
      raise SchemaError(
        "line \{t.line}: expected a comparison operator but found \{describe(k)}",
      )
  }
}

///|
fn Parser::parse_expr(self : Parser) -> Expr raise SchemaError {
  self.parse_add()
}

///|
fn Parser::parse_add(self : Parser) -> Expr raise SchemaError {
  let mut left = self.parse_mul()
  let mut go = true
  while go {
    if self.eat_punct("+") {
      left = EAdd(left, self.parse_mul())
    } else if self.eat_punct("-") {
      left = ESub(left, self.parse_mul())
    } else {
      go = false
    }
  }
  left
}

///|
fn Parser::parse_mul(self : Parser) -> Expr raise SchemaError {
  let mut left = self.parse_unary()
  let mut go = true
  while go {
    if self.eat_punct("*") {
      left = EMul(left, self.parse_unary())
    } else if self.eat_punct("/") {
      left = EDiv(left, self.parse_unary())
    } else {
      go = false
    }
  }
  left
}

///|
fn Parser::parse_unary(self : Parser) -> Expr raise SchemaError {
  if self.eat_punct("-") {
    ENeg(self.parse_unary())
  } else {
    self.parse_pow()
  }
}

///|
fn Parser::parse_pow(self : Parser) -> Expr raise SchemaError {
  let base = self.parse_atom()
  if self.eat_punct("^") {
    let t = self.peek()
    let neg = self.eat_punct("-")
    let n = self.advance()
    match n.kind {
      TNum(v) =>
        if neg {
          raise SchemaError(
            "line \{t.line}: negative exponents are not allowed",
          )
        } else {
          EPow(base, v.to_int())
        }
      k =>
        raise SchemaError(
          "line \{t.line}: expected an integer exponent but found \{describe(k)}",
        )
    }
  } else {
    base
  }
}

///|
fn Parser::parse_atom(self : Parser) -> Expr raise SchemaError {
  let t = self.advance()
  match t.kind {
    TNum(v) => ELit(rat_int(v))
    TIdent(s) => EVar(s)
    TPunct("(") => {
      let e = self.parse_expr()
      self.expect_punct(")")
      e
    }
    k =>
      raise SchemaError(
        "line \{t.line}: expected a number, variable or '(' but found \{describe(k)}",
      )
  }
}

///|
fn Parser::parse_schema(self : Parser) -> Schema raise SchemaError {
  let mut name = ""
  let mut family = FQuadratic
  let mut title = ""
  let mut answers : Array[VarDecl] = []
  let mut params : Array[VarDecl] = []
  let mut requires : Array[Require] = []
  let mut ask = ""
  while true {
    let t = self.peek()
    match t.kind {
      TEof => break
      TIdent(kw) =>
        if kw == "schema" {
          let _ = self.advance()
          name = self.expect_string()
        } else if kw == "family" {
          let _ = self.advance()
          family = self.parse_family()
        } else if kw == "title" {
          let _ = self.advance()
          title = self.expect_string()
        } else if kw == "answer" {
          let _ = self.advance()
          answers = self.parse_vardecls()
        } else if kw == "param" {
          let _ = self.advance()
          params = self.parse_vardecls()
        } else if kw == "require" {
          let _ = self.advance()
          requires = self.parse_requires()
        } else if kw == "ask" {
          let _ = self.advance()
          ask = self.expect_string()
        } else {
          raise SchemaError("line \{t.line}: unexpected keyword '\{kw}'")
        }
      k => raise SchemaError("line \{t.line}: unexpected \{describe(k)}")
    }
  }
  { name, family, title, answers, params, requires, ask, }
}

///|
/// Load and validate a schema. Validation is separate from parsing so that a
/// malformed *program* (undefined variable, no answers, duplicate name) is
/// reported as clearly as a malformed *file*.
pub fn load_schema(src : String) -> Result[Schema, String] {
  let parsed : Result[Schema, String] = Ok(
    Parser::new(tokenize(src)).parse_schema(),
  ) catch {
    SchemaError(msg) => Err(msg)
  }
  match parsed {
    Err(e) => Err(e)
    Ok(s) =>
      match validate(s) {
        Some(e) => Err(e)
        None => Ok(s)
      }
  }
}

///|
fn validate(s : Schema) -> String? {
  if s.name == "" {
    return Some("schema: missing `schema \"name\"` header")
  }
  if s.answers.length() == 0 {
    return Some("schema '\{s.name}': at least one answer variable is required")
  }
  let seen : Array[String] = []
  for v in s.answers {
    if contains_str(seen, v.name) {
      return Some("schema '\{s.name}': duplicate variable '\{v.name}'")
    }
    seen.push(v.name)
    if v.domain is None {
      return Some(
        "schema '\{s.name}': answer variable '\{v.name}' needs a domain, e.g. `[1, 9]`",
      )
    }
  }
  for v in s.params {
    if contains_str(seen, v.name) {
      return Some("schema '\{s.name}': duplicate variable '\{v.name}'")
    }
    match v.expr {
      Some(e) =>
        for used in e.vars() {
          if !contains_str(seen, used) {
            return Some(
              "schema '\{s.name}': '\{v.name}' refers to undefined variable '\{used}'",
            )
          }
        }
      None => ()
    }
    seen.push(v.name)
  }
  for r in s.requires {
    for side in [r.left, r.right] {
      for used in side.vars() {
        if !contains_str(seen, used) {
          return Some(
            "schema '\{s.name}': require clause refers to undefined variable '\{used}'",
          )
        }
      }
    }
  }
  if s.ask == "" {
    return Some("schema '\{s.name}': missing `ask \"...\"` template")
  }
  None
}

///|
fn contains_str(xs : Array[String], x : String) -> Bool {
  let mut found = false
  for y in xs {
    if y == x {
      found = true
    }
  }
  found
}

///|
const SAMPLE_SCHEMA : String =
  #|schema "quadratic_int_roots"
  #|family quadratic
  #|title "一元二次方程（整数根）"
  #|
  #|answer {
  #|  r1: int in [-9, 9]
  #|  r2: int in [-9, 9]
  #|}
  #|
  #|param {
  #|  a: 1
  #|  b: -(a * (r1 + r2))
  #|  c: a * r1 * r2
  #|}
  #|
  #|require {
  #|  r1 < r2
  #|}
  #|
  #|ask "解方程 {poly} = 0"
  #|

///|
test "parse the sample schema" {
  match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => {
      inspect(s.name, content="quadratic_int_roots")
      inspect(s.answers.length(), content="2")
      inspect(s.params.length(), content="3")
      inspect(s.requires.length(), content="1")
      inspect(s.ask, content="解方程 {poly} = 0")
    }
    Err(e) => abort("unexpected error: \{e}")
  }
}

///|
test "parse rejects an undefined variable" {
  let src = "schema \"s\"\nfamily quadratic\nanswer {\n x: int in [1, 2]\n}\nparam {\n y: x + z\n}\nask \"{poly}\"\n"
  match load_schema(src) {
    Ok(_) => abort("expected a validation error")
    Err(e) => inspect(e.contains("undefined variable"), content="true")
  }
}

///|
test "parse rejects an empty domain" {
  let src = "schema \"s\"\nfamily quadratic\nanswer {\n x: int in [5, 2]\n}\nask \"{poly}\"\n"
  match load_schema(src) {
    Ok(_) => abort("expected an error")
    Err(e) => inspect(e.contains("empty domain"), content="true")
  }
}

///|
test "parse reports the line of a syntax error" {
  let src = "schema \"s\"\nfamily quadratic\nanswer {\n x: int in [1, 2\n}\n"
  match load_schema(src) {
    Ok(_) => abort("expected an error")
    Err(e) =>
      inspect(e.contains("line 5") || e.contains("line 4"), content="true")
  }
}

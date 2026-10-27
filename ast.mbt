///|
/// Abstract syntax for the `.kiln` schema language.
///
/// The language is intentionally tiny: it can enumerate answer shapes, derive
/// parameters from them, and state side conditions. Anything that needs real
/// mathematics (solving, verifying) lives in the engine, not in the schema.
pub enum Expr {
  ELit(Rat)
  EVar(String)
  ENeg(Expr)
  EAdd(Expr, Expr)
  ESub(Expr, Expr)
  EMul(Expr, Expr)
  EDiv(Expr, Expr)
  EPow(Expr, Int32)
}

///|
pub enum CmpOp {
  CLt
  CLe
  CGt
  CGe
  CEq
  CNe
}

///|
pub struct Require {
  left : Expr
  op : CmpOp
  right : Expr
}

///|
/// A declared variable is either *enumerated* over an integer interval or
/// *derived* from previously bound variables.
pub struct VarDecl {
  name : String
  domain : (Int32, Int32)?
  expr : Expr?
}

///|
pub enum Family {
  FQuadratic
  FRational
}

///|
pub(all) struct Schema {
  name : String
  family : Family
  title : String
  answers : Array[VarDecl]
  params : Array[VarDecl]
  requires : Array[Require]
  ask : String
}

///|
pub fn Expr::eval(self : Expr, env : Map[String, Rat]) -> Rat? {
  match self {
    ELit(r) => Some(r)
    EVar(n) =>
      match env.get(n) {
        Some(v) => Some(v)
        None => None
      }
    ENeg(e) =>
      match e.eval(env) {
        Some(v) => Some(v.neg())
        None => None
      }
    EAdd(a, b) =>
      match (a.eval(env), b.eval(env)) {
        (Some(x), Some(y)) => Some(x.add(y))
        _ => None
      }
    ESub(a, b) =>
      match (a.eval(env), b.eval(env)) {
        (Some(x), Some(y)) => Some(x.sub(y))
        _ => None
      }
    EMul(a, b) =>
      match (a.eval(env), b.eval(env)) {
        (Some(x), Some(y)) => Some(x.mul(y))
        _ => None
      }
    EDiv(a, b) =>
      match (a.eval(env), b.eval(env)) {
        (Some(x), Some(y)) => if y.is_zero() { None } else { Some(x.div(y)) }
        _ => None
      }
    EPow(a, n) =>
      match a.eval(env) {
        Some(x) => Some(x.pow(n))
        None => None
      }
  }
}

///|
pub fn Expr::vars(self : Expr) -> Array[String] {
  let out : Array[String] = []
  fn walk(e : Expr, acc : Array[String]) {
    match e {
      ELit(_) => ()
      EVar(n) => acc.push(n)
      ENeg(a) => walk(a, acc)
      EAdd(a, b) | ESub(a, b) | EMul(a, b) | EDiv(a, b) => {
        walk(a, acc)
        walk(b, acc)
      }
      EPow(a, _) => walk(a, acc)
    }
  }
  walk(self, out)
  out
}

///|
pub fn Expr::to_string(self : Expr) -> String {
  match self {
    ELit(r) => r.to_string()
    EVar(n) => n
    ENeg(e) => "-\{e.to_string()}"
    EAdd(a, b) => "(\{a.to_string()} + \{b.to_string()})"
    ESub(a, b) => "(\{a.to_string()} - \{b.to_string()})"
    EMul(a, b) => "(\{a.to_string()} * \{b.to_string()})"
    EDiv(a, b) => "(\{a.to_string()} / \{b.to_string()})"
    EPow(a, n) => "\{a.to_string()}^\{n}"
  }
}

///|
pub fn CmpOp::to_string(self : CmpOp) -> String {
  match self {
    CLt => "<"
    CLe => "<="
    CGt => ">"
    CGe => ">="
    CEq => "=="
    CNe => "!="
  }
}

///|
pub fn CmpOp::holds(self : CmpOp, a : Rat, b : Rat) -> Bool {
  let c = a.compare(b)
  match self {
    CLt => c < 0
    CLe => c <= 0
    CGt => c > 0
    CGe => c >= 0
    CEq => c == 0
    CNe => c != 0
  }
}

///|
/// `None` means the clause is undefined at this point (a subexpression divided
/// by zero), which the generator treats as "outside the domain", not as an
/// error.
pub fn Require::check(self : Require, env : Map[String, Rat]) -> Bool? {
  match (self.left.eval(env), self.right.eval(env)) {
    (Some(a), Some(b)) => Some(self.op.holds(a, b))
    _ => None
  }
}

///|
pub fn Family::to_string(self : Family) -> String {
  match self {
    FQuadratic => "quadratic"
    FRational => "rational"
  }
}

///|
test "expr evaluates exactly" {
  let env : Map[String, Rat] = Map([])
  env["a"] = rat_int(2L)
  env["b"] = rat_int(3L)
  let e = EAdd(EMul(EVar("a"), EVar("b")), ELit(rat(1L, 2L)))
  match e.eval(env) {
    Some(v) => inspect(v.to_string(), content="13/2")
    None => abort("expected a value")
  }
}

///|
test "division by zero yields none, not a crash" {
  let env : Map[String, Rat] = Map([])
  env["a"] = rat_int(0L)
  let e = EDiv(ELit(rat_one()), EVar("a"))
  match e.eval(env) {
    Some(v) => abort("expected undefined, got \{v.to_string()}")
    None => inspect("undefined", content="undefined")
  }
}

///|
test "expr collects variables" {
  let e = EAdd(EVar("x"), EMul(EVar("y"), EVar("x")))
  inspect(e.vars().length(), content="3")
}

///|
test "compare operators use exact ordering" {
  inspect(CLt.holds(rat(1L, 3L), rat(1L, 2L)), content="true")
  inspect(CEq.holds(rat(2L, 4L), rat(1L, 2L)), content="true")
  inspect(CNe.holds(rat(1L, 2L), rat(1L, 2L)), content="false")
}

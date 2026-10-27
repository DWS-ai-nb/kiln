///|
/// Tokenizer for the `.kiln` schema language.
///
/// The lexer never fails. Unrecognized characters become `TBad` tokens and the
/// parser turns the first one it meets into a positioned error message, so a
/// typo in a schema file always points at a line instead of a stack trace.
pub enum Tok {
  TIdent(String)
  TNum(Int64)
  TStr(String)
  TPunct(String)
  TBad(Char)
  TEof
}

///|
pub struct Token {
  kind : Tok
  line : Int32
}

///|
fn is_digit_char(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn is_ident_char(c : Char) -> Bool {
  is_ident_start(c) || is_digit_char(c)
}

///|
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r'
}

///|
pub fn tokenize(src : String) -> Array[Token] {
  let cs = src.to_array()
  let out : Array[Token] = []
  let n = cs.length()
  let mut i = 0
  let mut line = 1
  while i < n {
    let c = cs[i]
    if c == '\n' {
      line = line + 1
      i = i + 1
      continue
    }
    if is_space(c) {
      i = i + 1
      continue
    }
    if c == '#' {
      while i < n && cs[i] != '\n' {
        i = i + 1
      }
      continue
    }
    if c == '"' {
      let sb = StringBuilder()
      i = i + 1
      let mut closed = false
      while i < n && !closed {
        let d = cs[i]
        if d == '"' {
          closed = true
          i = i + 1
        } else if d == '\\' && i + 1 < n {
          let e = cs[i + 1]
          if e == 'n' {
            sb.write_char('\n')
          } else if e == 't' {
            sb.write_char('\t')
          } else {
            sb.write_char(e)
          }
          i = i + 2
        } else {
          sb.write_char(d)
          i = i + 1
        }
      }
      out.push({ kind: TStr(sb.to_string()), line, })
      continue
    }
    if is_digit_char(c) {
      let mut value : Int64 = 0L
      while i < n && is_digit_char(cs[i]) {
        value = value * 10L + (cs[i].to_int() - '0'.to_int()).to_int64()
        i = i + 1
      }
      out.push({ kind: TNum(value), line, })
      continue
    }
    if is_ident_start(c) {
      let sb = StringBuilder()
      while i < n && is_ident_char(cs[i]) {
        sb.write_char(cs[i])
        i = i + 1
      }
      out.push({ kind: TIdent(sb.to_string()), line, })
      continue
    }
    // Two-character operators first so that `<=` never lexes as `<` then `=`.
    if i + 1 < n {
      let pair = "\{c}\{cs[i + 1]}"
      if pair == "<=" || pair == ">=" || pair == "==" || pair == "!=" {
        out.push({ kind: TPunct(pair), line, })
        i = i + 2
        continue
      }
    }
    if c == '+' ||
      c == '-' ||
      c == '*' ||
      c == '/' ||
      c == '^' ||
      c == '(' ||
      c == ')' ||
      c == '{' ||
      c == '}' ||
      c == '[' ||
      c == ']' ||
      c == ',' ||
      c == ':' ||
      c == '<' ||
      c == '>' {
      out.push({ kind: TPunct(c.to_string()), line, })
      i = i + 1
      continue
    }
    out.push({ kind: TBad(c), line, })
    i = i + 1
  }
  out.push({ kind: TEof, line, })
  out
}

///|
test "tokenize a small schema fragment" {
  let ts = tokenize("schema \"quad\"\n  a: int in [-3, 5]\n")
  inspect(ts.length(), content="13")
  match ts[0].kind {
    TIdent(s) => inspect(s, content="schema")
    _ => abort("expected ident")
  }
  match ts[1].kind {
    TStr(s) => inspect(s, content="quad")
    _ => abort("expected string")
  }
}

///|
test "tokenize keeps two char operators together" {
  let ts = tokenize("a <= b != c")
  inspect(ts.length(), content="6")
  match ts[1].kind {
    TPunct(p) => inspect(p, content="<=")
    _ => abort("expected <=")
  }
  match ts[3].kind {
    TPunct(p) => inspect(p, content="!=")
    _ => abort("expected !=")
  }
}

///|
test "comments and blank lines do not produce tokens" {
  let ts = tokenize("# hello\n\n  x # trailing\n")
  inspect(ts.length(), content="2")
}

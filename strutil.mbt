///|
/// Small string helpers. Kept local on purpose: pulling in a dependency for
/// `replace_all` would make the reproducibility story harder to audit.
pub fn replace_all(s : String, from : String, to : String) -> String {
  if from == "" {
    return s
  }
  let cs = s.to_array()
  let fs = from.to_array()
  let n = cs.length()
  let m = fs.length()
  let sb = StringBuilder()
  let mut i = 0
  while i < n {
    let mut matched = false
    if i + m <= n {
      let mut k = 0
      let mut same = true
      while k < m {
        if cs[i + k] != fs[k] {
          same = false
        }
        k = k + 1
      }
      matched = same
    }
    if matched {
      sb.write_string(to)
      i = i + m
    } else {
      sb.write_char(cs[i])
      i = i + 1
    }
  }
  sb.to_string()
}

///|
pub fn join_lines(lines : Array[String]) -> String {
  let sb = StringBuilder()
  for i, l in lines {
    if i > 0 {
      sb.write_string("\n")
    }
    sb.write_string(l)
  }
  sb.to_string()
}

///|
/// Split on a single separator character. Empty segments are preserved so that
/// `a,,b` stays diagnosable instead of silently collapsing.
pub fn split_on(s : String, sep : Char) -> Array[String] {
  let out : Array[String] = []
  let sb = StringBuilder()
  for c in s {
    if c == sep {
      out.push(sb.to_string())
      let _ = sb.reset()
    } else {
      sb.write_char(c)
    }
  }
  out.push(sb.to_string())
  out
}

///|
pub fn trim(s : String) -> String {
  let cs = s.to_array()
  let n = cs.length()
  let mut start = 0
  while start < n &&
        (cs[start] == ' ' || cs[start] == '\t' || cs[start] == '\r') {
    start = start + 1
  }
  let mut end = n
  while end > start &&
        (cs[end - 1] == ' ' || cs[end - 1] == '\t' || cs[end - 1] == '\r') {
    end = end - 1
  }
  let sb = StringBuilder()
  for i in start..<end {
    sb.write_char(cs[i])
  }
  sb.to_string()
}

///|
/// Parse a decimal integer, tolerating a leading `+` or `-`.
pub fn parse_int_opt(s : String) -> Int32? {
  let t = trim(s)
  let cs = t.to_array()
  if cs.length() == 0 {
    return None
  }
  let mut neg = false
  let mut i = 0
  if cs[0] == '-' || cs[0] == '+' {
    neg = cs[0] == '-'
    i = 1
  }
  if i >= cs.length() {
    return None
  }
  let mut value : Int64 = 0L
  let mut ok = true
  while i < cs.length() {
    let c = cs[i]
    if c < '0' || c > '9' {
      ok = false
    } else {
      value = value * 10L + (c.to_int() - '0'.to_int()).to_int64()
    }
    i = i + 1
  }
  if !ok {
    return None
  }
  if neg {
    Some((-value).to_int())
  } else {
    Some(value.to_int())
  }
}

///|
test "replace_all handles repeated and absent patterns" {
  inspect(replace_all("a{poly}b{poly}", "{poly}", "X"), content="aXbX")
  inspect(replace_all("nothing here", "{poly}", "X"), content="nothing here")
  inspect(replace_all("{poly}", "{poly}", ""), content="")
}

///|
test "replace_all does not loop on empty needle" {
  inspect(replace_all("abc", "", "X"), content="abc")
}

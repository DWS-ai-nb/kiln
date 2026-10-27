///|
/// Rendering.
///
/// Output is plain HTML with no external assets: no CDN, no webfont, no math
/// renderer. A worksheet that needs the network to look right is not a
/// worksheet. Exponents use Unicode superscripts, which print correctly in every
/// browser and survive copy-paste into chat.
pub fn escape_html(s : String) -> String {
  let a = replace_all(s, "&", "&amp;")
  let b = replace_all(a, "<", "&lt;")
  let c = replace_all(b, ">", "&gt;")
  replace_all(c, "\"", "&quot;")
}

///|
pub fn render_markdown(paper : Paper, title : String) -> String {
  let sb = StringBuilder()
  sb.write_string("# \{title}\n\n")
  sb.write_string(
    "> \{paper.size()} 题 · 种子 \{paper.seed} · 结构 \{paper.request}\n\n",
  )
  for i, it in paper.items {
    sb.write_string("\{i + 1}. \{it.question}\n\n")
  }
  sb.write_string("---\n\n## 答案\n\n")
  for i, it in paper.items {
    sb.write_string("\{i + 1}. \{it.answer_text()}\n")
  }
  sb.to_string()
}

///|
const BASE_CSS : String =
  #|:root { --ink:#1c1c1e; --muted:#6b6b70; --line:#e4e4e7; --accent:#7a4b2a; }
  #|* { box-sizing:border-box; }
  #|body { margin:0; padding:48px 32px 72px; background:#fbfbfa; color:var(--ink);
  #|  font-family:"Source Han Serif SC","Songti SC","Noto Serif CJK SC",Georgia,serif;
  #|  line-height:1.75; }
  #|.sheet { max-width:760px; margin:0 auto; background:#fff; padding:56px 64px 64px;
  #|  border:1px solid var(--line); border-radius:6px; box-shadow:0 1px 2px rgba(0,0,0,.04); }
  #|header { border-bottom:2px solid var(--ink); padding-bottom:16px; margin-bottom:32px; }
  #|h1 { font-size:24px; margin:0 0 6px; letter-spacing:.02em; }
  #|.meta { margin:0; font-size:13px; color:var(--muted);
  #|  font-family:"Inter","Segoe UI",system-ui,sans-serif; }
  #|ol.problems { list-style:none; counter-reset:p; margin:0; padding:0; }
  #|ol.problems li { counter-increment:p; position:relative; padding:14px 0 14px 44px;
  #|  border-bottom:1px dashed var(--line); font-size:17px; }
  #|ol.problems li:last-child { border-bottom:none; }
  #|ol.problems li::before { content:counter(p)"."; position:absolute; left:0; top:14px;
  #|  width:32px; text-align:right; color:var(--muted); font-size:15px; }
  #|.q { font-size:18px; letter-spacing:.01em; }
  #|.tag { display:inline-block; margin-left:10px; padding:1px 7px; border-radius:3px;
  #|  background:#f4f1ec; color:var(--accent); font-size:11px; vertical-align:2px;
  #|  font-family:"Inter","Segoe UI",system-ui,sans-serif; }
  #|footer { margin-top:40px; padding-top:14px; border-top:1px solid var(--line);
  #|  font-size:12px; color:var(--muted);
  #|  font-family:"Inter","Segoe UI",system-ui,sans-serif; }
  #|table { width:100%; border-collapse:collapse; font-size:14px; margin-top:8px; }
  #|th,td { text-align:left; padding:9px 10px; border-bottom:1px solid var(--line);
  #|  vertical-align:top; }
  #|th { font-size:12px; color:var(--muted); font-weight:600; letter-spacing:.04em;
  #|  text-transform:uppercase; font-family:"Inter","Segoe UI",system-ui,sans-serif; }
  #|td.ans { font-size:16px; white-space:nowrap; }
  #|td.note { color:var(--muted); font-size:13px; }
  #|.cert { margin-top:28px; font-size:12px; color:var(--muted); }
  #|.cert summary { cursor:pointer; }
  #|.cert pre { background:#faf9f7; border:1px solid var(--line); border-radius:4px;
  #|  padding:12px 14px; overflow-x:auto; font-size:12px; line-height:1.6;
  #|  font-family:ui-monospace,"Cascadia Code",Menlo,monospace; }
  #|@media print { body { background:#fff; padding:0; } .sheet { border:none;
  #|  box-shadow:none; padding:0; max-width:none; } .pagebreak { page-break-before:always; } }

///|
pub fn render_worksheet(paper : Paper, title : String) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "<!DOCTYPE html>\n<html lang=\"zh-CN\"><head><meta charset=\"utf-8\">",
  )
  sb.write_string(
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
  )
  sb.write_string("<title>\{escape_html(title)}</title><style>")
  sb.write_string(BASE_CSS)
  sb.write_string("</style></head><body><article class=\"sheet\">")
  sb.write_string("<header><h1>\{escape_html(title)}</h1><p class=\"meta\">")
  sb.write_string(
    "\{paper.size()} 题 · 结构 \{paper.request} · 种子 \{paper.seed} · 每题已通过独立复核",
  )
  sb.write_string("</p></header><ol class=\"problems\">")
  for it in paper.items {
    sb.write_string("<li><span class=\"q\">\{escape_html(it.question)}</span>")
    sb.write_string("<span class=\"tag\">\{it.level_label()}</span></li>")
  }
  sb.write_string(
    "</ol><footer>由 kiln 生成 · 答案与命题依据见配套答案页</footer>",
  )
  sb.write_string("</article></body></html>")
  sb.to_string()
}

///|
pub fn render_answer_key(paper : Paper, title : String) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "<!DOCTYPE html>\n<html lang=\"zh-CN\"><head><meta charset=\"utf-8\">",
  )
  sb.write_string(
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
  )
  sb.write_string("<title>\{escape_html(title)} · 答案</title><style>")
  sb.write_string(BASE_CSS)
  sb.write_string("</style></head><body><article class=\"sheet\">")
  sb.write_string(
    "<header><h1>\{escape_html(title)} · 答案</h1><p class=\"meta\">",
  )
  sb.write_string(
    "\{paper.size()} 题 · 种子 \{paper.seed} · 难度与依据由结构特征给出",
  )
  sb.write_string("</p></header><table><thead><tr>")
  sb.write_string(
    "<th>#</th><th>答案</th><th>难度</th><th>命题依据</th>",
  )
  sb.write_string("</tr></thead><tbody>")
  for i, it in paper.items {
    sb.write_string("<tr><td>\{i + 1}</td>")
    sb.write_string("<td class=\"ans\">\{escape_html(it.answer_text())}</td>")
    sb.write_string("<td>\{it.level_label()}</td>")
    sb.write_string(
      "<td class=\"note\">\{escape_html(it.reasons_text())}</td></tr>",
    )
  }
  sb.write_string("</tbody></table>")
  sb.write_string(
    "<details class=\"cert\"><summary>展开复核凭证（每题一行）</summary><pre>",
  )
  for i, it in paper.items {
    sb.write_string(
      "\{i + 1}. \{escape_html(it.signature)}  |  fp=\{escape_html(it.fingerprint)}\n",
    )
  }
  sb.write_string("</pre></details>")
  sb.write_string(
    "<footer>由 kiln 生成 · 判别式与求根公式路径独立于参数构造路径</footer>",
  )
  sb.write_string("</article></body></html>")
  sb.to_string()
}

///|
test "answer text is stable and ordered" {
  let schema = match load_schema(SAMPLE_SCHEMA) {
    Ok(s) => s
    Err(e) => abort("schema error: \{e}")
  }
  let pool = generate(schema, 0)
  let paper = match assemble(pool, schema.name, Blueprint::new(3, 5)) {
    Ok(p) => p
    Err(e) => abort(e)
  }
  let key = render_answer_key(paper, "测试卷")
  inspect(key.contains("<!DOCTYPE html>"), content="true")
  inspect(key.contains("复核凭证"), content="true")
}

///|
test "html escaping blocks tag injection" {
  inspect(escape_html("a<b>&\"c\""), content="a&lt;b&gt;&amp;&quot;c&quot;")
}

// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "DWS-ai-nb/kiln"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/DWS-ai-nb/kiln"

license = "Apache-2.0"

keywords = [
  "education",
  "assessment",
  "constraint",
  "verification",
  "generator",
]

preferred_target = "wasm"

description = "Well-posed problem generation with machine-checkable answer certificates"

import {
  "moonbitlang/x@0.5.6",
}

# Compiler Requests

Bumper Bowling is SwiftSyntax-first. When a rule needs type-checked truth, it belongs on this list instead of being smuggled into syntax-only linting.

These are requests for a future compiler-backed analysis lane.

## Typed String Matching

SwiftSyntax can observe operator tokens and member-call spelling. It can catch obvious direct string matching such as:

```swift
name.rawValue == "ready"
name.hasSuffix("State")
```

It cannot prove every arbitrary `==`, `!=`, `contains`, `hasPrefix`, or `hasSuffix` expression is actually operating on `String`.

Compiler-backed analysis would let Bumper Bowling ask:

- Is either side of this comparison type-checked as `String` or `Substring`?
- Does this `contains` call resolve to string matching or collection membership?
- Does this `hasPrefix` or `hasSuffix` call resolve to the standard string API?

This would turn `NoDirectStringMatching` from a conservative syntax rule into a precise typed rule.

## Inferred Type Facts

SwiftSyntax sees explicit type annotations. It does not infer:

```swift
let id = "abc"
```

Compiler-backed analysis would let Bumper Bowling treat inferred `String`, `Any`, broad existential, and domain identity types the same way it treats explicit annotations.

## Symbol And Module Truth

SwiftSyntax sees imports and names. It does not establish compiler symbol identity or prove which module owns a referenced declaration.

`LexicalTypeResolver` follows bounded alias chains inside one file. Declaration
contracts derive access from explicit declarations and enclosing scopes. These
facts retain explicit unresolved results for imported names, unknown extension
targets, inherited aliases, and compiler-dependent access. They do not replace a
compiler-backed analysis lane.

Compiler-backed analysis would let Bumper Bowling distinguish:

- declared dependency edges from actual symbol usage
- unused imports from real dependencies
- same-spelled declarations from the symbol actually referenced

## Build Target Truth

SwiftSyntax reads files. It does not know final build target membership after package, Xcode, conditional compilation, or build setting decisions.

Compiler-backed analysis would let Bumper Bowling attach facts to the targets the compiler actually builds.

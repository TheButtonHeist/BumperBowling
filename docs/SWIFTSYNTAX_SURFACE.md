# SwiftSyntax access

`SyntaxQuery<Node>` accepts any `SyntaxProtocol` node type. Its matches retain
the concrete node, parsed file snapshot, and source location.

Use query roots for common syntax. Use generic queries for other nodes. Compose
with filters, projections, direct members, descendants, and same-file relations.
Use a custom `SyntaxPattern` or an ordinary visitor when it helps.

`SourceFileContext.syntax` retains SwiftLint’s cached `SourceFileSyntax`.
`SourceFileContext.source` retains the matching source snapshot. Rules do not
call the parser. Native cache eviction does not change a collected match’s tree
or diagnostic location.

Syntax spelling does not establish compiler identity. Extensions, aliases,
qualified names, macro expansion, and indirect calls require explicit policy
choices. SIL, LLVM IR, and compiler integration are outside this product.

See the [authoring guide](RULE_AUTHORING.md) and [worked examples](RULE_RECIPES.md).

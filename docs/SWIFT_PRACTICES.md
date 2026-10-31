# Sources behind the example conventions

Published Swift guidance supplies context. Each rule adds a repository decision;
it does not make that decision an Apple or language requirement.

| Example | Source guidance | Repository decision |
| --- | --- | --- |
| Matching previews | [Apple: adding previews](https://developer.apple.com/documentation/xcode/adding-previews-to-your-interface-files) describes creating a view in a preview macro. | Each selected view must have a same-file preview that constructs it. |
| Explicit coding keys | [Apple: encoding and decoding custom types](https://developer.apple.com/documentation/foundation/encoding-and-decoding-custom-types) explains key cases, renaming, synthesis, and intentional omission. | Selected models with explicit keys must cover their direct stored instance fields. |
| Route registration | This is a project convention, with no claim of an industry mandate. | Each selected route case must have one bare registration across included files. |

Apple permits intentional field omission from `CodingKeys`. A repository that
uses omission should change or omit that example. The rule demonstrates a
direct-member relationship; it is not general Codable correctness advice.

See the [executable recipes](RULE_RECIPES.md) for scope, repair, fixtures, and
syntax limits. The preview fixtures run in the generated starter. The other
two run through the repository’s ordinary consumer-test package.

## Other conventions a repository can choose

The [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/#strive-for-fluent-usage)
discuss consistent mutating and nonmutating operation names.
[Point-Free’s dependencies](https://github.com/pointfreeco/swift-dependencies)
show controllable external dependencies.
The [Swift concurrency migration guide](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/commonproblems/#Manual-Synchronization)
discusses manual synchronization and unchecked sendability.

These are possible future rule subjects, not shipped executable recipes in this
version. Add them only with a concrete repository decision and paired examples.

The compiler checks types and actor isolation. Runtime tests check behavior.
Syntax rules do not replace either. Optionals, loops, mutation, and existentials
have legitimate uses; these examples impose no blanket bans on them.

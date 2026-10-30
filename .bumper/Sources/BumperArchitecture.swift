import BumperBowlingCore

extension ComponentShape {
    static let bumperEngine = ComponentShape {
        MayUse(.foundation)
        DoesNotDependOn(.cli)
        DoesNot(Declare("bumperBowling"), severity: .error)
        // This catches `/.../` regex literals only; NSRegularExpression/Regex(...)
        // are plain calls SwiftSyntax can't tell from any other. SwiftSyntax-first is the rule.
        Requires(DisallowSyntax(.regexLiteralExpr), severity: .error)
        Requires(.explicitDomainSurfaces, .typedIdentity, severity: .warning)
    }

    static let thinCommandAdapter = ComponentShape {
        MayDependOn(.core)
        MayUse(.foundation)
        Requires(.immutableStoredState, .typedIdentity, severity: .error)
    }
}

extension AssertionShape {
    static let bumperGlobal = AssertionShape {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        SourceCoverage(.error)
        AcyclicDeclaredDependencies(.error)
        NoDirectStringMatching(
            .error,
            paths: ["Sources/BumperBowlingCore"],
            except: [
                "Sources/BumperBowlingCore/BumperSyntaxDeclarations.swift",
                "Sources/BumperBowlingCore/BumperSyntaxFacts.swift",
                "Sources/BumperBowlingCore/BumperSyntaxImperative.swift",
                "Sources/BumperBowlingCore/StringMatcher.swift",
            ]
        )
    }
}

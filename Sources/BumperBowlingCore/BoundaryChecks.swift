import SwiftSyntax

/// Select written imports by their root module, including selective imports.
public func imports(_ modules: Set<String>) -> SyntaxQuery<ImportDeclSyntax> {
    SyntaxQuery<ImportDeclSyntax>().filter { match in
        match.node.path.first.map { modules.contains($0.name.text) } ?? false
    }
}

public extension Rules {
    /// Keep selected module imports in a repository-owned boundary.
    static func importOwnership(_ modules: Set<String>, allowed: RuleScope) -> SyntaxCheck {
        forbid(imports(modules), scope: .repository.excluding(allowed)) { match in
            "Import \(match.node.path.first?.name.text ?? "") is outside its allowed boundary. Allowed locations: \(allowed.description). Move the code that needs this import to an allowed location."
        }
    }

    /// Reject selected module imports in the subject scope.
    static func forbiddenImports(_ modules: Set<String>, scope: RuleScope = .repository) -> SyntaxCheck {
        forbid(imports(modules), scope: scope) { match in
            "Import \(match.node.path.first?.name.text ?? "") is forbidden in this scope: \(scope.description). Remove this dependency or move the code outside this scope."
        }
    }

    /// Require exactly one owner for each scanned Swift file, including empty files.
    static func sourceOwnership(_ owners: [RuleScope], scope: RuleScope = .repository) -> SyntaxCheck {
        files(scope: scope.validating(owners)) { file in
            let matches = owners.filter { $0.includes(file) }
            if matches.isEmpty {
                let scopes = owners.isEmpty ? "none" : owners.map(\.description).joined(separator: ", ")
                return [file.failure(at: file.syntax, message: "This file has no source owner. Owner scopes: \(scopes). Move the file into an owner scope or add its intended owner.")]
            }
            guard matches.count > 1 else { return [] }
            let scopes = matches.map(\.description).joined(separator: ", ")
            return [file.failure(at: file.syntax, message: "This file matches \(matches.count) source owners: \(scopes). Narrow these scopes until the file has exactly one owner.")]
        }
    }
}

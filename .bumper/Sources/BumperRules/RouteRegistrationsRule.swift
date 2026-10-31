import BumperBowlingCore
import SwiftSyntax

public struct RouteRegistrationsRule: RepositoryRule {
    public var configuration = RuleSettings<Self>()
    public static let metadata = RuleMetadata(id: "routes.registration", summary: "Each AppRoute case has exactly one bare registration")
    public init() {}

    public struct FileInfo: Sendable {
        let cases: [SyntaxMatch<EnumCaseElementSyntax>]
        let registrations: [String]
    }

    public var body: RepositoryCheck<FileInfo> {
        Rules.repository(scope: .files(["Sources/App/Routes.swift"]), collect: { file in
            let cases = SyntaxQuery<EnumDeclSyntax>().filter { $0.name == "AppRoute" }.matches(in: file).flatMap { route in
                SyntaxQuery<EnumCaseDeclSyntax>().members(of: route).flatMap { member in
                    member.node.elements.map { SyntaxMatch(node: $0, file: file) }
                }
            }
            let registrations = functionCalls().matches(in: file).compactMap { call -> String? in
                guard call.node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "register",
                      call.node.arguments.count == 1,
                      let member = call.node.arguments.first?.expression.as(MemberAccessExprSyntax.self),
                      member.base == nil else { return nil }
                return member.declName.baseName.text
            }
            return FileInfo(cases: cases, registrations: registrations)
        }, check: { file, inventory in
            let counts = Dictionary(grouping: inventory.flatMap(\.registrations), by: { $0 }).mapValues(\.count)
            return inventory.flatMap(\.cases).filter { $0.file.path == file.path }.compactMap { route in
                let name = route.node.name.text
                let count = counts[name, default: 0]
                guard count != 1 else { return nil }
                return route.failure(message: "\(name) needs exactly one registration; found \(count)")
            }
        })
    }
}

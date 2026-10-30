import BumperBowlingCore
import Foundation

/// One in-memory Swift source file. No checkout, no filesystem.
public struct VirtualSourceFile: Sendable {
    public let path: RelativeFilePath
    public let component: ComponentID?
    public let source: String

    public init(path: RelativeFilePath, component: ComponentID? = nil, source: String) {
        self.path = path
        self.component = component
        self.source = source
    }

    public static func swift(
        _ path: RelativeFilePath,
        component: ComponentID? = nil,
        source: String
    ) -> Self {
        VirtualSourceFile(path: path, component: component, source: source)
    }

    /// Project component enums work directly at the fixture boundary.
    public static func swift<Key: ComponentKey>(
        _ path: RelativeFilePath,
        component: Key,
        source: String
    ) -> Self {
        guard let typedComponent = try? ComponentID(component.rawValue) else {
            preconditionFailure("Invalid virtual source file component: \(component.rawValue)")
        }
        return .swift(path, component: typedComponent, source: source)
    }

    /// Strings are accepted at this test boundary and normalized into typed
    /// values. Invalid fixture paths fail loudly at construction.
    public static func swift(
        _ path: String,
        component: String,
        source: String
    ) -> Self {
        guard let typedPath = try? RelativeFilePath(path) else {
            preconditionFailure("Invalid virtual source file path: \(path)")
        }
        guard let typedComponent = try? ComponentID(component) else {
            preconditionFailure("Invalid virtual source file component: \(component)")
        }
        return .swift(typedPath, component: typedComponent, source: source)
    }
}

@resultBuilder
public enum VirtualRepositoryBuilder {
    public static func buildExpression(_ expression: VirtualSourceFile) -> [VirtualSourceFile] {
        [expression]
    }

    public static func buildExpression(_ expression: [VirtualSourceFile]) -> [VirtualSourceFile] {
        expression
    }

    public static func buildBlock(_ components: [VirtualSourceFile]...) -> [VirtualSourceFile] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [VirtualSourceFile]?) -> [VirtualSourceFile] {
        component ?? []
    }

    public static func buildEither(first component: [VirtualSourceFile]) -> [VirtualSourceFile] {
        component
    }

    public static func buildEither(second component: [VirtualSourceFile]) -> [VirtualSourceFile] {
        component
    }

    public static func buildArray(_ components: [[VirtualSourceFile]]) -> [VirtualSourceFile] {
        components.flatMap { $0 }
    }
}

public struct VirtualRepository: Sendable {
    public let files: [VirtualSourceFile]

    public init(files: [VirtualSourceFile]) {
        self.files = files
    }

    public init(@VirtualRepositoryBuilder files: () -> [VirtualSourceFile]) {
        self.init(files: files())
    }
}

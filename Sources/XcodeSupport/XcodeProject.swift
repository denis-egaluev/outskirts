import Foundation
import Logger
import Shared
import SystemPackage
import XcodeProj

public final class XcodeProject: XcodeProjectlike {
    public let type: String = "project"
    public let path: FilePath
    public let sourceRoot: FilePath
    public let name: String
    public private(set) var targets: Set<XcodeTarget> = []

    let xcodeProject: XcodeProj
    let fileElements: FileElementResolver

    private let xcodebuild: Xcodebuild

    /// The names of the build configurations of the project, in the order of the project file.
    public var buildConfigurationNames: [String] {
        xcodeProject.pbxproj.rootObject?.buildConfigurationList?.buildConfigurations.map(\.name) ?? []
    }

    convenience init?(
        path: FilePath,
        loadedProjectPaths: inout Set<FilePath>,
        referencedBy refPath:
        FilePath,
        xcodebuild: Xcodebuild,
        shell: Shell,
        logger: Logger
    ) throws {
        if !path.exists {
            logger.warn("No such project exists at '\(path.lexicallyNormalized())', referenced by '\(refPath)'.")
            return nil
        }

        try self.init(
            path: path,
            loadedProjectPaths: &loadedProjectPaths,
            xcodebuild: xcodebuild,
            shell: shell,
            logger: logger
        )
    }

    public required init(
        path: FilePath,
        loadedProjectPaths: inout Set<FilePath>,
        xcodebuild: Xcodebuild,
        shell: Shell,
        logger: Logger
    ) throws {
        logger.contextualized(with: "xcode:project").debug("Loading \(path)")

        self.path = path
        self.xcodebuild = xcodebuild
        guard let name = self.path.lastComponent?.stem else {
            throw PeripheryError.pathDoesNotExist(path: path.string)
        }

        self.name = name
        sourceRoot = self.path.removingLastComponent()

        do {
            xcodeProject = try XcodeProj(pathString: self.path.lexicallyNormalized().string)
        } catch {
            guard self.path.exists else {
                throw PeripheryError.projectNotFound(path: self.path.string)
            }

            throw PeripheryError.underlyingError(error)
        }

        fileElements = FileElementResolver(sourceRoot: sourceRoot, projectName: name)
        var subProjects: [XcodeProject] = []
        loadedProjectPaths.insert(path.lexicallyNormalized())

        // Don't search for sub projects within CocoaPods.
        if !path.components.contains("Pods.xcodeproj") {
            subProjects = try xcodeProject.pbxproj.fileReferences
                .filter { $0.path?.hasSuffix(".xcodeproj") ?? false }
                .compactMap { [fileElements] in fileElements.path(of: $0, warn: { logger.warn($0) }) }
                .compactMap { projectPath in
                    // Prevent infinite loading of circular references.
                    guard !loadedProjectPaths.contains(projectPath.lexicallyNormalized()) else { return nil }

                    return try XcodeProject(
                        path: projectPath,
                        loadedProjectPaths: &loadedProjectPaths,
                        referencedBy: path,
                        xcodebuild: xcodebuild,
                        shell: shell,
                        logger: logger
                    )
                }
        }

        targets = xcodeProject.pbxproj.nativeTargets
            .mapSet { XcodeTarget(project: self, target: $0, logger: logger) }
            .union(subProjects.flatMapSet { $0.targets })
    }

    public func schemes(additionalArguments: [String]) throws -> Set<String> {
        try xcodebuild.schemes(project: self, additionalArguments: additionalArguments)
    }
}

/// A project is identified by its normalized path: the same project referenced through different relative paths is
/// one project.
extension XcodeProject: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(path.lexicallyNormalized())
    }
}

extension XcodeProject: Equatable {
    public static func == (lhs: XcodeProject, rhs: XcodeProject) -> Bool {
        lhs.path.lexicallyNormalized() == rhs.path.lexicallyNormalized()
    }
}

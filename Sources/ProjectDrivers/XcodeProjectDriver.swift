#if os(macOS)
    import Configuration
    import Foundation
    import Indexer
    import Logger
    import Shared
    import SourceGraph
    import SystemPackage
    import XcodeSupport

    public final class XcodeProjectDriver {
        private let logger: Logger
        private let configuration: Configuration
        private let xcodebuild: Xcodebuild
        private let project: XcodeProjectlike
        private let schemes: Set<String>

        public convenience init(
            projectPath: FilePath,
            configuration: Configuration,
            shell: Shell,
            logger: Logger,
            cacheDirectory: FilePath? = nil
        ) throws {
            let absolutePath: FilePath = .makeAbsolute(projectPath)
            guard absolutePath.exists else {
                throw PeripheryError.projectNotFound(path: absolutePath.string)
            }

            if configuration.outputFormat.supportsAuxiliaryOutput {
                let asterisk = logger.colorize("*", .boldGreen)
                logger.info("\(asterisk) Inspecting project...")
            }

            let xcodebuild = Xcodebuild(shell: shell, logger: logger, cacheDirectory: cacheDirectory)

            guard !configuration.schemes.isEmpty else {
                throw PeripheryError.usageError("The '--schemes' option is required.")
            }

            try xcodebuild.ensureConfigured()

            let project: XcodeProjectlike
            if projectPath.extension == "xcworkspace" {
                project = try XcodeWorkspace(
                    path: .makeAbsolute(projectPath),
                    xcodebuild: xcodebuild,
                    configuration: configuration,
                    logger: logger,
                    shell: shell
                )
            } else {
                var loadedProjectPaths: Set<FilePath> = []
                project = try XcodeProject(
                    path: .makeAbsolute(projectPath),
                    loadedProjectPaths: &loadedProjectPaths,
                    xcodebuild: xcodebuild,
                    shell: shell,
                    logger: logger
                )
            }

            let schemes: Set<String>

            if configuration.skipSchemesValidation {
                schemes = Set(configuration.schemes)
            } else {
                // Ensure schemes exist within the project
                if configuration.cleanBuild {
                    try xcodebuild.removeDerivedData(for: project, allSchemes: [])
                }
                schemes = try project.schemes(
                    additionalArguments: configuration.xcodeListArguments
                ).filter { configuration.schemes.contains($0) }
                let validSchemeNames = schemes.mapSet { $0 }

                if let scheme = Set(configuration.schemes).subtracting(validSchemeNames).first {
                    throw PeripheryError.invalidScheme(name: scheme, project: project.path.lastComponent?.string ?? "")
                }
            }

            self.init(
                logger: logger,
                configuration: configuration,
                xcodebuild: xcodebuild,
                project: project,
                schemes: schemes
            )
        }

        init(
            logger: Logger,
            configuration: Configuration,
            xcodebuild: Xcodebuild,
            project: XcodeProjectlike,
            schemes: Set<String>
        ) {
            self.logger = logger
            self.configuration = configuration
            self.xcodebuild = xcodebuild
            self.project = project
            self.schemes = schemes
        }
    }

    extension XcodeProjectDriver: ProjectDriver {
        public func build() throws {
            guard !configuration.skipBuild else { return }

            if configuration.cleanBuild {
                try xcodebuild.removeDerivedData(for: project, allSchemes: Array(schemes), buildArguments: configuration.buildArguments)
            }

            for scheme in schemes {
                if configuration.outputFormat.supportsAuxiliaryOutput {
                    let asterisk = logger.colorize("*", .boldGreen)
                    logger.info("\(asterisk) Building \(scheme)...")
                }

                try xcodebuild.build(project: project,
                                     scheme: scheme,
                                     allSchemes: Array(schemes),
                                     additionalArguments: configuration.buildArguments)
            }
        }

        /// Refreshes the build cache entry in use and evicts the unused ones; a configured index store bypasses the cache.
        private func evictUnusedBuildCaches() throws {
            guard configuration.indexStorePath.isEmpty else { return }

            let evicted = try xcodebuild.refreshCache(
                project: project,
                schemes: Array(schemes),
                buildArguments: configuration.buildArguments,
                maxAgeDays: configuration.cacheMaxAgeDays,
                maxSizeGB: configuration.cacheMaxSizeGB
            )
            for entry in evicted {
                let size = ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
                logger.info("Evicted unused build cache \(entry.name) (\(size))")
            }
        }

        public func plan(logger: ContextualLogger) throws -> IndexPlan {
            let indexStorePaths = try resolveIndexStorePaths(configured: configuration.indexStorePath) {
                try xcodebuild.indexStorePath(project: project, schemes: Array(schemes), buildArguments: configuration.buildArguments, skipBuild: configuration.skipBuild)
            }

            try evictUnusedBuildCaches()

            let targets = project.targets
            try targets.forEach { try $0.identifyFiles() }
            let excludedTargets = Self.excludedTargets(of: targets, excludeTests: configuration.excludeTests, excludeTargets: configuration.excludeTargets)
            warnUnmatchedExcludedTargets(configuration.excludeTargets, targets: targets.flatMap { [$0.name, $0.moduleName].compactMap(\.self) }, logger: logger)
            let scannedTargets = Self.scannedTargets(of: targets.subtracting(excludedTargets), excluding: [], relativeTo: project.sourceRoot)
            let expectedSourceFiles = scannedTargets.mapValues(\.swiftSourceFiles)
            let infoPlistPaths = targets.flatMapSet { $0.files(kind: .infoPlist) }
            let xibPaths = targets.flatMapSet { $0.files(kind: .interfaceBuilder) }
            let xcDataModelPaths = targets.flatMapSet { $0.files(kind: .xcDataModel) }
            let xcMappingModelPaths = targets.flatMapSet { $0.files(kind: .xcMappingModel) }
            let xcStringsPaths = targets.flatMapSet { $0.files(kind: .xcStrings) }
            let collector = SourceFileCollector(
                indexStorePaths: indexStorePaths,
                excludedModules: excludedTargets.mapSet { $0.moduleName ?? $0.name },
                scanInputs: ScanInputs(
                    sourceFiles: Set(expectedSourceFiles.values.joined()),
                    resources: infoPlistPaths.union(xibPaths).union(xcDataModelPaths).union(xcMappingModelPaths).union(xcStringsPaths),
                    readsMetalSources: configuration.detectUnusedMetalFunctions,
                    readsAssetCatalogs: configuration.detectsUnusedAssetCatalogSymbols
                ),
                logger: logger,
                configuration: configuration
            )
            let (sourceFiles, unreadableUnits) = try collector.collect()
            let coverageTargets = configuration.strictIndexCoverage ? Self.coverageTargets(of: scannedTargets) : [:]

            return IndexPlan(
                sourceFiles: sourceFiles,
                plistPaths: infoPlistPaths,
                xibPaths: xibPaths,
                xcDataModelPaths: xcDataModelPaths,
                xcMappingModelPaths: xcMappingModelPaths,
                xcStringsPaths: xcStringsPaths,
                expectedSourceFiles: expectedSourceFiles,
                coverageTargets: coverageTargets,
                unreadableUnits: unreadableUnits,
                indexStorePaths: indexStorePaths,
                globalAccentColorNames: targets.flatMapSet(\.globalAccentColorNames)
            )
        }

        /// The test targets with `exclude_tests`, and the targets `exclude_targets` names by target or module name.
        static func excludedTargets(of targets: Set<XcodeTarget>, excludeTests: Bool, excludeTargets: [String]) -> Set<XcodeTarget> {
            targets.filter { target in
                (excludeTests && target.isTestTarget)
                    || excludeTargets.contains(target.name)
                    || target.moduleName.map(excludeTargets.contains) == true
            }
        }

        /// The targets with Swift source files, minus the excluded names, keyed by name. A name shared by targets of
        /// several projects (e.g. in a workspace) is qualified with the path of each project, relative to `base`.
        static func scannedTargets(of targets: Set<XcodeTarget>, excluding excluded: Set<String>, relativeTo base: FilePath) -> [String: XcodeTarget] {
            let scanned = targets.filter { !excluded.contains($0.name) && !$0.swiftSourceFiles.isEmpty }
            let base = base.lexicallyNormalized()

            return Dictionary(grouping: scanned, by: \.name).reduce(into: [:]) { result, group in
                guard group.value.count > 1 else {
                    result[group.key] = group.value.first
                    return
                }

                for target in group.value {
                    let path = target.project.path.lexicallyNormalized()
                    let shown = path.starts(with: base) ? path.relativeTo(base) : path
                    result["\(group.key) (\(shown.string))"] = target
                }
            }
        }

        static func coverageTargets(of targets: [String: XcodeTarget]) -> [String: CoverageTarget] {
            targets.mapValues { CoverageTarget(moduleName: $0.moduleName, platforms: $0.supportedSDKs.compactMapSet(IndexPlatform.init(sdk:))) }
        }
    }
#endif

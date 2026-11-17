#if os(macOS)
    import Configuration
    import ProjectDrivers
    import SystemPackage
    @testable import TestShared
    import XCTest

    final class SPMProjectMacOSLocalizedStringTest: SPMSourceGraphTestCase {
        override static func setUp() {
            super.setUp()

            let configuration = Configuration()
            configuration.buildFilenameMatchers()
            build(projectPath: SPMProjectMacOSPath)
            index(configuration: configuration)
        }

        func testRetainsKeysPassedToLocalizedParameters() {
            assertReferenced(.localizedString("mac_button_key"))
            assertReferenced(.localizedString("mac_label_key"))
            assertReferenced(.localizedString("mac_toggle_key"))
            assertReferenced(.localizedString("mac_section_key"))
            assertReferenced(.localizedString("mac_navigation_title_key"))
            assertReferenced(.localizedString("mac_text_key"))
            assertReferenced(.localizedString("mac_ternary_true_key"))
            assertReferenced(.localizedString("mac_ternary_false_key"))
            assertReferenced(.localizedString("mac_custom_init_key"))
            assertReferenced(.localizedString("mac_resource_param_key"))
            assertReferenced(.localizedString("mac_localization_value_param_key"))
            assertReferenced(.localizedString("mac_variadic_key"))
        }

        func testRetainsKeysPassedToLocalizedTypeInitializers() {
            assertReferenced(.localizedString("mac_dot_init_key"))
            assertReferenced(.localizedString("mac_memberwise_init_key"))
            assertReferenced(.localizedString("mac_value_init_key"))
            assertReferenced(.localizedString("mac_localized_value_init_key"))
            assertReferenced(.localizedString("mac_string_init_key"))
            assertReferenced(.localizedString("mac_resource_init_key"))
            assertNotReferenced(.localizedString("mac_plain_init_key"))
        }

        func testRetainsKeysReturnedFromTrailingClosures() {
            assertReferenced(.localizedString("mac_trailing_closure_key"))
            assertReferenced(.localizedString("mac_forward_scan_key"))
            assertNotReferenced(.localizedString("mac_trailing_closure_string_key"))
            assertNotReferenced(.localizedString("mac_closure_argument_string_key"))
        }

        func testRetainsCoalescedCastAndEnumCaseKeys() {
            assertReferenced(.localizedString("mac_coalesce_key"))
            assertReferenced(.localizedString("mac_cast_key"))
            assertReferenced(.localizedString("mac_case_default_key"))
            assertNotReferenced(.localizedString("mac_coalesce_string_key"))
        }

        func testRetainsKeysPassedToLocalizedSubscripts() {
            assertReferenced(.localizedString("mac_subscript_key"))
            assertReferenced(.localizedString("mac_labeled_subscript_key"))
            assertReferenced(.localizedString("mac_static_subscript_key"))
            assertReferenced(.localizedString("mac_chained_subscript_key"))
            assertReferenced(.localizedString("mac_self_subscript_key"))
            assertNotReferenced(.localizedString("mac_plain_subscript_key"))
            assertNotReferenced(.localizedString("mac_dictionary_subscript_key"))
        }

        func testRetainsKeysPassedToGenericSubscriptParameters() {
            assertReferenced(.localizedString("mac_generic_table_key"))
            // The index store records no conversion of a `String` passed to a generic subscript parameter.
            assertNotReferenced(.localizedString("mac_generic_subscript_key"))
            assertNotReferenced(.localizedString("mac_dictionary_default_key"))
            assertNotReferenced(.localizedString("mac_dictionary_remove_key"))
            assertNotReferenced(.localizedString("mac_unused_generic_subscript_key"))
        }

        /// The index store records the conversion of a literal to a localized type on every supported toolchain
        /// (Swift 6.1.2 and later).
        func testRetainsLiteralsConvertedToLocalizedTypes() {
            assertNotReferenced(.localizedString("mac_generic_string_key"))
            assertNotReferenced(.localizedString("mac_plain_literal_key"))
            assertReferenced(.localizedString("mac_generic_function_key"))
            assertReferenced(.localizedString("mac_generic_closure_key"))
            assertReferenced(.localizedString("mac_generic_raw_key"))
            assertReferenced(.localizedString("mac_generic_multiline_key"))
            assertReferenced(.localizedString("mac_generic_interpolated_key %lld"))
            assertReferenced(.localizedString("mac_generic_method_key"))
        }

        /// Literals whose parameter type the callee signature does not give are keys only when the index store records
        /// their conversion to a localized type; they stay conservatively retained when it cannot tell, in an `#if`
        /// clause without a recorded callee.
        func testIndexStoreDecidesLiteralsOfUnresolvedParameters() {
            assertReferenced(.localizedString("mac_unlocated_localized_key"))
            assertReferenced(.localizedString("mac_enum_payload_key"))
            assertNotReferenced(.localizedString("mac_unlocated_string_key"))
            assertNotReferenced(.localizedString("mac_skipped_closure_string_key"))
            assertNotReferenced(.localizedString("mac_enum_payload_string_key"))
            assertNotReferenced(.localizedString("mac_conditional_string_param_key"))
            assertReferenced(.localizedString("mac_conditional_unlocated_key"))
            assertReferenced(.localizedString("mac_uncompiled_key"))
        }

        /// The index store counts the three bytes of a UTF-8 byte order mark in the columns of the first line.
        func testMatchesFirstLinePositionsOfFilesWithAByteOrderMark() {
            assertReferenced(.localizedString("mac_bom_line1_key"))
            assertReferenced(.localizedString("mac_bom_enum_line1_key"))
            assertAccessibility(.enum("SPMByteOrderMarkKeys"), .public) {
                self.assertAccessibility(.varStatic("bomLine1"), .public)
            }
        }

        func testRetainsKeysFromLocalizedDeclarationTypes() {
            assertReferenced(.localizedString("mac_annotated_property_key"))
            assertReferenced(.localizedString("mac_returned_resource_key"))
            assertReferenced(.localizedString("mac_default_value_key"))
        }

        func testRetainsInterpolatedKeys() {
            assertReferenced(.localizedString("mac_interpolated_string_key %@"))
            assertReferenced(.localizedString("mac_interpolated_int_key %lld"))
            assertReferenced(.localizedString("mac_interpolated_double_key %lf"))
            assertNotReferenced(.localizedString("mac_interpolated_unused_key %@"))
        }

        func testRetainsReturnedKeys() {
            assertReferenced(.localizedString("mac_switch_first_key"))
            assertReferenced(.localizedString("mac_switch_second_key"))
            assertReferenced(.localizedString("mac_ternary_return_key"))
            assertReferenced(.localizedString("mac_ternary_return_count_key %lld"))
        }

        func testRetainsTypedCollectionAndStructInitKeys() throws {
            assertReferenced(.localizedString("mac_typed_array_key"))
            assertReferenced(.localizedString("mac_typed_dictionary_key"))
            assertReferenced(.localizedString("mac_typed_tuple_key"))
            assertReferenced(.localizedString("mac_struct_init_key"))
            assertReferenced(.localizedString("mac_struct_trailing_key"))
            assertNotReferenced(.localizedString("mac_typed_tuple_symbol_key"))
            // The `systemImage:` parameter is resolved as a plain String from the macOS 27 SDK (Xcode 27) on; under
            // Xcode 26 the key is retained, a missed result rather than a false positive.
            try XCTSkipIf(
                Self.swiftVersion.version.isVersion(lessThan: "6.4"),
                "systemImage: keys are pinned on the macOS 27 SDK (Xcode 27, Swift 6.4) and later"
            )
            assertNotReferenced(.localizedString("mac_struct_image_key"))
        }

        func testDoesNotRetainKeysPassedToStringParameters() throws {
            assertNotReferenced(.localizedString("mac_plain_string_param_key"))
            assertNotReferenced(.localizedString("mac_unused_key"))
            assertNotReferenced(.localizedString("mac_dynamic.alpha"))
            // The `systemImage:` parameter is resolved as a plain String from the macOS 27 SDK (Xcode 27) on; under
            // Xcode 26 the key is retained, a missed result rather than a false positive.
            try XCTSkipIf(
                Self.swiftVersion.version.isVersion(lessThan: "6.4"),
                "systemImage: keys are pinned on the macOS 27 SDK (Xcode 27, Swift 6.4) and later"
            )
            assertNotReferenced(.localizedString("mac_label_system_image_key"))
        }

        func testExcludesInfoPlistAndAppShortcutsCatalogsByDefault() {
            assertNotIndexed(.localizedString("NSCameraUsageDescription"))
            assertNotIndexed(.localizedString("mac_shortcut_phrase"))
        }
    }

    /// An index store that may describe an older version of a file cannot tell its literals apart: their positions
    /// may have moved, so the literals whose parameter type is unknown stay conservatively retained.
    final class SPMProjectMacOSOutdatedIndexLocalizedStringTest: SPMSourceGraphTestCase {
        private static var temporaryDirectory: URL?

        /// A copy of the package, built, then one of its files modified after its index store was written.
        override static func setUp() {
            super.setUp()

            let configuration = Configuration()
            configuration.buildFilenameMatchers()
            let fileManager = FileManager.default
            let directory = try! makeTemporaryDirectory("outskirts-outdated-index")
            temporaryDirectory = directory
            let project = FilePath(directory.path).appending("SPMProjectMacOS")
            try! fileManager.createDirectory(atPath: project.string, withIntermediateDirectories: false)
            for name in ["Package.swift", "Sources"] {
                try! fileManager.copyItem(atPath: SPMProjectMacOSPath.appending(name).string, toPath: project.appending(name).string)
            }
            build(projectPath: project)

            let file = project.appending("Sources/SPMProjectMacOSKit/SPMLocalizedViews.swift")
            try! fileManager.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: file.string)
            project.chdir {
                let driver = try! SPMProjectDriver(configuration: configuration, shell: shell, logger: logger)
                plan = try! driver.plan(logger: logger.contextualized(with: "index"))
            }
            index(configuration: configuration)
        }

        override static func tearDown() {
            if let temporaryDirectory {
                try! FileManager.default.removeItem(at: temporaryDirectory)
            }
            super.tearDown()
        }

        func testRetainsLiteralsOfUnresolvedParametersOfOutdatedFiles() {
            assertReferenced(.localizedString("mac_unlocated_string_key"))
            assertReferenced(.localizedString("mac_skipped_closure_string_key"))
            assertReferenced(.localizedString("mac_enum_payload_string_key"))
            assertReferenced(.localizedString("mac_generic_subscript_key"))
            assertReferenced(.localizedString("mac_unlocated_localized_key"))
            assertNotReferenced(.localizedString("mac_plain_string_param_key"))
        }
    }

    final class SPMProjectMacOSLocalizedStringKeyPatternsTest: SPMSourceGraphTestCase {
        override static func setUp() {
            super.setUp()

            let configuration = Configuration()
            configuration.localizedStringKeyPatterns = ["mac_dynamic.*"]
            configuration.buildFilenameMatchers()
            build(projectPath: SPMProjectMacOSPath)
            index(configuration: configuration)
        }

        func testRetainsKeysMatchingDynamicPatterns() {
            assertReferenced(.localizedString("mac_dynamic.alpha"))
            assertReferenced(.localizedString("mac_dynamic.beta"))
            assertNotReferenced(.localizedString("mac_unused_key"))
        }
    }

    final class SPMProjectMacOSLocalizedStringCatalogExcludeTest: SPMSourceGraphTestCase {
        override static func setUp() {
            super.setUp()

            let configuration = Configuration()
            configuration.localizedStringCatalogExclude = ["**/Localizable.xcstrings"]
            configuration.buildFilenameMatchers()
            build(projectPath: SPMProjectMacOSPath)
            index(configuration: configuration)
        }

        func testExcludesConfiguredCatalogs() {
            assertNotIndexed(.localizedString("mac_unused_key"))
            assertNotIndexed(.localizedString("mac_button_key"))
            assertNotReferenced(.localizedString("NSCameraUsageDescription"))
            assertNotReferenced(.localizedString("mac_shortcut_phrase"))
        }
    }
#endif

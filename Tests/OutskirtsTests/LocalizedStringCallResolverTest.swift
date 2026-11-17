@testable import Indexer
@testable import SyntaxAnalysis
import XCTest

final class LocalizedStringCallResolverTest: XCTestCase {
    private typealias Parameter = LocalizedStringCallResolver.Parameter
    private typealias Argument = LocalizedStringCallSite.Argument

    func testDemanglesSwiftUSR() {
        let demangled = LocalizedStringCallResolver.demangle(
            usr: "s:7SwiftUI6ButtonVA2A4TextVRszrlE_6actionACyAEGAA18LocalizedStringKeyV_yyctcfc"
        )

        XCTAssertEqual(
            demangled,
            "(extension in SwiftUI):SwiftUI.Button< where A == SwiftUI.Text>.init(_: SwiftUI.LocalizedStringKey, action: () -> ()) -> SwiftUI.Button<SwiftUI.Text>"
        )
    }

    func testDoesNotDemangleNonSwiftUSR() {
        XCTAssertNil(LocalizedStringCallResolver.demangle(usr: "c:objc(cs)NSAlert(im)addButtonWithTitle:"))
    }

    func testParsesLabeledParameters() {
        let parameters = LocalizedStringCallResolver.parameters(
            fromDemangledSignature: "(extension in SwiftUI):SwiftUI.Label< where A == SwiftUI.Text, B == SwiftUI.Image>.init(_: SwiftUI.LocalizedStringKey, systemImage: Swift.String) -> SwiftUI.Label<SwiftUI.Text, SwiftUI.Image>"
        )

        XCTAssertEqual(parameters, [
            Parameter(label: nil, type: "SwiftUI.LocalizedStringKey"),
            Parameter(label: "systemImage", type: "Swift.String"),
        ])
    }

    func testParsesUnlabeledParameters() {
        let parameters = LocalizedStringCallResolver.parameters(
            fromDemangledSignature: "(extension in SwiftUI):SwiftUI.View.navigationTitle(SwiftUI.LocalizedStringKey) -> some"
        )

        XCTAssertEqual(parameters, [Parameter(label: nil, type: "SwiftUI.LocalizedStringKey")])
    }

    func testParsesFunctionTypeParameters() {
        let parameters = LocalizedStringCallResolver.parameters(
            fromDemangledSignature: "Module.run<A where A: Swift.StringProtocol>(_: A, completion: (Swift.Int, Swift.String) -> (), title: [Swift.String: Foundation.LocalizedStringResource]) -> ()"
        )

        XCTAssertEqual(parameters, [
            Parameter(label: nil, type: "A"),
            Parameter(label: "completion", type: "(Swift.Int, Swift.String) -> ()"),
            Parameter(label: "title", type: "[Swift.String: Foundation.LocalizedStringResource]"),
        ])
    }

    func testSkipsPrivateDiscriminator() {
        let parameters = LocalizedStringCallResolver.parameters(
            fromDemangledSignature: "Module.Controller.(showAlert in _81AE913598B2E23132B3415B5C7CAFDE)(title: SwiftUI.LocalizedStringKey) -> ()"
        )

        XCTAssertEqual(parameters, [Parameter(label: "title", type: "SwiftUI.LocalizedStringKey")])
    }

    func testParsesEmptyParameterList() {
        XCTAssertEqual(LocalizedStringCallResolver.parameters(fromDemangledSignature: "Module.run() -> ()"), [])
    }

    func testMatchesArgumentsToParametersSkippingDefaults() {
        let parameters = [
            Parameter(label: nil, type: "SwiftUI.LocalizedStringKey"),
            Parameter(label: "tableName", type: "Swift.Optional<Swift.String>"),
            Parameter(label: "comment", type: "Swift.Optional<Swift.StaticString>"),
        ]
        let arguments = [
            Argument(label: nil, keys: ["key"]),
            Argument(label: "comment", keys: ["comment"]),
        ]

        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: arguments, parameters: parameters), ["key"])
    }

    func testMatchesVariadicArguments() {
        let parameters = [Parameter(label: nil, type: "Foundation.LocalizedStringResource...")]
        let arguments = [Argument(label: nil, keys: ["a"]), Argument(label: nil, keys: ["b"])]

        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: arguments, parameters: parameters), ["a", "b"])
    }

    func testRetainsUnmatchedArguments() {
        let parameters = [Parameter(label: "title", type: "Swift.String")]
        let arguments = [Argument(label: "other", keys: ["unmatched"])]

        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: arguments, parameters: parameters), ["unmatched"])
    }

    func testFindsStringKeyParametersOfLocalizedInitializers() {
        let signatures: [(String, Set<String?>)] = [
            ("SwiftUI.LocalizedStringKey.init(Swift.String) -> SwiftUI.LocalizedStringKey", [nil, "stringLiteral"]),
            (
                "(extension in Foundation):Swift.String.LocalizationValue.init(stringLiteral: Swift.String) -> (extension in Foundation):Swift.String.LocalizationValue",
                [nil, "stringLiteral"]
            ),
            (
                "Foundation.LocalizedStringResource.init(_: Swift.StaticString, defaultValue: (extension in Foundation):Swift.String.LocalizationValue, table: Swift.String?) -> Foundation.LocalizedStringResource",
                [nil, "stringLiteral"]
            ),
            (
                "(extension in Foundation):Swift.String.init(localized: Swift.StaticString, defaultValue: (extension in Foundation):Swift.String.LocalizationValue, table: Swift.String?) -> Swift.String",
                ["localized"]
            ),
            ("Module.Wrapper<A>.init<B where B: Swift.StringProtocol>(B) -> Module.Wrapper<A>", []),
            ("Module.Name.init(Swift.String) -> Module.Name", []),
            ("Module.LocalizedStringKeyBox.init(Swift.String) -> Module.LocalizedStringKeyBox", []),
            ("Module.show(Swift.String) -> ()", []),
        ]

        for (signature, labels) in signatures {
            XCTAssertEqual(LocalizedStringCallResolver.stringKeyLabels(ofDemangledSignature: signature), labels, signature)
        }
    }

    func testRetainsPlainStringKeysOfLocalizedInitializers() {
        let parameters = [
            Parameter(label: nil, type: "Swift.StaticString"),
            Parameter(label: "table", type: "Swift.String?"),
        ]
        let arguments = [Argument(label: nil, keys: ["key"]), Argument(label: "table", keys: ["Table"])]

        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: arguments, parameters: parameters, stringKeyLabels: [nil]), ["key"])
        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: arguments, parameters: parameters), [])
    }

    func testMatchesTrailingClosureToNextFunctionParameter() {
        let parameters = [
            Parameter(label: nil, type: "Swift.String"),
            Parameter(label: "make", type: "() -> SwiftUI.LocalizedStringKey"),
            Parameter(label: "plain", type: "() -> Swift.String"),
        ]
        let arguments = [
            Argument(label: nil, keys: ["string_key"]),
            Argument(label: nil, keys: ["closure_key"], isTrailingClosure: true),
            Argument(label: "plain", keys: ["plain_closure_key"]),
        ]

        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: arguments, parameters: parameters), ["closure_key"])
        XCTAssertEqual(
            LocalizedStringCallResolver.usedKeys(
                for: [Argument(label: nil, keys: ["defaulted_closure_key"], isTrailingClosure: true)],
                parameters: parameters
            ),
            ["defaulted_closure_key"]
        )
        XCTAssertEqual(
            LocalizedStringCallResolver.usedKeys(
                for: [Argument(label: nil, keys: ["map_key"], isTrailingClosure: true)],
                parameters: [Parameter(label: nil, type: "(A) throws(B) -> C")]
            ),
            []
        )
    }

    func testRetainsTrailingClosureKeysOfSkippableParametersUnlessTheIndexStoreDecides() {
        // `g(_ a: (() -> String)? = nil, _ b: () -> LocalizedStringKey)` called as `g { "key" }` passes the closure to
        // `b`; default values are not in the signature, so every candidate before the next labeled argument counts.
        let parameters = [
            Parameter(label: nil, type: "(() -> Swift.String)?"),
            Parameter(label: nil, type: "() -> SwiftUI.LocalizedStringKey"),
            Parameter(label: "footer", type: "() -> Swift.String"),
        ]

        XCTAssertEqual(
            LocalizedStringCallResolver.usedKeys(
                for: [
                    Argument(label: nil, keys: ["closure_key"], isTrailingClosure: true),
                    Argument(label: "footer", keys: ["footer_key"]),
                ],
                parameters: parameters
            ),
            ["closure_key"]
        )
        XCTAssertEqual(
            LocalizedStringCallResolver.usedKeys(
                for: [Argument(label: nil, keys: ["string_closure_key"], isTrailingClosure: true)],
                parameters: [Parameter(label: nil, type: "(() -> Swift.String)?"), parameters[2]]
            ),
            []
        )

        // The index store tells which candidate takes the closure: only a closure every candidate localizes is known.
        XCTAssertEqual(
            LocalizedStringCallResolver.usedKeys(
                for: [Argument(label: nil, keys: ["closure_key"], isTrailingClosure: true)],
                parameters: parameters,
                literalsDecidedByIndex: true
            ),
            []
        )
        XCTAssertEqual(
            LocalizedStringCallResolver.usedKeys(
                for: [Argument(label: nil, keys: ["closure_key"], isTrailingClosure: true)],
                parameters: [parameters[1]],
                literalsDecidedByIndex: true
            ),
            ["closure_key"]
        )
    }

    func testDoesNotRetainKeysOfClosuresTakingLocalizedArguments() {
        let parameters = [Parameter(label: nil, type: "(SwiftUI.LocalizedStringKey) -> Swift.String")]
        let arguments = [Argument(label: nil, keys: ["closure_argument_key"], isTrailingClosure: true)]

        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: arguments, parameters: parameters), [])
    }

    func testReadsTheReturnTypeOfFunctionTypes() {
        let types: [(String, String)] = [
            ("(SwiftUI.LocalizedStringKey) -> Swift.String", "Swift.String"),
            ("@escaping @Sendable () -> SwiftUI.LocalizedStringKey", "SwiftUI.LocalizedStringKey"),
            ("((Swift.Int) -> Foundation.LocalizedStringResource)?", "Foundation.LocalizedStringResource"),
            ("(Swift.Int) -> (Swift.String) -> SwiftUI.LocalizedStringKey", "SwiftUI.LocalizedStringKey"),
            ("(A) async throws(B) -> C", "C"),
            ("[Swift.String: SwiftUI.LocalizedStringKey]", "[Swift.String: SwiftUI.LocalizedStringKey]"),
            ("(SwiftUI.LocalizedStringKey, Swift.Int)?", "(SwiftUI.LocalizedStringKey, Swift.Int)?"),
        ]

        for (type, valueType) in types {
            XCTAssertEqual(LocalizedStringSyntaxVisitor.valueTypeName(of: type), valueType, type)
        }
    }

    func testRetainsKeysPassedToGenericSubscriptParametersUnlessTheIndexStoreDecides() {
        let cases: [(usr: String, label: String?, isKey: Bool)] = [
            // `subscript(_: Key)` of a `Table<Key>`, which may be a `Table<LocalizedStringKey>`.
            ("s:2cv5TableVySixcig", nil, true),
            // `subscript<K>(generic: K)`.
            ("s:2cv3BoxV7genericSix_tcluig", "generic", true),
            // `Dictionary` and `Set` keys are `Hashable`, which no localized type is.
            ("s:SDyq_Sgxcig", nil, false),
            ("s:SDyq_x_q_yXKtcig", nil, false),
            // A generic parameter of a function other than a subscript, e.g. `dict.removeValue(forKey:)`.
            ("s:SD11removeValue6forKeyq_Sgx_tF", "forKey", false),
        ]

        for (usr, label, isKey) in cases {
            let callSite = LocalizedStringCallSite(line: 1, column: 1, arguments: [Argument(label: label, keys: ["key"])])
            XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: callSite, calleeUsrs: [usr]), isKey ? ["key"] : [], usr)
            XCTAssertEqual(
                LocalizedStringCallResolver.usedKeys(for: callSite, calleeUsrs: [usr], literalsDecidedByIndex: true),
                [],
                usr
            )
        }
    }

    func testCollectsDictionaryAndSetKeysForHashableLocalizedTypes() {
        let cases: [(usr: String, arguments: [Argument], expected: Set<String>)] = [
            // `dict["key"]`, `dict["key", default: 0]`, `dict.removeValue(forKey: "key")`.
            ("s:SDyq_Sgxcig", [Argument(label: nil, keys: ["key"])], ["key"]),
            ("s:SDyq_x_q_yXKtcig", [Argument(label: nil, keys: ["key"]), Argument(label: "default", keys: [])], ["key"]),
            ("s:SD11removeValue6forKeyq_Sgx_tF", [Argument(label: "forKey", keys: ["key"])], ["key"]),
            // `set.insert("key")`, `set.contains("key")`.
            ("s:Sh6insertySb8inserted_x17memberAfterInserttxnF", [Argument(label: nil, keys: ["key"])], ["key"]),
            ("s:Sh8containsySbxF", [Argument(label: nil, keys: ["key"])], ["key"]),
            // `dict.updateValue("value", forKey: "key")`: the value is not a key.
            (
                "s:SD11updateValue_6forKeyq_Sgq__xtF",
                [Argument(label: nil, keys: ["value"]), Argument(label: "forKey", keys: ["key"])],
                ["key"]
            ),
            // `Array` and other types are not keyed by a `Hashable` value.
            ("s:SayxSicig", [Argument(label: nil, keys: ["key"])], []),
            ("s:2cv5TableVySixcig", [Argument(label: nil, keys: ["key"])], []),
        ]

        for (usr, arguments, expected) in cases {
            let callSite = LocalizedStringCallSite(line: 1, column: 1, arguments: arguments)
            XCTAssertEqual(LocalizedStringCallResolver.hashableKeyedKeys(for: callSite, calleeUsrs: [usr]), expected, usr)
        }
    }

    func testResolvesSubscriptAccessors() {
        // `subscript(two a: String, _ b: LocalizedStringKey)`, called as `table[two: "first", "second"]`: the index
        // store records its getter at the opening bracket.
        let getter = "s:2cv3SubV3two_SiSS_7SwiftUI18LocalizedStringKeyVtcig"
        let twoArguments = LocalizedStringCallSite(line: 1, column: 1, arguments: [
            Argument(label: "two", keys: ["string_subscript_key"]),
            Argument(label: nil, keys: ["localized_subscript_key"]),
        ])

        XCTAssertEqual(
            LocalizedStringCallResolver.demangle(usr: getter),
            "cv.Sub.subscript.getter : (two: Swift.String, _: SwiftUI.LocalizedStringKey) -> Swift.Int"
        )
        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: twoArguments, calleeUsrs: [getter]), ["localized_subscript_key"])

        let accessors: [(usr: String, isKey: Bool)] = [
            // `static subscript(_: LocalizedStringKey)`.
            ("s:2cv3SubVySi7SwiftUI18LocalizedStringKeyVcigZ", true),
            // The setter and the modify accessor of `subscript(label: LocalizedStringResource)`.
            ("s:2cv3BoxV5labelSi10Foundation23LocalizedStringResourceV_tcis", true),
            ("s:2cv3BoxV5labelSi10Foundation23LocalizedStringResourceV_tciM", true),
            // `subscript(label: String)`, `Dictionary<String, _>` and `Array`.
            ("s:2cv3BoxV5labelSiSS_tcig", false),
            ("s:SDyq_Sgxcig", false),
            ("s:SayxSicig", false),
        ]

        for (usr, isKey) in accessors {
            let label = usr.contains("label") ? "label" : nil
            let callSite = LocalizedStringCallSite(line: 1, column: 1, arguments: [Argument(label: label, keys: ["key"])])

            XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: callSite, calleeUsrs: [usr]), isKey ? ["key"] : [], usr)
        }
    }

    func testRetainsKeysOfUnresolvedCalleeUnlessTheIndexStoreDecides() {
        let callSite = LocalizedStringCallSite(line: 1, column: 1, arguments: [Argument(label: nil, keys: ["key"])])
        let objcCallee: Set = ["c:objc(cs)NSAlert(im)addButtonWithTitle:"]
        let unmatched = [Argument(label: "unknown", keys: ["unmatched_key"])]
        let parameters = [Parameter(label: nil, type: "Swift.String")]

        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: callSite, calleeUsrs: []), ["key"])
        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: callSite, calleeUsrs: objcCallee), ["key"])
        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: unmatched, parameters: parameters), ["unmatched_key"])

        // The index store tells the converted literals apart, an Objective-C signature stays conservative.
        XCTAssertEqual(LocalizedStringCallResolver.usedKeys(for: callSite, calleeUsrs: [], literalsDecidedByIndex: true), [])
        XCTAssertEqual(
            LocalizedStringCallResolver.usedKeys(for: callSite, calleeUsrs: objcCallee, literalsDecidedByIndex: true),
            ["key"]
        )
        XCTAssertEqual(
            LocalizedStringCallResolver.usedKeys(for: unmatched, parameters: parameters, literalsDecidedByIndex: true),
            []
        )
    }

    func testRecognizesLiteralInitializersOfLocalizedTypes() {
        let localized = [
            "s:10Foundation23LocalizedStringResourceV13stringLiteralACSS_tcfc",
            "s:7SwiftUI18LocalizedStringKeyV13stringLiteralACSS_tcfc",
            "s:SS10FoundationE17LocalizationValueV13stringLiteralACSS_tcfc",
            "s:10Foundation23LocalizedStringResourceV19stringInterpolationACSSAAE17LocalizationValueV0cF0V_tcfc",
        ]
        let notLocalized = [
            // A project type conforming to `ExpressibleByStringLiteral`.
            "s:3Toy7WrapperV13stringLiteralACSS_tcfc",
            // `Swift.String.init(stringInterpolation:)`.
            "s:SS19stringInterpolationSSs26DefaultStringInterpolationV_tcfc",
            // A localized parameter callee, not a literal conversion.
            "s:7SwiftUI6ButtonVA2A4TextVRszrlE_6actionACyAEGAA18LocalizedStringKeyV_yyctcfc",
            "c:objc(cs)NSAlert(im)addButtonWithTitle:",
        ]

        for usr in localized {
            XCTAssertTrue(LocalizedStringCallResolver.isLocalizedLiteralInitializer(usr: usr), usr)
        }

        for usr in notLocalized {
            XCTAssertFalse(LocalizedStringCallResolver.isLocalizedLiteralInitializer(usr: usr), usr)
        }
    }

    func testRetainsOnlyLiteralsConvertedToLocalizedTypes() {
        typealias Position = LocalizedStringCalleePosition
        let literals = [
            LocalizedStringLiteral(key: "converted", line: 1, column: 7),
            LocalizedStringLiteral(key: "second_on_line", line: 1, column: 20),
            LocalizedStringLiteral(key: "plain", line: 2, column: 7),
            LocalizedStringLiteral(key: "wrapper", line: 3, column: 7),
            LocalizedStringLiteral(key: "format %@", line: 4, column: 7),
            LocalizedStringLiteral(key: "not_indexed", line: 5, column: 7),
        ]
        let usrs: [Position: Set<String>] = [
            Position(line: 1, column: 7): ["s:10Foundation23LocalizedStringResourceV13stringLiteralACSS_tcfc"],
            Position(line: 1, column: 20): ["s:7SwiftUI18LocalizedStringKeyV13stringLiteralACSS_tcfc"],
            Position(line: 2, column: 5): ["s:10Foundation23LocalizedStringResourceV13stringLiteralACSS_tcfc"],
            Position(line: 3, column: 7): ["s:3Toy7WrapperV13stringLiteralACSS_tcfc"],
            Position(line: 4, column: 7): [
                "s:10Foundation23LocalizedStringResourceV19stringInterpolationACSSAAE17LocalizationValueV0cF0V_tcfc",
            ],
        ]

        XCTAssertEqual(
            LocalizedStringCallResolver.convertedLiteralKeys(literals, calleeUsrsByPosition: usrs),
            ["converted", "second_on_line", "format %@"]
        )
        XCTAssertEqual(LocalizedStringCallResolver.convertedLiteralKeys(literals, calleeUsrsByPosition: [:]), [])
    }

    func testMatchesConversionsOnlyAtTheLiteralPosition() {
        typealias Position = LocalizedStringCalleePosition
        // `Button("preview_key") {}` in a `#Preview` body: the macro arguments are type-checked in the expansion buffer,
        // and a conversion recorded at another position, e.g. at the `#` of the expansion, retains no key.
        let literals = [LocalizedStringLiteral(key: "preview_key", line: 2, column: 12)]
        let conversion: Set = ["s:7SwiftUI18LocalizedStringKeyV13stringLiteralACSS_tcfc"]

        XCTAssertEqual(
            LocalizedStringCallResolver.convertedLiteralKeys(literals, calleeUsrsByPosition: [
                Position(line: 1, column: 1): conversion,
                Position(line: 2, column: 5): conversion,
                Position(line: 2, column: 11): conversion,
                Position(line: 12, column: 2): conversion,
            ]),
            []
        )
        XCTAssertEqual(
            LocalizedStringCallResolver.convertedLiteralKeys(literals, calleeUsrsByPosition: [Position(line: 2, column: 12): conversion]),
            ["preview_key"]
        )
    }
}

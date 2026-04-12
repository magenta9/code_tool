import Foundation
import XCTest

@testable import CodeToolCore
@testable import CodeToolUI

#if canImport(AppKit)
    import AppKit
#endif

#if canImport(SwiftUI)
    import SwiftUI

    final class StyledTextEditorTestModel: ObservableObject {
        @Published var text = ""
    }

    struct StyledTextEditorTestContainer: View {
        @ObservedObject var model: StyledTextEditorTestModel

        var body: some View {
            StyledTextEditor(
                text: Binding(
                    get: { model.text },
                    set: { model.text = $0 }
                ),
                placeholder: "Type here"
            )
        }
    }
#endif

#if canImport(AppKit)
    func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = firstTextView(in: subview) {
                return textView
            }
        }

        return nil
    }

    let appKitTextBehaviorKeys = [
        "NSAutomaticSpellingCorrectionEnabled",
        "NSAutomaticTextCompletionEnabled",
        "NSAutomaticQuoteSubstitutionEnabled",
        "NSAutomaticDashSubstitutionEnabled",
        "NSAutomaticTextReplacementEnabled",
    ]
#endif

#if canImport(AppKit)
extension CodeToolTests {
    @MainActor
    func testStyledTextEditorDisablesCommitTimeTextCheckingFeatures() {
        let defaults = UserDefaults.standard
        let savedValues = Dictionary(uniqueKeysWithValues: appKitTextBehaviorKeys.map { key in
            (key, defaults.object(forKey: key))
        })
        defer {
            for (key, value) in savedValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        for key in appKitTextBehaviorKeys {
            defaults.set(true, forKey: key)
        }

        let draft = StyledTextEditorTestModel()
        let host = NSHostingView(rootView: StyledTextEditorTestContainer(model: draft))
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 240)
        host.layoutSubtreeIfNeeded()

        guard let textView = firstTextView(in: host) else {
            XCTFail("Expected StyledTextEditor to contain an NSTextView")
            return
        }

        XCTAssertFalse(textView.isAutomaticSpellingCorrectionEnabled)
        XCTAssertFalse(textView.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(textView.isGrammarCheckingEnabled)
        XCTAssertFalse(textView.isAutomaticTextCompletionEnabled)
        XCTAssertFalse(textView.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticTextReplacementEnabled)
    }

    @MainActor
    func testStyledTextEditorDoesNotCommitMarkedTextToBinding() {
        let draft = StyledTextEditorTestModel()
        let host = NSHostingView(rootView: StyledTextEditorTestContainer(model: draft))
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 240)
        host.layoutSubtreeIfNeeded()

        guard let textView = firstTextView(in: host) else {
            XCTFail("Expected StyledTextEditor to contain an NSTextView")
            return
        }

        textView.setMarkedText(
            "ni",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        textView.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(draft.text, "")
        XCTAssertEqual(textView.string, "ni")
    }

    @MainActor
    func testStyledTextEditorDoesNotOverwriteMarkedTextDuringViewUpdates() {
        let draft = StyledTextEditorTestModel()
        let host = NSHostingView(rootView: StyledTextEditorTestContainer(model: draft))
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 240)
        host.layoutSubtreeIfNeeded()

        guard let textView = firstTextView(in: host) else {
            XCTFail("Expected StyledTextEditor to contain an NSTextView")
            return
        }

        textView.setMarkedText(
            "ni",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())

        draft.text = "external update"
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(textView.string, "ni")
    }

}
#endif

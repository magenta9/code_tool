import Foundation

#if canImport(AppKit)
    import AppKit

    public enum CodeToolTextInputConfiguration {
        public static let appDefaults: [String: Bool] = [
            "NSAutomaticSpellingCorrectionEnabled": false,
            "NSAutomaticTextCompletionEnabled": false,
            "NSAutomaticQuoteSubstitutionEnabled": false,
            "NSAutomaticDashSubstitutionEnabled": false,
            "NSAutomaticTextReplacementEnabled": false,
        ]

        public static func registerAppDefaults(in defaults: UserDefaults = .standard) {
            for (key, value) in appDefaults {
                defaults.set(value, forKey: key)
            }
        }

        public static func configure(_ textView: NSTextView) {
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            textView.isGrammarCheckingEnabled = false
            textView.isAutomaticTextCompletionEnabled = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticDataDetectionEnabled = false
            textView.isAutomaticLinkDetectionEnabled = false
        }
    }
#endif

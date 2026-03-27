import SwiftUI
import Foundation

// MARK: - Diff Model

/// Describes the type of difference between two JSON values.
public enum DiffType: String {
    case added = "Added"
    case removed = "Removed"
    case modified = "Modified"
}

/// A single difference found between two JSON structures.
public struct DiffItem: Identifiable {
    public let id = UUID()
    public let path: String
    public let type: DiffType
    public let leftValue: String?
    public let rightValue: String?
}

// MARK: - Diff Algorithm

/// Recursively compares two parsed JSON values and returns a list of differences.
public func compareJSON(_ left: Any, _ right: Any, path: String = "root") -> [DiffItem] {
    var diffs: [DiffItem] = []

    switch (left, right) {
    case (let lDict as [String: Any], let rDict as [String: Any]):
        let allKeys = Set(lDict.keys).union(rDict.keys).sorted()
        for key in allKeys {
            let childPath = "\(path).\(key)"
            switch (lDict[key], rDict[key]) {
            case (.none, .some(let rVal)):
                diffs.append(DiffItem(path: childPath, type: .added, leftValue: nil, rightValue: describe(rVal)))
            case (.some(let lVal), .none):
                diffs.append(DiffItem(path: childPath, type: .removed, leftValue: describe(lVal), rightValue: nil))
            case (.some(let lVal), .some(let rVal)):
                diffs.append(contentsOf: compareJSON(lVal, rVal, path: childPath))
            default:
                break
            }
        }

    case (let lArr as [Any], let rArr as [Any]):
        let maxCount = max(lArr.count, rArr.count)
        for i in 0..<maxCount {
            let childPath = "\(path)[\(i)]"
            if i >= lArr.count {
                diffs.append(DiffItem(path: childPath, type: .added, leftValue: nil, rightValue: describe(rArr[i])))
            } else if i >= rArr.count {
                diffs.append(DiffItem(path: childPath, type: .removed, leftValue: describe(lArr[i]), rightValue: nil))
            } else {
                diffs.append(contentsOf: compareJSON(lArr[i], rArr[i], path: childPath))
            }
        }

    default:
        if !isEqual(left, right) {
            diffs.append(DiffItem(path: path, type: .modified, leftValue: describe(left), rightValue: describe(right)))
        }
    }

    return diffs
}

// MARK: - Helpers

private func describe(_ value: Any) -> String {
    if value is NSNull { return "null" }
    if let dict = value as? [String: Any] {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{...}"
    }
    if let arr = value as? [Any] {
        if let data = try? JSONSerialization.data(withJSONObject: arr, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[...]"
    }
    return "\(value)"
}

private func isEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    switch (lhs, rhs) {
    case (is NSNull, is NSNull):
        return true
    case (let l as Bool, let r as Bool):
        return l == r
    case (let l as NSNumber, let r as NSNumber):
        // Distinguish bools from numbers to avoid 1 == true
        if CFBooleanGetTypeID() == CFGetTypeID(l) || CFBooleanGetTypeID() == CFGetTypeID(r) {
            return CFBooleanGetTypeID() == CFGetTypeID(l)
                && CFBooleanGetTypeID() == CFGetTypeID(r)
                && l.boolValue == r.boolValue
        }
        return l == r
    case (let l as String, let r as String):
        return l == r
    case (let l as [String: Any], let r as [String: Any]):
        return NSDictionary(dictionary: l).isEqual(to: r)
    case (let l as [Any], let r as [Any]):
        guard l.count == r.count else { return false }
        return zip(l, r).allSatisfy { isEqual($0, $1) }
    default:
        return false
    }
}

// MARK: - JSONDiffView

/// A SwiftUI view that compares two JSON objects side-by-side and shows their differences.
public struct JSONDiffView: View {
    @State private var leftText: String = ""
    @State private var rightText: String = ""
    @State private var diffs: [DiffItem] = []
    @State private var errorMessage: String?
    @State private var hasCompared: Bool = false

    public init() {}

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Delta analysis",
            title: "JSON Diff",
            description: "Compare left and right payloads in the same split workbench used across the toolkit.",
            systemImage: "arrow.left.arrow.right",
            statusItems: statusItems
        ) {
            StyledButton("Compare", systemImage: "arrow.left.arrow.right", variant: .primary) {
                compare()
            }
            StyledButton("Swap", systemImage: "arrow.triangle.swap") {
                let temp = leftText
                leftText = rightText
                rightText = temp
                if hasCompared { compare() }
            }
            StyledButton("Sample Data", systemImage: "doc.text") {
                loadSampleData()
            }
            StyledButton("Clear", systemImage: "trash", variant: .ghost) {
                leftText = ""
                rightText = ""
                diffs = []
                errorMessage = nil
                hasCompared = false
            }
        } content: {
            VStack(spacing: AppTheme.Spacing.lg) {
                HSplitView {
                    StyledPanel(title: "Left JSON") {
                        StyledTextEditor(text: $leftText, placeholder: "Paste JSON here…")
                    }

                    StyledPanel(title: "Right JSON") {
                        StyledTextEditor(text: $rightText, placeholder: "Paste JSON here…")
                    }
                }
                .frame(minHeight: 220)

                diffResultsPanel
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
    }

    private var statusItems: [ToolStatusItem] {
        if let errorMessage {
            return [ToolStatusItem(title: errorMessage, systemImage: "exclamationmark.triangle.fill", tint: AppTheme.error)]
        }
        if hasCompared && diffs.isEmpty {
            return [ToolStatusItem(title: "No differences", systemImage: "checkmark.circle.fill", tint: AppTheme.success)]
        }
        if hasCompared {
            let added = diffs.filter { $0.type == .added }.count
            let removed = diffs.filter { $0.type == .removed }.count
            let modified = diffs.filter { $0.type == .modified }.count
            return [
                ToolStatusItem(title: "\(diffs.count) total", systemImage: "chart.bar.xaxis", tint: AppTheme.accent),
                ToolStatusItem(title: "+\(added) / -\(removed) / ~\(modified)", systemImage: "list.bullet.indent", tint: AppTheme.accentWarm)
            ]
        }
        return [ToolStatusItem(title: "Ready to compare", systemImage: "rectangle.split.2x1", tint: AppTheme.accentWarm)]
    }

    // MARK: - Diff Results

    private var diffResultsPanel: some View {
        StyledPanel(title: "Differences") {
            if let error = errorMessage {
                ToolMessageBanner(systemImage: "exclamationmark.triangle.fill", message: error, tint: AppTheme.error)
            } else if !hasCompared {
                ToolMessageBanner(systemImage: "sparkles", message: "Enter JSON in both panels and run Compare from the shared action bar.", tint: AppTheme.accentWarm)
            } else if diffs.isEmpty {
                ToolMessageBanner(systemImage: "checkmark.circle.fill", message: "No differences found. The JSON structures are identical.", tint: AppTheme.success)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diffs) { item in
                            diffRow(item)
                            if item.id != diffs.last?.id {
                                StyledDivider()
                            }
                        }
                    }
                }
                .frame(minHeight: 120)
            }
        }
    }

    private func diffRow(_ item: DiffItem) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            GradientBadge(item.type.rawValue, color: badgeColor(for: item.type))

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(item.path)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(AppTheme.textPrimary)

                switch item.type {
                case .added:
                    Text("Value: \(item.rightValue ?? "nil")")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppTheme.textMuted)
                case .removed:
                    Text("Value: \(item.leftValue ?? "nil")")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppTheme.textMuted)
                case .modified:
                    Text("Left:  \(item.leftValue ?? "nil")")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppTheme.textMuted)
                    Text("Right: \(item.rightValue ?? "nil")")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppTheme.textMuted)
                }
            }

            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(Color.clear)
    }

    private func badgeColor(for type: DiffType) -> Color {
        switch type {
        case .added: return AppTheme.success
        case .removed: return AppTheme.error
        case .modified: return AppTheme.warning
        }
    }

    private var diffSummary: some View {
        let added = diffs.filter { $0.type == .added }.count
        let removed = diffs.filter { $0.type == .removed }.count
        let modified = diffs.filter { $0.type == .modified }.count
        return HStack(spacing: AppTheme.Spacing.sm) {
            Text("\(diffs.count) difference\(diffs.count == 1 ? "" : "s")")
                .fontWeight(.medium)
                .foregroundStyle(AppTheme.textPrimary)
            if added > 0 {
                Text("+\(added)")
                    .foregroundStyle(AppTheme.success)
            }
            if removed > 0 {
                Text("-\(removed)")
                    .foregroundStyle(AppTheme.error)
            }
            if modified > 0 {
                Text("~\(modified)")
                    .foregroundStyle(AppTheme.warning)
            }
        }
        .font(.callout)
    }

    // MARK: - Actions

    private func compare() {
        errorMessage = nil
        diffs = []
        hasCompared = true

        let trimmedLeft = leftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRight = rightText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedLeft.isEmpty, !trimmedRight.isEmpty else {
            errorMessage = "Both JSON inputs must be non-empty."
            return
        }

        guard let leftData = trimmedLeft.data(using: .utf8),
              let leftObj = try? JSONSerialization.jsonObject(with: leftData, options: .fragmentsAllowed) else {
            errorMessage = "Left JSON is invalid."
            return
        }

        guard let rightData = trimmedRight.data(using: .utf8),
              let rightObj = try? JSONSerialization.jsonObject(with: rightData, options: .fragmentsAllowed) else {
            errorMessage = "Right JSON is invalid."
            return
        }

        diffs = compareJSON(leftObj, rightObj)
    }

    private func loadSampleData() {
        leftText = """
        {
          "user": {
            "name": "Alice",
            "age": 30,
            "email": "alice@example.com",
            "active": true,
            "tags": ["admin", "editor"]
          },
          "settings": {
            "theme": "dark",
            "notifications": true
          }
        }
        """

        rightText = """
        {
          "user": {
            "name": "Alice",
            "age": 31,
            "phone": "+1-555-0100",
            "active": false,
            "tags": ["admin", "viewer"]
          },
          "settings": {
            "theme": "light",
            "notifications": true,
            "language": "en"
          }
        }
        """

        compare()
    }
}

// MARK: - Preview

#if DEBUG
struct JSONDiffView_Previews: PreviewProvider {
    static var previews: some View {
        JSONDiffView()
            .frame(width: 900, height: 700)
            .preferredColorScheme(.dark)
    }
}
#endif

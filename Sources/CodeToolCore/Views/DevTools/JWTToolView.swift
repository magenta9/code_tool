import CodeToolUI
import SwiftUI
import Foundation

// MARK: - JWT Tool View

public struct JWTToolView: View {
    public init() {}

    @State private var mode: Mode = .decode
    @State private var jwtInput: String = ""
    @State private var headerJSON: String = ""
    @State private var payloadJSON: String = ""
    @State private var signatureHex: String = ""
    @State private var expirationStatus: ExpirationStatus = .none
    @State private var issuedAtText: String = ""
    @State private var errorMessage: String = ""

    // Encode mode state
    @State private var encodeHeader: String = "{\n  \"alg\": \"HS256\",\n  \"typ\": \"JWT\"\n}"
    @State private var encodePayload: String = "{\n  \"sub\": \"1234567890\",\n  \"name\": \"John Doe\",\n  \"iat\": 1516239022\n}"
    @State private var encodedResult: String = ""
    @State private var showHistory = false
    @State private var jwtHistory: [JWTHistoryRecord] = []

    // Semantic colors tuned for dark backgrounds
    private let headerColor = Color.orange
    private let payloadColor = Color(red: 0.4, green: 0.6, blue: 1.0)
    private let signatureColor = Color(red: 0.7, green: 0.5, blue: 1.0)
    private let claimsColor = Color(red: 0.3, green: 0.85, blue: 0.5)

    public var body: some View {
        ToolWorkbench(
            eyebrow: "Token inspection",
            title: "JWT Workbench",
            description: "Decode claims or assemble unsigned tokens with the same two-column workbench and status language as the rest of the app.",
            systemImage: "key",
            statusItems: statusItems
        ) {
            StyledSegmentedPicker(
                options: Mode.allCases,
                selection: $mode,
                label: { $0.rawValue }
            )
            if mode == .decode {
                StyledButton("Sample JWT", systemImage: "doc.text") {
                    loadSampleJWT()
                }
            } else {
                StyledButton("Generate", systemImage: "key", variant: .primary) {
                    encodeJWT()
                }
                if !encodedResult.isEmpty {
                    CopyButton("Copy", text: encodedResult)
                }
            }
            StyledButton("History", systemImage: "clock.arrow.circlepath", variant: .secondary) {
                loadHistory()
                showHistory = true
            }
        } content: {
            Group {
                switch mode {
                case .decode:
                    decodeView
                case .encode:
                    encodeView
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .overlay {
            if showHistory {
                HistoryDrawer(
                    isPresented: $showHistory,
                    title: "JWT History",
                    items: jwtHistory,
                    onSelect: { record in restoreJWT(record) },
                    onDelete: { record in deleteJWTRecord(record) },
                    onClearAll: { clearJWTHistory() }
                )
            }
        }
    }

    private var statusItems: [ToolStatusItem] {
        var items = [ToolStatusItem(title: mode.rawValue, systemImage: "arrow.left.arrow.right", tint: AppTheme.accentBright)]
        if !errorMessage.isEmpty {
            items.append(ToolStatusItem(title: "Decode error", systemImage: "exclamationmark.triangle.fill", tint: AppTheme.error))
        }
        switch expirationStatus {
        case .valid:
            items.append(ToolStatusItem(title: "Token valid", systemImage: "checkmark.shield.fill", tint: AppTheme.success))
        case .expired:
            items.append(ToolStatusItem(title: "Token expired", systemImage: "xmark.shield.fill", tint: AppTheme.error))
        case .none:
            break
        }
        if mode == .encode && !encodedResult.isEmpty {
            items.append(ToolStatusItem(title: "Unsigned token generated", systemImage: "number", tint: AppTheme.accent))
        }
        return items
    }

    // MARK: - Section Title Helper

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    // MARK: - Decode View

    private var decodeView: some View {
        HSplitView {
            StyledPanel(title: "JWT Token") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    StyledTextEditor(text: $jwtInput, placeholder: "Paste JWT token here…")
                        .onChange(of: jwtInput) {
                            decodeJWT()
                        }

                    if !errorMessage.isEmpty {
                        ToolMessageBanner(systemImage: "exclamationmark.triangle.fill", message: errorMessage, tint: AppTheme.error)
                    } else {
                        ToolMessageBanner(systemImage: "info.bubble", message: "Header, payload and signature are decoded live as the token changes.", tint: AppTheme.accentBright)
                    }
                }
            }
            .frame(minWidth: 320)

            StyledPanel(title: "Decoded Sections") {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        decodedSection(
                            title: "Header",
                            content: headerJSON,
                            color: headerColor
                        )
                        decodedSection(
                            title: "Payload",
                            content: payloadJSON,
                            color: payloadColor
                        )
                        decodedSection(
                            title: "Signature",
                            content: signatureHex,
                            color: signatureColor
                        )

                        if expirationStatus != .none || !issuedAtText.isEmpty {
                            claimsInfoSection
                        }
                    }
                }
            }
            .frame(minWidth: 360)
        }
    }

    private func decodedSection(title: String, content: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if !content.isEmpty {
                    CopyButton("Copy", text: content)
                }
            }

            if content.isEmpty {
                Text("—")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(AppTheme.textMuted)
            } else {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(color)
                    .textSelection(.enabled)
                    .padding(AppTheme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(color.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            }
        }
    }

    private var claimsInfoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Circle()
                    .fill(claimsColor)
                    .frame(width: 8, height: 8)
                Text("Claims Info")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                if expirationStatus != .none {
                    HStack(spacing: 6) {
                        Text("Expiration:")
                            .fontWeight(.medium)
                            .foregroundStyle(AppTheme.textPrimary)
                        switch expirationStatus {
                        case .valid(let date):
                            Label("Valid — expires \(date.formatted())", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.success)
                        case .expired(let date):
                            Label("Expired — \(date.formatted())", systemImage: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.error)
                        case .none:
                            EmptyView()
                        }
                    }
                }

                if !issuedAtText.isEmpty {
                    HStack(spacing: 6) {
                        Text("Issued At:")
                            .fontWeight(.medium)
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(issuedAtText)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .font(.callout)
            .padding(AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                expirationStatus.isExpired
                    ? AppTheme.error.opacity(0.06)
                    : AppTheme.success.opacity(0.06)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        }
    }

    // MARK: - Encode View

    private var encodeView: some View {
        HSplitView {
            StyledPanel(title: "Header and Payload") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        sectionTitle("HEADER JSON")
                        StyledTextEditor(text: $encodeHeader, placeholder: "")
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        sectionTitle("PAYLOAD JSON")
                        StyledTextEditor(text: $encodePayload, placeholder: "")
                    }

                    ToolMessageBanner(systemImage: "sparkles", message: "Generation creates an unsigned token for debugging and payload inspection flows.", tint: AppTheme.accentBright)
                }
            }
            .frame(minWidth: 340)

            StyledPanel(title: "Encoded JWT") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    if encodedResult.isEmpty {
                        Spacer()
                        VStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "key.fill")
                                .font(.largeTitle)
                                .foregroundStyle(AppTheme.textMuted)
                            Text("Edit header and payload, then generate")
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        Text(encodedResult)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(AppTheme.textPrimary)
                            .textSelection(.enabled)
                            .padding(AppTheme.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.background.opacity(0.82))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))

                        ToolMessageBanner(systemImage: "number", message: "The signature placeholder stays as 'unsigned' by design.", tint: AppTheme.accent)
                    }
                }
            }
            .frame(minWidth: 360)
        }
    }

    // MARK: - JWT Decoding Logic

    private func decodeJWT() {
        let token = jwtInput.trimmingCharacters(in: .whitespacesAndNewlines)
        headerJSON = ""
        payloadJSON = ""
        signatureHex = ""
        expirationStatus = .none
        issuedAtText = ""
        errorMessage = ""

        guard !token.isEmpty else { return }

        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            errorMessage = "Invalid JWT format — expected 3 dot-separated parts, got \(parts.count)"
            return
        }

        // Decode header
        if let headerData = base64URLDecode(String(parts[0])),
           let headerObj = try? JSONSerialization.jsonObject(with: headerData),
           let prettyData = try? JSONSerialization.data(withJSONObject: headerObj, options: [.prettyPrinted, .sortedKeys]),
           let prettyStr = String(data: prettyData, encoding: .utf8) {
            headerJSON = prettyStr
        } else {
            errorMessage = "Failed to decode header"
            return
        }

        // Decode payload
        if let payloadData = base64URLDecode(String(parts[1])),
           let payloadObj = try? JSONSerialization.jsonObject(with: payloadData),
           let prettyData = try? JSONSerialization.data(withJSONObject: payloadObj, options: [.prettyPrinted, .sortedKeys]),
           let prettyStr = String(data: prettyData, encoding: .utf8) {
            payloadJSON = prettyStr

            // Extract claims
            if let dict = payloadObj as? [String: Any] {
                if let exp = dict["exp"] as? TimeInterval {
                    let expDate = Date(timeIntervalSince1970: exp)
                    if expDate < Date() {
                        expirationStatus = .expired(expDate)
                    } else {
                        expirationStatus = .valid(expDate)
                    }
                }
                if let iat = dict["iat"] as? TimeInterval {
                    let iatDate = Date(timeIntervalSince1970: iat)
                    issuedAtText = iatDate.formatted()
                }
            }
        } else {
            errorMessage = "Failed to decode payload"
            return
        }

        // Decode signature as hex
        if let sigData = base64URLDecode(String(parts[2])) {
            signatureHex = sigData.map { String(format: "%02x", $0) }.joined()
        } else {
            signatureHex = String(parts[2])
        }

        saveJWTHistory(mode: "Decode")
    }

    // MARK: - JWT Encoding Logic

    private func encodeJWT() {
        encodedResult = ""

        guard let headerData = encodeHeader.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: headerData) else {
            encodedResult = "Error: Invalid header JSON"
            return
        }

        guard let payloadData = encodePayload.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: payloadData) else {
            encodedResult = "Error: Invalid payload JSON"
            return
        }

        let headerB64 = base64URLEncode(headerData)
        let payloadB64 = base64URLEncode(payloadData)
        encodedResult = "\(headerB64).\(payloadB64).unsigned"

        saveJWTHistory(mode: "Encode")
    }

    // MARK: - Base64URL Helpers

    private func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - History Helpers

    private func saveJWTHistory(mode: String) {
        var expInfo = ""
        switch expirationStatus {
        case .valid(let date): expInfo = "Valid — expires \(date.formatted())"
        case .expired(let date): expInfo = "Expired — \(date.formatted())"
        case .none: expInfo = ""
        }

        let record = JWTHistoryRecord(
            id: UUID(),
            createdAt: Date(),
            mode: mode,
            jwtInput: mode == "Decode" ? jwtInput : encodedResult,
            headerJSON: mode == "Decode" ? headerJSON : encodeHeader,
            payloadJSON: mode == "Decode" ? payloadJSON : encodePayload,
            expirationInfo: expInfo
        )
        Task { try? await HistoryStore.shared.save(record) }
    }

    private func loadHistory() {
        Task {
            let records = (try? await HistoryStore.shared.listJWT()) ?? []
            await MainActor.run { jwtHistory = records }
        }
    }

    private func restoreJWT(_ record: JWTHistoryRecord) {
        if record.mode == "Decode" {
            mode = .decode
            jwtInput = record.jwtInput
        } else {
            mode = .encode
            encodeHeader = record.headerJSON
            encodePayload = record.payloadJSON
            encodedResult = ""
        }
    }

    private func deleteJWTRecord(_ record: JWTHistoryRecord) {
        Task {
            try? await HistoryStore.shared.deleteJWT(id: record.id)
            let records = (try? await HistoryStore.shared.listJWT()) ?? []
            await MainActor.run { jwtHistory = records }
        }
    }

    private func clearJWTHistory() {
        Task {
            try? await HistoryStore.shared.clear(category: .jwtTool)
            await MainActor.run { jwtHistory = [] }
        }
    }

    // MARK: - Sample Data

    private func loadSampleJWT() {
        // A well-known example JWT (HS256, not expired until 2033)
        // Header: {"alg":"HS256","typ":"JWT"}
        // Payload: {"sub":"1234567890","name":"John Doe","iat":1516239022,"exp":2000000000}
        let header = base64URLEncode("{\"alg\":\"HS256\",\"typ\":\"JWT\"}".data(using: .utf8)!)
        let payload = base64URLEncode("{\"sub\":\"1234567890\",\"name\":\"John Doe\",\"iat\":1516239022,\"exp\":2000000000}".data(using: .utf8)!)
        let signature = base64URLEncode("sample-signature-bytes".data(using: .utf8)!)
        jwtInput = "\(header).\(payload).\(signature)"
    }
}

// MARK: - Supporting Types

extension JWTToolView {
    enum Mode: String, CaseIterable {
        case decode = "Decode"
        case encode = "Encode"
    }

    enum ExpirationStatus: Equatable {
        case none
        case valid(Date)
        case expired(Date)

        var isExpired: Bool {
            if case .expired = self { return true }
            return false
        }
    }
}

// MARK: - Preview

#if DEBUG
struct JWTToolView_Previews: PreviewProvider {
    static var previews: some View {
        JWTToolView()
            .frame(width: 800, height: 600)
            .preferredColorScheme(.dark)
    }
}
#endif

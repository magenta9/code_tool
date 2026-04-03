import Foundation

/// An error that can provide a user-facing description.
/// Conform to this protocol in higher-level error types (e.g. API errors)
/// to decouple the observability layer from specific error implementations.
public protocol UserFacingError: Error {
    /// A human-readable description suitable for display in the UI,
    /// or `nil` to fall back to `localizedDescription`.
    var userFacingDescription: String? { get }
}

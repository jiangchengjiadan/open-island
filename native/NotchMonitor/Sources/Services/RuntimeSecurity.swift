import Foundation

enum RuntimeSecurity {
    /// Ephemeral capability shared only by this App process and the bridge child it launches.
    static let uiCapability = UUID().uuidString + UUID().uuidString
}

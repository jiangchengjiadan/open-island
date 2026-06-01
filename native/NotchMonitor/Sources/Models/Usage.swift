import Foundation

struct WindowUsage {
    let usedPercent: Double
    let resetAt: Date?
    let error: String?

    static let unknown = WindowUsage(usedPercent: 0, resetAt: nil, error: "no data")

    var percentInt: Int {
        Int((usedPercent * 100).rounded())
    }
}

struct AppUsage {
    var fiveHour: WindowUsage
    var weekly: WindowUsage
    var plan: String?

    static let empty = AppUsage(fiveHour: .unknown, weekly: .unknown, plan: nil)
}

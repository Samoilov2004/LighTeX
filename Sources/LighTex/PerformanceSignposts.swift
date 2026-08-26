import OSLog

enum LighTexPerformance {
    enum Interval {
        case syntaxHighlight
        case outlineParse
    }

    private static let log = OSLog(
        subsystem: "app.lightex.editor",
        category: .pointsOfInterest
    )

    static func begin(_ interval: Interval) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        switch interval {
        case .syntaxHighlight:
            os_signpost(.begin, log: log, name: "Syntax Highlight", signpostID: id)
        case .outlineParse:
            os_signpost(.begin, log: log, name: "Outline Parse", signpostID: id)
        }
        return id
    }

    static func end(_ interval: Interval, _ id: OSSignpostID) {
        switch interval {
        case .syntaxHighlight:
            os_signpost(.end, log: log, name: "Syntax Highlight", signpostID: id)
        case .outlineParse:
            os_signpost(.end, log: log, name: "Outline Parse", signpostID: id)
        }
    }
}

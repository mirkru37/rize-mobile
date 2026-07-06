import Foundation

/// UI display strings for `FocusSessionKind`/`FocusSessionStatus`, kept
/// separate from the `LocalStore` model files (which mirror the backend
/// schema and are not view-layer concerns).
extension FocusSessionKind {
    var displayName: String {
        switch self {
        case .focus:
            "Focus"
        case .breakTime:
            "Break"
        case .meeting:
            "Meeting"
        }
    }
}

extension FocusSessionStatus {
    var displayName: String {
        switch self {
        case .running:
            "Running"
        case .completed:
            "Completed"
        case .abandoned:
            "Abandoned"
        }
    }
}

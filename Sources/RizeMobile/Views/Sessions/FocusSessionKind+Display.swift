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

    /// Tier C sub-label per [[architecture-mobile.md]] §6 (UX Honesty
    /// Requirement): distinguishes an exact focus session from an exact
    /// manual timer (break/meeting), so the dashboard never implies either
    /// is automatically inferred device activity.
    var tierBadge: String {
        switch self {
        case .focus:
            "Focus"
        case .breakTime, .meeting:
            "Manual"
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

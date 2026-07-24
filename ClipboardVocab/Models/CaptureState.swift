/// Whether clipboard capture is currently running.
/// Always starts as `.active` on every app launch (FR-020); never persisted.
enum CaptureState {
    case active
    case paused
}

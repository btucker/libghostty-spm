import Foundation

/// How often a mounted terminal surface runs its render tick.
/// Embedders drop quiet-but-visible terminals to `.reduced` (~1 fps)
/// to coalesce repeated Metal render wakeups while a surface is idle.
public enum TerminalRenderPace: Equatable, Sendable {
    /// Run every requested render tick (default).
    case full
    /// Coalesce requested render ticks to at most once per `interval` seconds.
    case reduced(interval: TimeInterval)
}

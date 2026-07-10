import Foundation

/// How often a mounted terminal surface runs its render tick.
/// Embedders drop quiet-but-visible terminals to `.reduced` (~1 fps)
/// to stop the display-link-driven Metal pipeline from redrawing an
/// unchanged screen at native refresh rate.
public enum TerminalRenderPace: Equatable, Sendable {
    /// Run the full tick body on every display-link fire (default).
    case full
    /// Run the tick body at most once per `interval` seconds.
    case reduced(interval: TimeInterval)
}

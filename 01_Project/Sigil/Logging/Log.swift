import OSLog

/// Centralized `os.Logger` instances. Filter Console.app by subsystem
/// `com.lucesumbrarum.sigil` and a category to diagnose field issues:
///
///     log stream --predicate 'subsystem == "com.lucesumbrarum.sigil"'
///     log stream --predicate 'subsystem == "com.lucesumbrarum.sigil" AND category == "mount"'
enum Log {
    private static let subsystem = "com.lucesumbrarum.sigil"

    /// Mount / unmount events and smart-silent re-apply outcomes.
    static let mount = Logger(subsystem: subsystem, category: "mount")

    /// VolumeStore load/save, IconCache, IconApplier disk ops.
    static let io = Logger(subsystem: subsystem, category: "io")

    /// Icon rendering pipeline (normalize / iconset / iconutil / apply).
    static let render = Logger(subsystem: subsystem, category: "render")

    /// User-initiated actions (apply / reset / forget / conflict resolution).
    static let ui = Logger(subsystem: subsystem, category: "ui")
}

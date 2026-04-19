import Foundation

/// Thin wrapper around POSIX extended-attribute syscalls (`setxattr`, `getxattr`,
/// `removexattr`). Used by `IconApplier` to read/write `com.apple.FinderInfo`
/// on volume roots. No caching — each call is a direct syscall.
enum XAttr {

    enum Error: LocalizedError {
        case operationFailed(name: String, path: String, errno: Int32)

        var errorDescription: String? {
            switch self {
            case .operationFailed(let name, let path, let errno):
                let msg = String(cString: strerror(errno))
                return "xattr '\(name)' on \(path): \(msg) (errno \(errno))"
            }
        }

        var errnoValue: Int32 {
            switch self {
            case .operationFailed(_, _, let e): return e
            }
        }
    }

    // MARK: - Set

    /// Write an extended attribute.
    /// - Parameters:
    ///   - name: e.g. `"com.apple.FinderInfo"`
    ///   - value: exact bytes to store
    ///   - path: filesystem path (file or directory, including volume roots)
    ///   - followSymlinks: when `false`, operates on the link itself (`XATTR_NOFOLLOW`)
    static func set(
        name: String,
        value: Data,
        on path: String,
        followSymlinks: Bool = true
    ) throws {
        let options: Int32 = followSymlinks ? 0 : XATTR_NOFOLLOW
        let result = value.withUnsafeBytes { raw -> Int32 in
            setxattr(path, name, raw.baseAddress, value.count, 0, options)
        }
        if result != 0 {
            throw Error.operationFailed(name: name, path: path, errno: errno)
        }
    }

    // MARK: - Get

    /// Read an extended attribute. Returns `nil` if the attribute is not present.
    static func get(
        name: String,
        from path: String,
        followSymlinks: Bool = true
    ) throws -> Data? {
        let options: Int32 = followSymlinks ? 0 : XATTR_NOFOLLOW
        let size = getxattr(path, name, nil, 0, 0, options)
        if size < 0 {
            if errno == ENOATTR { return nil }
            throw Error.operationFailed(name: name, path: path, errno: errno)
        }
        guard size > 0 else { return Data() }

        var buffer = [UInt8](repeating: 0, count: size)
        let read = buffer.withUnsafeMutableBytes { raw -> ssize_t in
            getxattr(path, name, raw.baseAddress, size, 0, options)
        }
        if read < 0 {
            throw Error.operationFailed(name: name, path: path, errno: errno)
        }
        return Data(buffer.prefix(read))
    }

    // MARK: - Remove

    /// Remove an extended attribute. Silently succeeds if the attribute is
    /// already absent (ENOATTR is treated as a no-op).
    static func remove(
        name: String,
        from path: String,
        followSymlinks: Bool = true
    ) throws {
        let options: Int32 = followSymlinks ? 0 : XATTR_NOFOLLOW
        let result = removexattr(path, name, options)
        if result != 0 {
            if errno == ENOATTR { return }
            throw Error.operationFailed(name: name, path: path, errno: errno)
        }
    }
}

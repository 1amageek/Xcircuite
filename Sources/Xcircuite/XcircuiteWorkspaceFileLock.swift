import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Cross-process advisory lock for mutations inside one `.xcircuite` workspace.
///
/// Actor isolation orders calls made through one store instance. The file lock
/// additionally orders independent store instances and separate processes.
struct XcircuiteWorkspaceFileLock: Sendable {
    static func withExclusiveLock<T>(
        at lockURL: URL,
        _ operation: () throws -> T
    ) throws -> T {
        let descriptor = open(lockURL.path(percentEncoded: false), O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            throw XcircuiteWorkspaceStoreError.lockFailed(
                String(cString: strerror(errno))
            )
        }
        defer { close(descriptor) }

        guard flock(descriptor, LOCK_EX) == 0 else {
            throw XcircuiteWorkspaceStoreError.lockFailed(
                String(cString: strerror(errno))
            )
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}

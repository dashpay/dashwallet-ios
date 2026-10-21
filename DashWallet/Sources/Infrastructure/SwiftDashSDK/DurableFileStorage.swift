import Foundation

/// Shared durability barrier for intent files and the directories naming them.
enum DurableFileStorage {
    /// `F_FULLFSYNC` on the file or directory: the strongest flush the
    /// platform offers (an `fsync` alone may stop at the drive cache).
    static func flush(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(fd) }
        if fcntl(fd, F_FULLFSYNC) < 0, fsync(fd) < 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

}

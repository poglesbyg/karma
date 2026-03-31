import Foundation

enum PermissionManager {
    /// Returns true if the app can read ~/Library/Messages/chat.db (Full Disk Access granted).
    /// This is the standard check — FDA is the only way to make chat.db readable by third-party apps.
    static func checkFullDiskAccess() -> Bool {
        let path = NSHomeDirectory() + "/Library/Messages/chat.db"
        return FileManager.default.isReadableFile(atPath: path)
    }
}

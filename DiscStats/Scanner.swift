import Foundation
import SwiftUI
import Darwin

final class ScanProgress: ObservableObject {
    @Published var filesScanned: Int = 0
    @Published var bytesSeen: Int64 = 0
    @Published var currentPath: String = ""
    @Published var isScanning: Bool = false
    @Published var root: FileNode? = nil
    @Published var scanStart: Date? = nil
    @Published var scanElapsed: TimeInterval = 0
    @Published var dataVersion: Int = 0  // bump to force redraws after tree mutations

    private let lock = NSLock()
    private var _cancelled = false
    var cancelled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _cancelled }
        set { lock.lock(); _cancelled = newValue; lock.unlock() }
    }
}

enum Scanner {
    static func startScan(url: URL, progress: ScanProgress) {
        let start = Date()
        progress.isScanning = true
        progress.cancelled = false
        progress.filesScanned = 0
        progress.bytesSeen = 0
        progress.currentPath = ""
        progress.root = nil
        progress.scanStart = start
        progress.scanElapsed = 0
        progress.dataVersion &+= 1

        DispatchQueue.global(qos: .userInitiated).async {
            var counter = Counter(start: start)
            let node = scanSync(url: url,
                                parent: nil,
                                progress: progress,
                                counter: &counter)
            let wasCancelled = progress.cancelled
            let elapsed = Date().timeIntervalSince(start)
            DispatchQueue.main.async {
                progress.filesScanned = counter.files
                progress.bytesSeen = counter.bytes
                progress.currentPath = ""
                progress.scanElapsed = elapsed
                progress.isScanning = false
                progress.root = wasCancelled ? nil : node
                progress.dataVersion &+= 1
            }
        }
    }

    private struct Counter {
        var files: Int = 0
        var bytes: Int64 = 0
        var lastReport: Date = .init(timeIntervalSince1970: 0)
        var start: Date = Date()
        var seen: Set<InodeKey> = []
        var duplicates: Int = 0
    }

    /// A (device, inode) pair uniquely identifies a filesystem object on macOS.
    /// Used to skip files reached more than once — APFS firmlinks reroute paths
    /// like `/Users` and `/System/Volumes/Data/Users` to the same inodes, and
    /// hard links produce multiple paths to the same content.
    struct InodeKey: Hashable {
        let dev: Int32
        let ino: UInt64
    }

    private static func inodeKey(at path: String) -> InodeKey? {
        var st = stat()
        let rc = path.withCString { lstat($0, &st) }
        guard rc == 0 else { return nil }
        return InodeKey(dev: st.st_dev, ino: st.st_ino)
    }

    private static func scanSync(url: URL,
                                 parent: FileNode?,
                                 progress: ScanProgress,
                                 counter: inout Counter) -> FileNode {
        let fm = FileManager.default
        let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent

        if progress.cancelled {
            return FileNode(url: url, name: name, isDirectory: false, size: 0, parent: parent)
        }

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return FileNode(url: url, name: name, isDirectory: false, size: 0, parent: parent)
        }

        // Skip symlinks entirely so we don't double-count or loop
        if let v = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           v.isSymbolicLink == true {
            return FileNode(url: url, name: name, isDirectory: false, size: 0, parent: parent)
        }

        // Dedup by (device, inode). Catches APFS firmlinks (so e.g. /Users and
        // /System/Volumes/Data/Users don't both count), hard links, and any
        // other situation where two paths resolve to the same on-disk object.
        if let key = inodeKey(at: url.path) {
            let inserted = counter.seen.insert(key).inserted
            if !inserted {
                counter.duplicates += 1
                return FileNode(url: url, name: name,
                                isDirectory: isDir.boolValue,
                                size: 0, parent: parent)
            }
        }

        if !isDir.boolValue {
            let size = fileSize(at: url)
            counter.files += 1
            counter.bytes += size
            reportProgress(counter: &counter, path: url.path, progress: progress)
            return FileNode(url: url, name: name, isDirectory: false, size: size, parent: parent)
        }

        let node = FileNode(url: url, name: name, isDirectory: true, size: 0, parent: parent)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let contents = try? fm.contentsOfDirectory(at: url,
                                                         includingPropertiesForKeys: keys,
                                                         options: []) else {
            return node
        }

        var total: Int64 = 0
        var totalItems: Int = 1  // include this directory itself
        var children: [FileNode] = []
        children.reserveCapacity(contents.count)
        for child in contents {
            if progress.cancelled { break }
            let childNode = scanSync(url: child, parent: node, progress: progress, counter: &counter)
            total += childNode.size
            totalItems += childNode.itemCount
            children.append(childNode)
        }
        node.size = total
        node.itemCount = totalItems
        node.children = children.sorted { $0.size > $1.size }
        return node
    }

    private static func fileSize(at url: URL) -> Int64 {
        if let vals = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) {
            if let s = vals.totalFileAllocatedSize { return Int64(s) }
            if let s = vals.fileSize { return Int64(s) }
        }
        return 0
    }

    private static func reportProgress(counter: inout Counter, path: String, progress: ScanProgress) {
        let now = Date()
        if now.timeIntervalSince(counter.lastReport) > 0.1 {
            counter.lastReport = now
            let files = counter.files
            let bytes = counter.bytes
            let elapsed = Date().timeIntervalSince(counter.start)
            DispatchQueue.main.async {
                progress.filesScanned = files
                progress.bytesSeen = bytes
                progress.currentPath = path
                progress.scanElapsed = elapsed
            }
        }
    }
}

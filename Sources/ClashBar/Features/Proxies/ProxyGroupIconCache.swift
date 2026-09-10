import AppKit
import CryptoKit
import ImageIO
import MihomoKit
import SwiftUI

actor ProxyGroupIconCache {
    static let shared = ProxyGroupIconCache(
        iconDirectory: WorkingDirectoryManager().iconDirectoryURL,
        session: URLSessionFactory.makeEphemeralSession(
            requestTimeout: 15,
            resourceTimeout: 30,
            maxConnectionsPerHost: 4))

    private let diskDirectory: URL
    private let session: URLSession
    private let memoryCache = NSCache<NSURL, NSData>()
    private var inFlightRequests: [URL: Task<Data?, Never>] = [:]

    init(iconDirectory: URL, session: URLSession) {
        self.diskDirectory = iconDirectory
        self.session = session
        self.memoryCache.countLimit = 128
    }

    func imageData(for url: URL) async -> Data? {
        if let data = self.memoryCache.object(forKey: url as NSURL) {
            return data as Data
        }

        let fileURL = self.cacheFileURL(for: url)
        if let data = self.validImageData(at: fileURL) {
            self.remember(data, for: url)
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
            return data
        }

        let data: Data?
        if let task = self.inFlightRequests[url] {
            data = await task.value
        } else {
            let task = Task { [session = self.session] in
                await Self.downloadImageData(from: url, session: session)
            }
            self.inFlightRequests[url] = task
            data = await task.value
            self.inFlightRequests[url] = nil
        }
        guard !Task.isCancelled, let data else { return nil }

        if let cached = self.memoryCache.object(forKey: url as NSURL) {
            return cached as Data
        }
        self.remember(data, for: url)
        self.persist(data, to: fileURL)
        self.trimDiskCacheIfNeeded()
        return data
    }

    private func remember(_ data: Data, for url: URL) {
        self.memoryCache.setObject(data as NSData, forKey: url as NSURL)
    }

    private func cacheFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let fileName = digest.map { String(format: "%02x", $0) }.joined()
        return self.diskDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private func validImageData(at fileURL: URL) -> Data? {
        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
              data.count <= 2 * 1024 * 1024,
              Self.isValidImageData(data)
        else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return data
    }

    private func persist(_ data: Data, to fileURL: URL) {
        do {
            try FileManager.default.createDirectory(at: self.diskDirectory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {}
    }

    private func trimDiskCacheIfNeeded() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: self.diskDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles])
        else { return }

        var entries: [(url: URL, modifiedAt: Date, size: Int)] = []
        var totalBytes = 0
        for url in files {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            let size = max(0, values.fileSize ?? 0)
            entries.append((url, values.contentModificationDate ?? .distantPast, size))
            totalBytes += size
        }

        guard entries.count > 128 || totalBytes > 20 * 1024 * 1024 else { return }
        entries.sort { $0.modifiedAt < $1.modifiedAt }
        var remainingCount = entries.count
        for entry in entries {
            guard remainingCount > 128 || totalBytes > 20 * 1024 * 1024 else { break }
            guard (try? FileManager.default.removeItem(at: entry.url)) != nil else { continue }
            remainingCount -= 1
            totalBytes -= entry.size
        }
    }

    private static func downloadImageData(from url: URL, session: URLSession) async -> Data? {
        let maximumBytes = 2 * 1024 * 1024
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode),
                  response.expectedContentLength <= Int64(maximumBytes)
            else { return nil }

            var data = Data()
            data.reserveCapacity(max(0, Int(response.expectedContentLength)))
            for try await byte in bytes {
                guard data.count < maximumBytes else { return nil }
                data.append(byte)
            }
            return Self.isValidImageData(data) ? data : nil
        } catch {
            return nil
        }
    }

    private static func isValidImageData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }
}

extension EnvironmentValues {
    @Entry var proxyGroupIconCache: ProxyGroupIconCache = .shared
}

struct ProxyGroupIconView: View {
    let url: URL

    @Environment(\.proxyGroupIconCache) private var iconCache
    @State private var nsImage: NSImage?

    var body: some View {
        ZStack {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            }
        }
        .task(id: self.url) {
            guard let data = await self.iconCache.imageData(for: self.url) else {
                self.nsImage = nil
                return
            }
            self.nsImage = NSImage(data: data)
        }
    }
}

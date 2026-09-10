import Darwin
import Foundation

@MainActor
final class ConfigurationDirectoryObserver {
    struct Changes {
        let files: [URL]
        let fileNames: Set<String>
    }

    private let queue = DispatchQueue(label: "com.clashbar.config-monitor", qos: .utility)
    private var directorySource: DispatchSourceFileSystemObject?
    private var selectedFileSource: DispatchSourceFileSystemObject?
    private(set) var selectedFileURL: URL?
    private var debounceTask: Task<Void, Never>?
    private var signatures: [String: String] = [:]
    private var generation = 0
    private var onChange: (@MainActor () async -> Void)?

    var isMonitoring: Bool {
        self.directorySource != nil
    }

    func start(
        directoryURL: URL,
        files: [URL],
        selectedFileURL: URL?,
        onChange: @escaping @MainActor () async -> Void)
    {
        guard !self.isMonitoring else { return }
        self.signatures = Self.fileSignatures(for: files)
        self.onChange = onChange
        self.selectedFileURL = selectedFileURL

        let trigger: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }

        self.directorySource = Self.makeSource(
            url: directoryURL,
            events: [.write, .delete, .extend, .attrib, .link, .rename, .revoke],
            queue: self.queue,
            onChange: trigger)
        self.updateSelectedFile(selectedFileURL)
    }

    func updateSelectedFile(_ fileURL: URL?) {
        self.selectedFileURL = fileURL
        self.selectedFileSource?.cancel()
        guard let fileURL else {
            self.selectedFileSource = nil
            return
        }
        let trigger: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                if let current = self?.selectedFileURL {
                    self?.updateSelectedFile(current)
                }
                self?.scheduleRefresh()
            }
        }
        self.selectedFileSource = Self.makeSource(
            url: fileURL,
            events: [.write, .delete, .extend, .attrib, .rename, .revoke],
            queue: self.queue,
            onChange: trigger)
    }

    func scheduleRefresh(delayNanoseconds: UInt64 = 350_000_000) {
        guard let onChange else { return }
        self.debounceTask?.cancel()
        self.debounceTask = Task { [weak self] in
            guard await (try? Task.sleep(nanoseconds: delayNanoseconds)) != nil else { return }
            self?.debounceTask = nil
            await onChange()
        }
    }

    func scanChanges(in directoryURL: URL) async -> Changes? {
        let generation = self.generation
        let scan = await Task.detached(priority: .utility) {
            let files = ConfigurationStore.scanConfigFiles(in: directoryURL)
            return (files, Self.fileSignatures(for: files))
        }.value
        guard !Task.isCancelled, generation == self.generation else { return nil }
        let allNames = Set(self.signatures.keys).union(scan.1.keys)
        let changedNames = Set(allNames.filter { self.signatures[$0] != scan.1[$0] })
        self.signatures = scan.1
        return Changes(files: scan.0, fileNames: changedNames)
    }

    func stop() {
        self.generation += 1
        self.directorySource?.cancel()
        self.directorySource = nil
        self.selectedFileSource?.cancel()
        self.selectedFileSource = nil
        self.debounceTask?.cancel()
        self.debounceTask = nil
        self.signatures = [:]
        self.onChange = nil
    }

    private nonisolated static func makeSource(
        url: URL,
        events: DispatchSource.FileSystemEvent,
        queue: DispatchQueue,
        onChange: @escaping @Sendable () -> Void) -> DispatchSourceFileSystemObject?
    {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: events,
            queue: queue)
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private nonisolated static func fileSignatures(for files: [URL]) -> [String: String] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        var snapshot: [String: String] = [:]
        for fileURL in files {
            let resolved = fileURL.resolvingSymlinksInPath()
            let values = try? resolved.resourceValues(forKeys: keys)
            let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = values?.fileSize ?? -1
            snapshot[fileURL.lastPathComponent] = "\(modifiedAt)-\(size)"
        }
        return snapshot
    }

    isolated deinit {
        self.stop()
    }
}

import CoreServices
import Foundation

final class ProjectFileMonitor: @unchecked Sendable {
    private let rootURL: URL
    private let callback: @MainActor () -> Void
    private let queue = DispatchQueue(label: "app.lightex.project-file-monitor", qos: .utility)
    private var stream: FSEventStreamRef?
    private var pendingCallback: DispatchWorkItem?

    init(rootURL: URL, callback: @escaping @MainActor () -> Void) {
        self.rootURL = rootURL.standardizedFileURL
        self.callback = callback
    }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let eventCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<ProjectFileMonitor>
                .fromOpaque(info)
                .takeUnretainedValue()
                .scheduleCallback()
        }
        guard let stream = FSEventStreamCreate(
            nil,
            eventCallback,
            &context,
            [rootURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
                | FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
                | FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        ) else {
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        pendingCallback?.cancel()
        pendingCallback = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleCallback() {
        pendingCallback?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor [callback] in
                callback()
            }
        }
        pendingCallback = work
        queue.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    deinit {
        stop()
    }
}

import Foundation

final class RuntimeDownloadClient: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var destinationURL: URL?
    private var progressHandler: (@Sendable (RuntimeDownloadProgress) -> Void)?
    private var task: URLSessionDownloadTask?
    private var downloadedURL: URL?
    private var startedAt = Date()

    private lazy var session = URLSession(
        configuration: .ephemeral,
        delegate: self,
        delegateQueue: nil
    )

    func download(
        from sourceURL: URL,
        to destinationURL: URL,
        expectedBytes: Int64? = nil,
        progress: @escaping @Sendable (RuntimeDownloadProgress) -> Void
    ) async throws -> URL {
        if sourceURL.isFileURL {
            let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
            let actualSize = Int64(values.fileSize ?? 0)
            let reportedSize = expectedBytes ?? actualSize
            let demoSeconds = ProcessInfo.processInfo.environment["LIGHTEX_RUNTIME_DEMO_DOWNLOAD_SECONDS"]
                .flatMap(Double.init) ?? 0
            let startedAt = Date()

            if demoSeconds > 0 {
                let steps = 40
                for step in 1...steps {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .seconds(demoSeconds / Double(steps)))
                    let received = reportedSize * Int64(step) / Int64(steps)
                    let elapsed = max(0.1, Date().timeIntervalSince(startedAt))
                    let displayedSpeed = min(48_000_000, Double(received) / elapsed)
                    progress(RuntimeDownloadProgress(
                        receivedBytes: received,
                        totalBytes: reportedSize,
                        bytesPerSecond: displayedSpeed
                    ))
                }
            }

            try Task.checkCancellation()
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            if demoSeconds <= 0 {
                progress(RuntimeDownloadProgress(
                    receivedBytes: reportedSize,
                    totalBytes: reportedSize,
                    bytesPerSecond: Double(reportedSize)
                ))
            }
            return destinationURL
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                self.destinationURL = destinationURL
                progressHandler = progress
                startedAt = Date()
                let task = session.downloadTask(with: sourceURL)
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        lock.lock()
        let task = task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        let handler = progressHandler
        let elapsed = max(0.1, Date().timeIntervalSince(startedAt))
        lock.unlock()
        handler?(RuntimeDownloadProgress(
            receivedBytes: totalBytesWritten,
            totalBytes: totalBytesExpectedToWrite,
            bytesPerSecond: Double(totalBytesWritten) / elapsed
        ))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        guard let destinationURL else {
            lock.unlock()
            return
        }
        lock.unlock()

        do {
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: destinationURL)
            try fileManager.moveItem(at: location, to: destinationURL)
            lock.lock()
            downloadedURL = destinationURL
            lock.unlock()
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
            return
        }
        lock.lock()
        let downloadedURL = downloadedURL
        lock.unlock()
        if let downloadedURL {
            finish(.success(downloadedURL))
        } else {
            finish(.failure(URLError(.cannotCreateFile)))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        task = nil
        destinationURL = nil
        progressHandler = nil
        downloadedURL = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

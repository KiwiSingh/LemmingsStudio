import Foundation

final class SampleLibraryDownload: NSObject,
    URLSessionDataDelegate,
    @unchecked Sendable
{
    typealias ProgressHandler = @Sendable (Int64, Int64) -> Void

    private let destinationURL: URL
    private let partialURL: URL
    private let progressHandler: ProgressHandler

    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var output: FileHandle?
    private var receivedBytes: Int64 = 0
    private var expectedBytes: Int64 = 0
    private var completed = false

    private init(
        destinationURL: URL,
        progressHandler: @escaping ProgressHandler
    ) {
        self.destinationURL = destinationURL
        self.partialURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "." + destinationURL.lastPathComponent + ".part"
            )
        self.progressHandler = progressHandler
        super.init()
    }

    static func download(
        from url: URL,
        directlyTo destinationURL: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        let delegate = SampleLibraryDownload(
            destinationURL: destinationURL,
            progressHandler: progress
        )

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            delegate.continuation = continuation

            do {
                try FileManager.default.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                if FileManager.default.fileExists(
                    atPath: delegate.partialURL.path
                ) {
                    try FileManager.default.removeItem(
                        at: delegate.partialURL
                    )
                }

                FileManager.default.createFile(
                    atPath: delegate.partialURL.path,
                    contents: nil
                )

                delegate.output = try FileHandle(
                    forWritingTo: delegate.partialURL
                )

                let configuration =
                    URLSessionConfiguration.default
                configuration.waitsForConnectivity = true
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource =
                    60 * 60 * 6

                let session = URLSession(
                    configuration: configuration,
                    delegate: delegate,
                    delegateQueue: nil
                )
                delegate.session = session

                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                session.dataTask(with: request).resume()
            } catch {
                delegate.finish(throwing: error)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler:
            @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            completionHandler(.cancel)
            finish(
                throwing: NSError(
                    domain: "LemmingsStudio.SampleLibraryDownload",
                    code: http.statusCode,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Server returned HTTP \(http.statusCode)."
                    ]
                )
            )
            return
        }

        expectedBytes = max(0, response.expectedContentLength)
        progressHandler(receivedBytes, expectedBytes)
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard !completed else { return }

        do {
            try output?.write(contentsOf: data)
            receivedBytes += Int64(data.count)
            progressHandler(receivedBytes, expectedBytes)
        } catch {
            session.invalidateAndCancel()
            finish(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(throwing: error)
            return
        }

        guard !completed else { return }

        do {
            try output?.synchronize()
            try output?.close()
            output = nil

            if FileManager.default.fileExists(
                atPath: destinationURL.path
            ) {
                try FileManager.default.removeItem(
                    at: destinationURL
                )
            }

            try FileManager.default.moveItem(
                at: partialURL,
                to: destinationURL
            )

            progressHandler(
                receivedBytes,
                expectedBytes > 0
                    ? expectedBytes
                    : receivedBytes
            )

            finish()
        } catch {
            finish(throwing: error)
        }
    }

    private func finish(throwing error: Error? = nil) {
        guard !completed else { return }
        completed = true

        try? output?.close()
        output = nil

        if error != nil {
            try? FileManager.default.removeItem(
                at: partialURL
            )
        }

        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }

        continuation = nil
        session?.finishTasksAndInvalidate()
        session = nil
    }
}

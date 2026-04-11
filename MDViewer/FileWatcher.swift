import Foundation

/// Watches a markdown file for external edits and invokes a callback with
/// the new contents. Re-creates the underlying DispatchSource after each
/// event because editors commonly save via write-to-temp + rename, which
/// replaces the inode and invalidates the fd.
@MainActor
final class FileWatcher: ObservableObject {
    private var source: DispatchSourceFileSystemObject?
    private var watchedURL: URL?
    private var onChange: ((String) -> Void)?

    func watch(_ url: URL, onChange: @escaping (String) -> Void) {
        // If already watching the same URL, just update the callback.
        if watchedURL == url {
            self.onChange = onChange
            return
        }
        stop()
        watchedURL = url
        self.onChange = onChange
        start(url)
    }

    func stop() {
        source?.cancel()
        source = nil
        watchedURL = nil
        onChange = nil
    }

    deinit {
        source?.cancel()
    }

    private func start(_ url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main
        )
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                // Small delay — editors may still be writing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard let self, let watchedURL = self.watchedURL else { return }
                    if case let .success(text) = MarkdownRenderer.readMarkdownFile(at: watchedURL) {
                        self.onChange?(text)
                    }
                    // Re-watch: write-to-temp + rename replaces the inode,
                    // invalidating this watcher.
                    self.source?.cancel()
                    self.source = nil
                    self.start(watchedURL)
                }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }
}

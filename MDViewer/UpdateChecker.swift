import AppKit

enum UpdateChecker {
    private static let releasesURL = URL(string: "https://api.github.com/repos/ff2248/md-viewer/releases/latest")!

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func check() {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: releasesURL)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String,
                      let htmlURL = json["html_url"] as? String
                else {
                    await showAlert(title: "Update Check Failed", message: "Unexpected server response.")
                    return
                }

                let remote = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

                if compareVersions(remote, isNewerThan: currentVersion) {
                    await showNewVersionAlert(version: remote, url: htmlURL)
                } else {
                    await showAlert(title: "You're up to date", message: "MDViewer v\(currentVersion) is the latest version.")
                }
            } catch {
                await showAlert(title: "Update Check Failed", message: "Please check your network connection and try again.")
            }
        }
    }

    private static func compareVersions(_ remote: String, isNewerThan current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0 ..< max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }

    @MainActor
    private static func showNewVersionAlert(version: String, url: String) {
        let alert = NSAlert()
        alert.messageText = "MDViewer v\(version) is available"
        alert.informativeText = "You're using v\(currentVersion). Would you like to go to the download page?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn, let downloadURL = URL(string: url) {
            NSWorkspace.shared.open(downloadURL)
        }
    }

    @MainActor
    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}

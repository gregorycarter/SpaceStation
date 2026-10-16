import Foundation

/// A published release on GitHub.
struct ReleaseInfo: Equatable {
    let tag: String
    /// The tag without a leading "v", e.g. "1.2.0".
    let version: String
    let name: String
    /// Always a github.com page for this repository (see `UpdateChecker.isTrustedReleaseURL`).
    let url: URL
}

enum UpdateStatus: Equatable {
    case upToDate(currentVersion: String)
    case available(ReleaseInfo)
    /// The repository has no published (non-draft, non-prerelease) release yet.
    case noReleases
    case failed(String)
}

enum UpdateVersion {
    /// The numeric parts of a version or tag: "v1.2.3-beta" gives [1, 2, 3]. Nil if there are none.
    static func components(_ string: String) -> [Int]? {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        let core = text.prefix { $0.isNumber || $0 == "." }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        return parts.compactMap { $0 }
    }

    /// True for a tag like "1.2.0-beta" (anything after the numeric core).
    static func hasPrereleaseSuffix(_ string: String) -> Bool {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        return text.contains { !($0.isNumber || $0 == ".") }
    }

    /// Whether `candidate` is a newer version than `current`. Unparseable versions are never newer.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard var a = components(candidate), var b = components(current) else { return false }
        let count = max(a.count, b.count)
        a += Array(repeating: 0, count: count - a.count)
        b += Array(repeating: 0, count: count - b.count)
        if a != b { return a.lexicographicallyPrecedes(b) ? false : true }
        // Same numbers: a final release is newer than the pre-release you are running, not vice versa.
        return hasPrereleaseSuffix(current) && !hasPrereleaseSuffix(candidate)
    }
}

/// Looks for a newer release on GitHub.
///
/// This is the app's only network use. It runs when the user clicks Check for Updates, or, if they
/// turn it on (off by default), at most once a day at launch. It sends one anonymous HTTPS GET to
/// GitHub's public releases API, with nothing but a generic user agent, and never downloads or
/// installs anything: it only offers a link to the release page.
@MainActor
final class UpdateChecker: ObservableObject {
    typealias Fetch = (URLRequest) async throws -> (Data, URLResponse)

    nonisolated static let repository = "gregorycarter/SpaceStation"
    nonisolated static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!
    nonisolated static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    nonisolated static let lastCheckKey = "lastUpdateCheck"
    nonisolated static let availableUpdateKey = "availableUpdate"
    nonisolated static let automaticInterval: TimeInterval = 24 * 60 * 60

    @Published private(set) var availableUpdate: ReleaseInfo?
    @Published private(set) var status: UpdateStatus?
    @Published private(set) var isChecking = false

    private let currentVersion: String
    private let defaults: UserDefaults
    private let now: () -> Date
    private let fetch: Fetch
    private var inFlight: Task<UpdateStatus, Never>?

    /// - Parameters are injectable so tests never touch the network: `fetch` defaults to a real
    ///   HTTPS request and `currentVersion` to the running app's version.
    init(currentVersion: String? = nil,
         defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         fetch: Fetch? = nil) {
        self.currentVersion = currentVersion ?? Self.bundleVersion
        self.defaults = defaults
        self.now = now
        self.fetch = fetch ?? Self.liveFetch
        availableUpdate = Self.loadStoredUpdate(from: defaults, currentVersion: self.currentVersion)
    }

    // MARK: - Remembering a found update

    /// An update found earlier is kept so the notice survives a relaunch. It is dropped as soon as it
    /// is no longer newer than the running version (i.e. you installed it) or its link isn't trusted.
    nonisolated static func loadStoredUpdate(from defaults: UserDefaults, currentVersion: String) -> ReleaseInfo? {
        guard let stored = defaults.dictionary(forKey: availableUpdateKey),
              let tag = stored["tag"] as? String, let version = stored["version"] as? String,
              let name = stored["name"] as? String, let urlString = stored["url"] as? String,
              let url = URL(string: urlString), isTrustedReleaseURL(url),
              UpdateVersion.isNewer(version, than: currentVersion) else {
            defaults.removeObject(forKey: availableUpdateKey)
            return nil
        }
        return ReleaseInfo(tag: tag, version: version, name: name, url: url)
    }

    private func store(_ release: ReleaseInfo?) {
        if let release {
            defaults.set(["tag": release.tag, "version": release.version, "name": release.name,
                          "url": release.url.absoluteString], forKey: Self.availableUpdateKey)
        } else {
            defaults.removeObject(forKey: Self.availableUpdateKey)
        }
    }

    nonisolated static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - Checking

    /// Checks now (the user asked). Concurrent calls share the result of the one in flight.
    @discardableResult
    func check() async -> UpdateStatus {
        if let inFlight { return await inFlight.value }
        isChecking = true
        let task = Task { @MainActor in
            defer {
                inFlight = nil
                isChecking = false
            }
            let result = await performCheck()
            record(result)
            return result
        }
        inFlight = task
        return await task.value
    }

    /// Publish and persist once per request, regardless of how many callers await it.
    private func record(_ result: UpdateStatus) {
        status = result
        switch result {
        case .available(let release):
            availableUpdate = release
            store(release)
        case .upToDate, .noReleases:
            availableUpdate = nil
            store(nil)
        case .failed:
            return   // a failed check says nothing about whether an update exists; keep what we knew
        }
        defaults.set(now(), forKey: Self.lastCheckKey)
    }

    /// The optional background check: does nothing unless the user turned it on, and then at most
    /// once every 24 hours.
    func checkAutomaticallyIfDue(enabled: Bool) async {
        guard enabled else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           now().timeIntervalSince(last) < Self.automaticInterval {
            return
        }
        await check()
    }

    private func performCheck() async -> UpdateStatus {
        var request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("SpaceStation/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetch(request)
        } catch {
            return .failed("Couldn't reach GitHub. Check your connection and try again.")
        }

        guard let http = response as? HTTPURLResponse else { return .failed("Unexpected response from GitHub.") }
        switch http.statusCode {
        case 200:
            guard let release = Self.parseRelease(data) else { return .failed("Couldn't read GitHub's response.") }
            return UpdateVersion.isNewer(release.version, than: currentVersion)
                ? .available(release) : .upToDate(currentVersion: currentVersion)
        case 404:
            return .noReleases
        case 403, 429:
            return .failed("GitHub is limiting requests right now. Try again later.")
        default:
            return .failed("GitHub returned an error (\(http.statusCode)).")
        }
    }

    // MARK: - Parsing and trust (pure)

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let name: String?
        let html_url: String
        let draft: Bool?
        let prerelease: Bool?
    }

    /// Reads GitHub's "latest release" JSON. Drafts and pre-releases are ignored. The release page
    /// link is only used if it really is a page on this repository; otherwise the repository's
    /// releases page is used, so a malformed or tampered response can't send people elsewhere.
    nonisolated static func parseRelease(_ data: Data) -> ReleaseInfo? {
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              release.draft != true, release.prerelease != true else { return nil }
        let tag = release.tag_name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UpdateVersion.components(tag) != nil else { return nil }
        let version = tag.lowercased().hasPrefix("v") ? String(tag.dropFirst()) : tag
        let url = URL(string: release.html_url).flatMap { isTrustedReleaseURL($0) ? $0 : nil } ?? releasesPage
        return ReleaseInfo(tag: tag, version: version, name: release.name ?? "SpaceStation \(version)", url: url)
    }

    nonisolated static func isTrustedReleaseURL(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host?.lowercased() == "github.com"
            && url.path.lowercased().hasPrefix("/\(repository.lowercased())/")
    }

    // MARK: - Network

    /// An ephemeral session: no cookies, no cache, nothing stored between checks.
    static let liveFetch: Fetch = { request in
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }
}

extension UpdateStatus {
    /// One line for the About tab.
    var summary: String {
        switch self {
        case .upToDate(let version): return "SpaceStation \(version) is up to date."
        case .available(let release): return "Version \(release.version) is available."
        case .noReleases: return "No releases have been published yet."
        case .failed(let message): return message
        }
    }
}

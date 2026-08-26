import Foundation

enum AppUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(version: String, releaseURL: URL)
    case failed(String)
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
    }
}

enum AppUpdateService {
    static let releasesAPI = URL(string: "https://api.github.com/repos/Samoilov2004/LighTeX/releases")!

    static func check(
        currentVersion: String,
        url: URL = releasesAPI,
        session: URLSession = .shared
    ) async -> AppUpdateState {
        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("LighTex/(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            guard let latest = releases.first(where: { !$0.draft }) else {
                return .upToDate
            }
            return compare(latest.tagName, currentVersion) == .orderedDescending
                ? .available(version: latest.tagName, releaseURL: latest.htmlURL)
                : .upToDate
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        let leftBeta = lhs.lowercased().contains("beta")
        let rightBeta = rhs.lowercased().contains("beta")
        if leftBeta != rightBeta { return leftBeta ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    private static func versionComponents(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(whereSeparator: { !$0.isNumber })
            .prefix(3)
            .compactMap { Int($0) }
    }
}

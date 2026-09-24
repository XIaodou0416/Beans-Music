import Foundation

struct SponsorBlockSegment: Identifiable, Codable, Equatable, Sendable {
    var id: String { uuid }

    let uuid: String
    let category: String
    let actionType: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let videoDuration: TimeInterval?
    let votes: Int?

    var isSkippable: Bool {
        actionType.lowercased() == "skip" && endTime > startTime
    }

    var title: String {
        switch category.lowercased() {
        case "sponsor":
            return "赞助"
        case "selfpromo":
            return "推广"
        case "interaction":
            return "互动提醒"
        case "intro":
            return "开场"
        case "outro":
            return "片尾"
        case "preview":
            return "预览"
        case "padding":
            return "填充"
        case "filler":
            return "离题"
        case "music_offtopic":
            return "非音乐"
        default:
            return "空降片段"
        }
    }
}

struct SponsorBlockSkipEvent: Equatable, Sendable {
    let segment: SponsorBlockSegment
    let fromTime: TimeInterval
    let skippedAt: Date
}

final class SponsorBlockService: @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://www.bsbsb.top")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchSkipSegments(bvid: String, cid: Int) async throws -> [SponsorBlockSegment] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("/api/skipSegments"),
            resolvingAgainstBaseURL: false
        ) else {
            throw BiliAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "videoID", value: bvid),
            URLQueryItem(name: "cid", value: String(cid))
        ]
        guard let url = components.url else { throw BiliAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("cc.bili", forHTTPHeaderField: "Origin")
        request.setValue("cc.bili/1.0", forHTTPHeaderField: "X-Ext-Version")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return []
        }
        if httpResponse.statusCode == 404 {
            return []
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw BiliAPIError.api(code: httpResponse.statusCode, message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }

        return try JSONDecoder().decode([SponsorBlockSegmentResponse].self, from: data)
            .compactMap(SponsorBlockSegment.init(response:))
            .filter(\.isSkippable)
            .sorted { $0.startTime < $1.startTime }
    }

    func reportViewed(uuid: String) async {
        guard let components = URLComponents(
            url: baseURL.appendingPathComponent("/api/viewedVideoSponsorTime"),
            resolvingAgainstBaseURL: false
        ) else {
            return
        }
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("cc.bili", forHTTPHeaderField: "Origin")
        request.setValue("cc.bili/1.0", forHTTPHeaderField: "X-Ext-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONEncoder().encode(["UUID": uuid])

        _ = try? await session.data(for: request)
    }
}

private struct SponsorBlockSegmentResponse: Decodable {
    let cid: String?
    let category: String
    let actionType: String?
    let segment: [Double]
    let uuid: String
    let videoDuration: Double?
    let votes: Int?

    enum CodingKeys: String, CodingKey {
        case cid
        case category
        case actionType
        case segment
        case uuid = "UUID"
        case videoDuration
        case votes
    }
}

private extension SponsorBlockSegment {
    init?(response: SponsorBlockSegmentResponse) {
        guard response.segment.count >= 2 else { return nil }
        let startTime = response.segment[0]
        let endTime = response.segment[1]
        guard startTime.isFinite, endTime.isFinite, startTime >= 0, endTime > startTime else { return nil }

        self.init(
            uuid: response.uuid,
            category: response.category,
            actionType: response.actionType ?? "skip",
            startTime: startTime,
            endTime: endTime,
            videoDuration: response.videoDuration,
            votes: response.votes
        )
    }
}

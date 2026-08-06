import Foundation

struct AILCCBatchResponseDTO: Decodable, Sendable {
    let code: Int
    let holiday: [String: AILCCHolidayDTO?]
    let type: [String: AILCCTypeDTO]

    private enum CodingKeys: String, CodingKey {
        case code
        case holiday
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(Int.self, forKey: .code) ?? -1
        holiday = try container.decodeIfPresent(
            [String: AILCCHolidayDTO?].self,
            forKey: .holiday
        ) ?? [:]
        type = try container.decodeIfPresent(
            [String: AILCCTypeDTO].self,
            forKey: .type
        ) ?? [:]
    }
}

struct AILCCHolidayDTO: Decodable, Sendable {
    let holiday: Bool
    let name: String
    let date: String?
}

struct AILCCTypeDTO: Decodable, Sendable {
    let type: Int
    let name: String
    let week: Int
}

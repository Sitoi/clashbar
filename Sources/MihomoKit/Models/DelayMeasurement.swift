import Foundation

public struct DelayMeasurement: Decodable, Equatable, Sendable {
    public let value: Int?

    private enum CodingKeys: String, CodingKey {
        case delay
    }

    public init(value: Int?) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let value = try container.decodeIfPresent(Int.self, forKey: .delay)
        {
            self.value = value
            return
        }

        let container = try decoder.singleValueContainer()
        self.value = try? container.decode([String: Int].self).values.first
    }
}

public struct GroupDelayMeasurement: Decodable, Equatable, Sendable {
    public let values: [String: Int]

    public init(values: [String: Int] = [:]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.values = (try? container.decode([String: Int].self)) ?? [:]
    }
}

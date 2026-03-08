import Foundation

struct ConnectionsSnapshot: Decodable, Equatable {
    static let retainedConnectionLimit = 120

    let totalCount: Int
    let connections: [ConnectionSummary]

    private enum CodingKeys: String, CodingKey {
        case connections
    }

    init(connections: [ConnectionSummary], totalCount: Int? = nil) {
        self.connections = connections
        self.totalCount = totalCount ?? connections.count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard var connectionsContainer = try? container.nestedUnkeyedContainer(forKey: .connections) else {
            self.connections = []
            self.totalCount = 0
            return
        }

        var retained: [ConnectionSummary] = []
        retained.reserveCapacity(min(Self.retainedConnectionLimit, connectionsContainer.count ?? Self.retainedConnectionLimit))

        var totalCount = 0
        while !connectionsContainer.isAtEnd {
            let connection = try connectionsContainer.decode(ConnectionSummary.self)
            if retained.count < Self.retainedConnectionLimit {
                retained.append(connection)
            }
            totalCount += 1
        }

        self.connections = retained
        self.totalCount = totalCount
    }
}

struct ConnectionSummary: Codable, Equatable, Identifiable {
    let id: String
    let upload: Int64?
    let download: Int64?
    let start: String?
    let rule: String?
    let rulePayload: String?
    let chains: [String]?
    let metadata: ConnectionMetadata?

    private enum CodingKeys: String, CodingKey {
        case id
        case upload
        case download
        case start
        case rule
        case rulePayload
        case chains
        case metadata
    }

    init(
        id: String,
        upload: Int64?,
        download: Int64?,
        start: String?,
        rule: String?,
        rulePayload: String?,
        chains: [String]?,
        metadata: ConnectionMetadata?)
    {
        self.id = id
        self.upload = upload
        self.download = download
        self.start = start
        self.rule = rule
        self.rulePayload = rulePayload
        self.chains = chains
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dynamic = try decoder.container(keyedBy: ConnectionAnyCodingKey.self)

        self.id = try container.decode(String.self, forKey: .id)
        self.upload = try container.decodeIfPresent(Int64.self, forKey: .upload)
        self.download = try container.decodeIfPresent(Int64.self, forKey: .download)
        self.start = try container.decodeIfPresent(String.self, forKey: .start)
        self.rule = try container.decodeIfPresent(String.self, forKey: .rule)
        self.metadata = try container.decodeIfPresent(ConnectionMetadata.self, forKey: .metadata)
        self.rulePayload = ConnectionAnyCodingKey.decodeString(
            in: dynamic,
            keys: ["rulePayload", "rule_payload", "rulepayload", "payload"])
        self.chains = ConnectionAnyCodingKey.decodeStringArray(in: dynamic, keys: ["chains", "chain"])
    }
}

struct ConnectionMetadata: Codable, Equatable {
    let network: String?
    let sourceIP: String?
    let destinationIP: String?
    let host: String?

    private enum CodingKeys: String, CodingKey {
        case network
        case sourceIP
        case destinationIP
        case host
    }

    init(network: String?, sourceIP: String?, destinationIP: String?, host: String?) {
        self.network = network
        self.sourceIP = sourceIP
        self.destinationIP = destinationIP
        self.host = host
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dynamic = try decoder.container(keyedBy: ConnectionAnyCodingKey.self)

        self.network = try container.decodeIfPresent(String.self, forKey: .network).trimmedNonEmpty
            ?? ConnectionAnyCodingKey.decodeString(in: dynamic, keys: ["networkType", "type"])
        self.sourceIP = try container.decodeIfPresent(String.self, forKey: .sourceIP).trimmedNonEmpty
            ?? ConnectionAnyCodingKey.decodeString(in: dynamic, keys: ["source_ip", "source", "clientIP"])
        self.destinationIP = try container.decodeIfPresent(String.self, forKey: .destinationIP).trimmedNonEmpty
            ?? ConnectionAnyCodingKey.decodeString(
                in: dynamic,
                keys: ["destination_ip", "destination", "remoteIP", "remoteAddress"])
        self.host = try container.decodeIfPresent(String.self, forKey: .host).trimmedNonEmpty
            ?? ConnectionAnyCodingKey.decodeString(in: dynamic, keys: ["destinationHost", "remoteHost", "addr"])
    }
}

private struct ConnectionAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    static func decodeString(
        in container: KeyedDecodingContainer<ConnectionAnyCodingKey>,
        keys: [String]) -> String?
    {
        for keyName in keys {
            guard let key = ConnectionAnyCodingKey(stringValue: keyName),
                  let value = container.decodeFlexibleString(forKey: key)
            else { continue }
            return value
        }
        return nil
    }

    static func decodeStringArray(
        in container: KeyedDecodingContainer<ConnectionAnyCodingKey>,
        keys: [String]) -> [String]?
    {
        for keyName in keys {
            guard let key = ConnectionAnyCodingKey(stringValue: keyName) else { continue }

            if let rawValues = try? container.decodeIfPresent([String].self, forKey: key) {
                let values = rawValues.compactMap(\.trimmedNonEmpty)
                if !values.isEmpty {
                    return values
                }
            }

            if let rawValue = try? container.decodeIfPresent(String.self, forKey: key),
               let value = rawValue.trimmedNonEmpty
            {
                return [value]
            }
        }
        return nil
    }
}

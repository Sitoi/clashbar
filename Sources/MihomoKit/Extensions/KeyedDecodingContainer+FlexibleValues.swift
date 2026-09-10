import Foundation

extension KeyedDecodingContainer {
    package func decodeFlexibleBool(forKey key: Key) -> Bool? {
        if let value = try? self.decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? self.decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? self.decodeIfPresent(String.self, forKey: key) {
            return Bool(value.trimmed) ?? (value.trimmed == "1" ? true : (value.trimmed == "0" ? false : nil))
        }
        return nil
    }

    package func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? self.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? self.decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmed)
        }
        return nil
    }

    package func decodeFlexibleString(forKey key: Key) -> String? {
        if let value = try? self.decodeIfPresent(String.self, forKey: key) {
            return value.trimmedNonEmpty
        }
        if let value = try? self.decodeIfPresent(Int.self, forKey: key) {
            return "\(value)"
        }
        return nil
    }
}

extension KeyedDecodingContainer where K: CodingKey {
    package func decodeInt64WithFallback(primary: Key, fallback: Key) -> Int64? {
        (try? decodeIfPresent(Int64.self, forKey: primary))
            ?? (try? decodeIfPresent(Int64.self, forKey: fallback))
    }
}

extension KeyedDecodingContainer {
    package func decodeDelayHistory(forKey key: Key, limit: Int = ProxyDelayHistory.limit) -> [Int] {
        guard var historyContainer = try? self.nestedUnkeyedContainer(forKey: key) else {
            return []
        }
        var samples: [Int] = []
        while !historyContainer.isAtEnd {
            guard let entry = try? historyContainer.decode(FlexibleDelayHistoryEntry.self) else {
                break
            }
            if let delay = entry.delay {
                samples.append(delay)
            }
        }
        guard limit > 0, samples.count > limit else {
            return samples
        }
        return Array(samples.suffix(limit))
    }
}

extension Int? {
    package var positiveOrNil: Int? {
        guard let value = self, value > 0 else { return nil }
        return value
    }
}

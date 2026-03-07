import Foundation

extension KeyedDecodingContainer {
    func decodeFlexibleBool(forKey key: Key) -> Bool? {
        if let value = try? self.decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? self.decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? self.decodeIfPresent(Int64.self, forKey: key) {
            return value != 0
        }
        if let value = try? self.decodeIfPresent(String.self, forKey: key) {
            switch value.trimmed.lowercased() {
            case "true", "yes", "on", "1":
                return true
            case "false", "no", "off", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? self.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? self.decodeIfPresent(Int64.self, forKey: key) {
            return Int(value)
        }
        if let value = try? self.decodeIfPresent(String.self, forKey: key),
           let parsed = Int(value.trimmed)
        {
            return parsed
        }
        return nil
    }

    func decodeFlexibleString(forKey key: Key) -> String? {
        if let value = try? self.decodeIfPresent(String.self, forKey: key) {
            return value.trimmedNonEmpty
        }
        if let value = try? self.decodeIfPresent(Int.self, forKey: key) {
            return "\(value)"
        }
        if let value = try? self.decodeIfPresent(Int64.self, forKey: key) {
            return "\(value)"
        }
        if let value = try? self.decodeIfPresent(Double.self, forKey: key) {
            return "\(value)"
        }
        return nil
    }
}

extension KeyedDecodingContainer where K: CodingKey {
    func decodeInt64WithFallback(primary: Key, fallback: Key) -> Int64? {
        (try? decodeIfPresent(Int64.self, forKey: primary))
            ?? (try? decodeIfPresent(Int64.self, forKey: fallback))
    }
}

extension Int? {
    var positiveOrNil: Int? {
        guard let value = self, value > 0 else { return nil }
        return value
    }
}

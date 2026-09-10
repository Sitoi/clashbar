import Darwin
import Foundation

enum DeviceIPv4AddressResolver {
    static func currentAddress() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var bestMatch: (priority: Int, address: String)?

        for pointer in sequence(first: interfaces, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let sockaddr = interface.ifa_addr, sockaddr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            guard isUp, isRunning, !isLoopback else {
                continue
            }

            let interfaceName = String(cString: interface.ifa_name)
            guard !self.isIgnoredInterface(interfaceName) else {
                continue
            }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                sockaddr,
                socklen_t(sockaddr.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST)
            guard result == 0 else {
                continue
            }

            let address = hostBuffer.withUnsafeBufferPointer { ptr in
                ptr.baseAddress.map { String(cString: $0) } ?? ""
            }
            guard !address.isEmpty else {
                continue
            }
            guard !address.hasPrefix("169.254.") else {
                continue
            }

            let candidate = (priority: interfacePriority(interfaceName), address: address)
            if let bestMatch, bestMatch.priority <= candidate.priority {
                continue
            }
            bestMatch = candidate
        }

        return bestMatch?.address
    }

    private static func isIgnoredInterface(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.hasPrefix("lo") || normalized.hasPrefix("awdl") || normalized.hasPrefix("llw")
    }

    private static func interfacePriority(_ name: String) -> Int {
        let normalized = name.lowercased()
        if normalized == "en0" {
            return 0
        }
        if normalized.hasPrefix("en") {
            return 1
        }
        if normalized.hasPrefix("bridge") {
            return 2
        }
        if normalized.hasPrefix("utun") {
            return 3
        }
        return 4
    }
}

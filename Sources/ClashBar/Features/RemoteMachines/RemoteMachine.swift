import Foundation

struct RemoteMachine: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var secret: String?
    var useHTTPS: Bool

    var controllerAddress: String {
        if self.useHTTPS {
            return "https://\(self.host):\(self.port)"
        }
        return "\(self.host):\(self.port)"
    }

    var displayAddress: String {
        "\(self.host):\(self.port)"
    }

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 9090,
        secret: String? = nil,
        useHTTPS: Bool = false)
    {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.secret = secret
        self.useHTTPS = useHTTPS
    }
}

enum MachineTarget: Equatable, Hashable {
    case local
    case remote(RemoteMachine)

    var isLocal: Bool {
        if case .local = self {
            return true
        }
        return false
    }

    var remoteMachine: RemoteMachine? {
        if case let .remote(machine) = self {
            return machine
        }
        return nil
    }
}

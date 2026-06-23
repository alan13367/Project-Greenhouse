import Foundation
import Network

enum AgentHealthProbe {
    static func probe(port: Int, timeout: Duration = .seconds(3)) async throws -> Bool {
        let state = ProbeState(
            connection: NWConnection(
                host: .ipv4(.loopback),
                port: NWEndpoint.Port(rawValue: UInt16(port))!,
                using: .tcp
            )
        )
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await state.run()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ProbeError.timedOut
            }
            guard let result = try await group.next() else {
                throw ProbeError.connectionClosed
            }
            group.cancelAll()
            state.cancel()
            return result
        }
    }

    private final class ProbeState: @unchecked Sendable {
        private let connection: NWConnection
        private let queue = DispatchQueue(label: "dev.greenhouse.agent-health")
        private var parser = GreenhousePacketParser()

        init(connection: NWConnection) {
            self.connection = connection
        }

        func run() async throws -> Bool {
            try await withCheckedThrowingContinuation { continuation in
                let gate = ContinuationGate(continuation)
                connection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.connection.send(
                            content: GreenhousePacket(
                                kind: .health,
                                streamID: 0
                            ).encoded(),
                            completion: .contentProcessed { error in
                                if let error {
                                    gate.resume(throwing: error)
                                } else {
                                    self.receive(gate: gate)
                                }
                            }
                        )
                    case let .failed(error):
                        gate.resume(throwing: error)
                    case .cancelled:
                        gate.resume(throwing: ProbeError.connectionClosed)
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        }

        func cancel() {
            connection.cancel()
        }

        private func receive(gate: ContinuationGate) {
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: 64 * 1024
            ) { [weak self] data, _, complete, error in
                guard let self else { return }
                do {
                    if let data {
                        for packet in try self.parser.append(data)
                        where packet.kind == .healthy {
                            let object = try JSONSerialization.jsonObject(
                                with: packet.payload
                            ) as? [String: Any]
                            gate.resume(returning: object?["healthy"] as? Bool == true)
                            return
                        }
                    }
                    if let error {
                        gate.resume(throwing: error)
                    } else if complete {
                        gate.resume(throwing: ProbeError.connectionClosed)
                    } else {
                        self.receive(gate: gate)
                    }
                } catch {
                    gate.resume(throwing: error)
                }
            }
        }
    }

    private final class ContinuationGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool, Error>?

        init(_ continuation: CheckedContinuation<Bool, Error>) {
            self.continuation = continuation
        }

        func resume(returning value: Bool) {
            take()?.resume(returning: value)
        }

        func resume(throwing error: Error) {
            take()?.resume(throwing: error)
        }

        private func take() -> CheckedContinuation<Bool, Error>? {
            lock.lock()
            defer { lock.unlock() }
            let value = continuation
            continuation = nil
            return value
        }
    }

    private enum ProbeError: Error {
        case timedOut
        case connectionClosed
    }
}

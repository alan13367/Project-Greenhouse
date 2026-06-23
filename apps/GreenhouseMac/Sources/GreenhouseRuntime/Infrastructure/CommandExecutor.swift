import Foundation

public struct CommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public struct CommandFailure: Error, LocalizedError, Sendable {
    public let executable: String
    public let arguments: [String]
    public let result: CommandResult

    public var errorDescription: String? {
        let detail = result.standardError.isEmpty
            ? result.standardOutput
            : result.standardError
        return "\(executable) exited with status \(result.exitCode): \(detail)"
    }
}

public final class CommandExecutor: @unchecked Sendable {
    public init() {}

    public func run(
        executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectory: URL? = nil,
        allowingNonZeroExit: Bool = false
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    let output = Pipe()
                    let error = Pipe()
                    process.executableURL = executable
                    process.arguments = arguments
                    process.environment = ProcessInfo.processInfo.environment.merging(
                        environment,
                        uniquingKeysWith: { _, new in new }
                    )
                    process.currentDirectoryURL = currentDirectory
                    process.standardOutput = output
                    process.standardError = error
                    try process.run()

                    let capture = CommandCapture()
                    let readers = DispatchGroup()
                    readers.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        capture.setStandardOutput(
                            output.fileHandleForReading.readDataToEndOfFile()
                        )
                        readers.leave()
                    }
                    readers.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        capture.setStandardError(
                            error.fileHandleForReading.readDataToEndOfFile()
                        )
                        readers.leave()
                    }
                    process.waitUntilExit()
                    readers.wait()
                    let captured = capture.snapshot()

                    let result = CommandResult(
                        exitCode: process.terminationStatus,
                        standardOutput: String(
                            decoding: captured.standardOutput,
                            as: UTF8.self
                        ).trimmingCharacters(in: .whitespacesAndNewlines),
                        standardError: String(
                            decoding: captured.standardError,
                            as: UTF8.self
                        ).trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    if result.exitCode != 0 && !allowingNonZeroExit {
                        throw CommandFailure(
                            executable: executable.path,
                            arguments: arguments,
                            result: result
                        )
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func launch(
        executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        standardOutput: Any? = nil,
        standardError: Any? = nil
    ) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            environment,
            uniquingKeysWith: { _, new in new }
        )
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        return process
    }
}

private final class CommandCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var standardOutput = Data()
    private var standardError = Data()

    func setStandardOutput(_ data: Data) {
        lock.lock()
        standardOutput = data
        lock.unlock()
    }

    func setStandardError(_ data: Data) {
        lock.lock()
        standardError = data
        lock.unlock()
    }

    func snapshot() -> (standardOutput: Data, standardError: Data) {
        lock.lock()
        defer { lock.unlock() }
        return (standardOutput, standardError)
    }
}

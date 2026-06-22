import Foundation

public enum EventLevel: String, Codable, Sendable {
    case debug
    case info
    case warning
    case error
}

public struct DevelopmentEvent: Codable, Equatable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let id: UUID
    public let sequence: Int
    public let timestamp: Date
    public let source: String
    public let level: EventLevel
    public let name: String
    public let message: String
    public let attributes: [String: String]
    public let statePatch: StatePatch?
    public let issue: GreenhouseIssue?

    public init(
        schemaVersion: Int = 1,
        id: UUID = UUID(),
        sequence: Int,
        timestamp: Date = Date(),
        source: String,
        level: EventLevel,
        name: String,
        message: String,
        attributes: [String: String] = [:],
        statePatch: StatePatch? = nil,
        issue: GreenhouseIssue? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.sequence = sequence
        self.timestamp = timestamp
        self.source = source
        self.level = level
        self.name = name
        self.message = message
        self.attributes = attributes
        self.statePatch = statePatch
        self.issue = issue
    }

    public var ndjson: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else {
            return #"{"schemaVersion":1,"level":"error","name":"event.encoding-failed"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}

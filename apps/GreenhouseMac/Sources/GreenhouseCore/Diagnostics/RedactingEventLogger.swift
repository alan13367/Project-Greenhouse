import Foundation
import OSLog

public struct RedactingEventLogger {
    private let logger: Logger

    public init(
        subsystem: String = "dev.greenhouse.GreenhouseMac",
        category: String = "development-events"
    ) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    @discardableResult
    public func record(_ event: DevelopmentEvent) -> DevelopmentEvent {
        let redacted = event.redacted()
        logger.log(level: redacted.osLogType, "\(redacted.ndjson, privacy: .public)")
        return redacted
    }
}

private extension DevelopmentEvent {
    var osLogType: OSLogType {
        switch level {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        }
    }
}

public extension DevelopmentEvent {
    func redacted(homeDirectory: String = NSHomeDirectory()) -> DevelopmentEvent {
        let sensitiveFragments = [
            "authorization", "cookie", "credential", "password",
            "secret", "token", "account"
        ]

        let cleanedAttributes = attributes.mapValues { value in
            redactValue(value, homeDirectory: homeDirectory)
        }.reduce(into: [String: String]()) { result, pair in
            let key = pair.key
            if sensitiveFragments.contains(where: { key.lowercased().contains($0) }) {
                result[key] = "<redacted>"
            } else {
                result[key] = pair.value
            }
        }

        return DevelopmentEvent(
            schemaVersion: schemaVersion,
            id: id,
            sequence: sequence,
            timestamp: timestamp,
            source: source,
            level: level,
            name: name,
            message: redactValue(message, homeDirectory: homeDirectory),
            attributes: cleanedAttributes,
            statePatch: statePatch?.redacted(homeDirectory: homeDirectory),
            issue: issue.map {
                GreenhouseIssue(
                    id: $0.id,
                    code: $0.code,
                    severity: $0.severity,
                    summary: redactValue($0.summary, homeDirectory: homeDirectory),
                    detail: redactValue($0.detail, homeDirectory: homeDirectory),
                    recoverySuggestion: redactValue($0.recoveryAction, homeDirectory: homeDirectory)
                )
            }
        )
    }
}

private extension StatePatch {
    func redacted(homeDirectory: String) -> StatePatch {
        StatePatch(
            runtimeInstallation: runtimeInstallation,
            vmLifecycle: vmLifecycle,
            androidReadiness: androidReadiness,
            googleServices: googleServices,
            currentOperation: currentOperation?.redacted(homeDirectory: homeDirectory),
            appWindow: appWindow.map {
                AppWindowPatch(
                    appID: AndroidAppID(
                        rawValue: redactValue($0.appID.rawValue, homeDirectory: homeDirectory)
                    ),
                    state: $0.state
                )
            }
        )
    }
}

private extension CurrentOperation {
    func redacted(homeDirectory: String) -> CurrentOperation {
        switch self {
        case .idle:
            .idle
        case let .preparingRuntime(progress):
            .preparingRuntime(progress.redacted(homeDirectory: homeDirectory))
        case .startingAndroid:
            .startingAndroid
        case .signingInToGoogle:
            .signingInToGoogle
        case let .installingFromPlay(progress):
            .installingFromPlay(progress.redacted(homeDirectory: homeDirectory))
        case let .installingApp(progress):
            .installingApp(progress.redacted(homeDirectory: homeDirectory))
        case .openingAppWindow:
            .openingAppWindow
        case let .updatingRuntime(progress):
            .updatingRuntime(progress.redacted(homeDirectory: homeDirectory))
        case let .repairingRuntime(progress):
            .repairingRuntime(progress.redacted(homeDirectory: homeDirectory))
        case .exportingDiagnostics:
            .exportingDiagnostics
        }
    }
}

private extension OperationProgress {
    func redacted(homeDirectory: String) -> OperationProgress {
        OperationProgress(
            fractionCompleted: fractionCompleted,
            detail: redactValue(detail, homeDirectory: homeDirectory)
        )
    }
}

private func redactValue(_ value: String, homeDirectory: String) -> String {
    let homeRedacted = homeDirectory.isEmpty
        ? value
        : value.replacingOccurrences(of: homeDirectory, with: "~")

    return homeRedacted.replacingOccurrences(
        of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        with: "<redacted-email>",
        options: [.regularExpression, .caseInsensitive]
    )
}

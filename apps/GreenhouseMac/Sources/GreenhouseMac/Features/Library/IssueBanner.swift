import GreenhouseCore
import SwiftUI

struct IssueBanner: View {
    let issue: GreenhouseIssue
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: issue.severity == .warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                .foregroundStyle(issue.severity == .warning ? .orange : .red)

            VStack(alignment: .leading, spacing: 4) {
                Text(issue.summary)
                    .font(.headline)
                Text(issue.detail)
                Text(issue.recoveryAction)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Dismiss", action: dismiss)
                .buttonStyle(.borderless)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

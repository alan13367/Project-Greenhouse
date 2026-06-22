import GreenhouseCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryRootView: View {
    let model: GreenhouseAppModel
    let appWindowCoordinator: AppWindowCoordinator

    @Environment(\.openWindow) private var openWindow
    @State private var showingImporter = false

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(model: model)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    RuntimeStatusView(model: model)

                    if let issue = model.latestIssue {
                        IssueBanner(issue: issue) {
                            model.clearIssues()
                        }
                    }

                    operationProgress
                    libraryContent
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
            }
            .navigationTitle("App Library")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Install Package", systemImage: "shippingbox")
                    }
                    .disabled(model.snapshot.androidReadiness != .ready)

                    Button {
                        openWindow(id: "diagnostics")
                    } label: {
                        Label("Diagnostics", systemImage: "waveform.path.ecg")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: Self.packageTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task {
                await model.installPackage(named: url.lastPathComponent)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your Android apps, without the Android setup")
                    .font(.title2.weight(.semibold))
                Text("This foundation build uses a deterministic fake backend. No virtual machine or Google software is included.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    if appWindowCoordinator.focusWindow(for: AndroidApp.googlePlay.id) {
                        return
                    }
                    guard let app = await model.openGooglePlay() else { return }
                    guard await model.openApp(app) else { return }
                    appWindowCoordinator.presentWindow(for: app.id) {
                        openWindow(value: app.id)
                    }
                }
            } label: {
                Label("Google Play", systemImage: "bag.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.snapshot.androidReadiness != .ready)
        }
    }

    @ViewBuilder
    private var operationProgress: some View {
        if let progress = model.snapshot.currentOperation.progress {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.snapshot.currentOperation.title)
                        .font(.headline)
                    Spacer()
                    Text(progress.fractionCompleted, format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress.fractionCompleted)
                Text(progress.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        } else if model.snapshot.currentOperation != .idle {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(model.snapshot.currentOperation.title)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if model.apps.isEmpty {
            ContentUnavailableView {
                Label("No Android apps yet", systemImage: "square.grid.2x2")
            } description: {
                Text("Prepare Android, then install a package or add the two built-in demo apps.")
            } actions: {
                Button("Add Two Demo Apps") {
                    model.addDemoApps()
                }
                .disabled(model.snapshot.androidReadiness != .ready)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Installed Apps")
                    .font(.headline)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(model.apps) { app in
                        AppLibraryTile(app: app, state: model.state(for: app)) {
                            Task {
                                if appWindowCoordinator.focusWindow(for: app.id) {
                                    return
                                }
                                guard await model.openApp(app) else { return }
                                appWindowCoordinator.presentWindow(for: app.id) {
                                    openWindow(value: app.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static let packageTypes: [UTType] = [
        UTType(filenameExtension: "apk") ?? .data,
        UTType(filenameExtension: "apks") ?? .archive,
        UTType(filenameExtension: "xapk") ?? .archive
    ]
}

private struct LibrarySidebar: View {
    let model: GreenhouseAppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List {
            Section("Greenhouse") {
                Label("App Library", systemImage: "square.grid.2x2")
                Button {
                    openWindow(id: "diagnostics")
                } label: {
                    Label("Advanced Diagnostics", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.plain)
            }

            Section("Android Status") {
                SidebarStatusRow(
                    title: "Runtime",
                    value: model.snapshot.runtimeInstallation.title,
                    symbol: "internaldrive"
                )
                SidebarStatusRow(
                    title: "Environment",
                    value: model.snapshot.vmLifecycle.title,
                    symbol: "power"
                )
                SidebarStatusRow(
                    title: "Android",
                    value: model.snapshot.androidReadiness.title,
                    symbol: "apps.iphone"
                )
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 210, ideal: 240)
    }
}

private struct SidebarStatusRow: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

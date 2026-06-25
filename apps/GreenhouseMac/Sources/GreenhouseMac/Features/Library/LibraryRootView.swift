import GreenhouseCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryRootView: View {
    let model: GreenhouseAppModel
    let appWindowCoordinator: AppWindowCoordinator

    @Environment(\.openWindow) private var openWindow
    @State private var showingImporter = false
    @State private var searchText = ""
    @State private var sortOrder = LibrarySortOrder.name
    @State private var packageDropTargeted = false

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(model: model)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LibraryHeader(
                        model: model,
                        appWindowCoordinator: appWindowCoordinator
                    )
                    RuntimeStatusView(model: model)

                    if let issue = model.latestIssue {
                        IssueBanner(issue: issue) {
                            model.clearIssues()
                        }
                    }

                    OperationProgressCard(operation: model.snapshot.currentOperation)
                    LibraryContent(
                        model: model,
                        appWindowCoordinator: appWindowCoordinator,
                        apps: visibleApps
                    )
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
            }
            .navigationTitle("App Library")
            .searchable(text: $searchText, prompt: "Search apps")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Install Package", systemImage: "shippingbox")
                    }
                    .disabled(model.snapshot.androidReadiness != .ready)

                    Menu {
                        Picker("Sort Apps", selection: $sortOrder) {
                            ForEach(LibrarySortOrder.allCases) { order in
                                Text(order.title).tag(order)
                            }
                        }
                    } label: {
                        Label(sortOrder.title, systemImage: "arrow.up.arrow.down")
                    }

                    Button {
                        openWindow(id: "diagnostics")
                    } label: {
                        Label("Diagnostics", systemImage: "waveform.path.ecg")
                    }

                    Button {
                        Task { await model.refreshInstalledApps() }
                    } label: {
                        Label("Refresh Apps", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.snapshot.androidReadiness != .ready)
                }
            }
            .dropDestination(
                for: URL.self,
                action: dropPackages,
                isTargeted: { packageDropTargeted = $0 }
            )
            .overlay {
                if packageDropTargeted {
                    PackageDropOverlay()
                        .padding(24)
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
                await model.installPackage(at: url)
            }
        }
    }

    private var visibleApps: [AndroidApp] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [AndroidApp]
        if trimmed.isEmpty {
            filtered = model.apps
        } else {
            filtered = model.apps.filter { app in
                app.name.localizedCaseInsensitiveContains(trimmed) ||
                    app.packageName.localizedCaseInsensitiveContains(trimmed)
            }
        }
        return filtered.sorted { lhs, rhs in
            sortOrder.sorted(lhs, rhs, model: model)
        }
    }

    private func dropPackages(_ urls: [URL], location: CGPoint) -> Bool {
        guard model.snapshot.androidReadiness == .ready else { return false }
        let packages = urls.filter(Self.isSupportedPackage)
        guard !packages.isEmpty else { return false }
        Task {
            for package in packages {
                await model.installPackage(at: package)
            }
        }
        return true
    }

    private static func isSupportedPackage(_ url: URL) -> Bool {
        url.isFileURL && ["apk", "apks", "xapk"].contains(url.pathExtension.lowercased())
    }

    private static let packageTypes: [UTType] = [
        UTType(filenameExtension: "apk") ?? .data,
        UTType(filenameExtension: "apks") ?? .archive,
        UTType(filenameExtension: "xapk") ?? .archive
    ]
}

private struct LibraryHeader: View {
    let model: GreenhouseAppModel
    let appWindowCoordinator: AppWindowCoordinator

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your Android apps, without the Android setup")
                    .font(.title2.weight(.semibold))
                Text("The Community Runtime uses microG-compatible services and F-Droid. Official Google Play is not included.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            CommunityRuntimeActions(
                model: model,
                appWindowCoordinator: appWindowCoordinator
            )
        }
    }
}

private struct CommunityRuntimeActions: View {
    let model: GreenhouseAppModel
    let appWindowCoordinator: AppWindowCoordinator

    var body: some View {
        ViewThatFits {
            HStack {
                GoogleServicesButton(
                    model: model,
                    appWindowCoordinator: appWindowCoordinator
                )
                CommunityStoreButton(
                    model: model,
                    appWindowCoordinator: appWindowCoordinator
                )
            }
            VStack(alignment: .trailing) {
                GoogleServicesButton(
                    model: model,
                    appWindowCoordinator: appWindowCoordinator
                )
                CommunityStoreButton(
                    model: model,
                    appWindowCoordinator: appWindowCoordinator
                )
            }
        }
    }
}

private struct GoogleServicesButton: View {
    let model: GreenhouseAppModel
    let appWindowCoordinator: AppWindowCoordinator

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            Task {
                if appWindowCoordinator.focusWindow(for: AndroidApp.microGSettings.id) {
                    return
                }
                guard let app = await model.openGoogleServices() else { return }
                guard await model.openApp(app) else { return }
                appWindowCoordinator.presentWindow(for: app.id) {
                    openWindow(value: app.id)
                }
            }
        } label: {
            Label("microG Setup", systemImage: "person.crop.circle.badge.checkmark")
        }
        .disabled(model.snapshot.androidReadiness != .ready)
    }
}

private struct CommunityStoreButton: View {
    let model: GreenhouseAppModel
    let appWindowCoordinator: AppWindowCoordinator

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            Task {
                if appWindowCoordinator.focusWindow(for: AndroidApp.fDroid.id) {
                    return
                }
                guard let app = await model.openCommunityStore() else { return }
                guard await model.openApp(app) else { return }
                appWindowCoordinator.presentWindow(for: app.id) {
                    openWindow(value: app.id)
                }
            }
        } label: {
            Label("F-Droid", systemImage: "shippingbox.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.snapshot.androidReadiness != .ready)
    }
}

private struct OperationProgressCard: View {
    let operation: CurrentOperation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = operation.progress {
                HStack {
                    Text(operation.title)
                        .font(.headline)
                    Spacer()
                    Text(
                        progress.fractionCompleted,
                        format: .percent.precision(.fractionLength(0))
                    )
                    .foregroundStyle(.secondary)
                }
                ProgressView(value: progress.fractionCompleted)
                Text(progress.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if operation != .idle {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(operation.title)
                }
            }
        }
        .padding(operation == .idle ? 0 : 16)
        .background {
            if operation != .idle {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
            }
        }
    }
}

private struct LibraryContent: View {
    let model: GreenhouseAppModel
    let appWindowCoordinator: AppWindowCoordinator
    let apps: [AndroidApp]

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.apps.isEmpty {
                ContentUnavailableView {
                    Label("No Android apps yet", systemImage: "square.grid.2x2")
                } description: {
                    Text("Prepare Android, then open F-Droid, install a package, or add the built-in demo apps.")
                } actions: {
                    Button("Add Two Demo Apps") {
                        model.addDemoApps()
                    }
                    .disabled(model.snapshot.androidReadiness != .ready)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            } else if apps.isEmpty {
                ContentUnavailableView {
                    Label("No matching apps", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different app name or package identifier.")
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                HStack {
                    Text("Installed Apps")
                        .font(.headline)
                    Spacer()
                    Text("\(apps.count) \(apps.count == 1 ? "app" : "apps")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(apps) { app in
                        AppLibraryTile(
                            app: app,
                            state: model.state(for: app),
                            canOpen: model.snapshot.androidReadiness == .ready
                        ) {
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
}

private enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case name
    case source
    case state

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Name"
        case .source: "Source"
        case .state: "State"
        }
    }

    @MainActor
    func sorted(_ lhs: AndroidApp, _ rhs: AndroidApp, model: GreenhouseAppModel) -> Bool {
        switch self {
        case .name:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .source:
            if lhs.source.title != rhs.source.title {
                return lhs.source.title < rhs.source.title
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .state:
            let leftState = model.state(for: lhs).title
            let rightState = model.state(for: rhs).title
            if leftState != rightState {
                return leftState < rightState
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private struct PackageDropOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.regularMaterial)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "shippingbox.and.arrow.backward")
                        .font(.system(size: 34))
                    Text("Drop package to install")
                        .font(.headline)
                    Text("APK, APKS, and XAPK files are supported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
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
                SidebarStatusRow(
                    title: "Google compatibility",
                    value: model.snapshot.googleServicesProvider.title,
                    symbol: "person.crop.circle.badge.checkmark"
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

import XCTest
@testable import GreenhouseCore

@MainActor
final class FakeBackendIntegrationTests: XCTestCase {
    func testHappyPathReachesReadyAndTracksTwoIndependentWindows() async {
        let model = GreenhouseAppModel(
            backend: FakeBackend(configuration: .tests)
        )

        await model.prepareRuntime()
        await waitUntil { model.snapshot.runtimeInstallation == .ready }

        await model.startAndroid()
        await waitUntil { model.snapshot.androidReadiness == .ready }

        model.addDemoApps()
        XCTAssertEqual(model.apps.count, 2)

        let notesOpened = await model.openApp(.demoNotes)
        let gameOpened = await model.openApp(.demoGame)
        XCTAssertTrue(notesOpened)
        XCTAssertTrue(gameOpened)

        await waitUntil {
            model.snapshot.appWindows[AndroidApp.demoNotes.id] == .visible &&
            model.snapshot.appWindows[AndroidApp.demoGame.id] == .visible
        }

        await model.closeApp(.demoNotes)
        await waitUntil {
            model.snapshot.appWindows[AndroidApp.demoNotes.id] == .closed
        }

        XCTAssertEqual(model.snapshot.appWindows[AndroidApp.demoGame.id], .visible)
        XCTAssertEqual(model.snapshot.vmLifecycle, .running)
        XCTAssertEqual(model.snapshot.androidReadiness, .ready)
    }

    func testAllRequiredFailureScenariosProduceTypedIssues() async {
        let model = GreenhouseAppModel(
            backend: FakeBackend(configuration: .tests)
        )

        for failure in SimulatedFailure.allCases {
            let previousCount = model.issues.count
            await model.simulate(failure)
            await waitUntil { model.issues.count == previousCount + 1 }
        }

        XCTAssertEqual(
            Set(model.issues.map(\.code)),
            Set(IssueCode.allCases)
        )
    }

    func testStateMachinesRemainIndependent() async {
        let backend = FakeBackend(configuration: .tests)
        let model = GreenhouseAppModel(backend: backend)

        await model.simulate(.graphicsUnavailable)
        await waitUntil { model.snapshot.androidReadiness == .degraded }

        XCTAssertEqual(model.snapshot.runtimeInstallation, .missing)
        XCTAssertEqual(model.snapshot.vmLifecycle, .stopped)
        XCTAssertEqual(model.snapshot.androidReadiness, .degraded)
        XCTAssertEqual(model.snapshot.currentOperation, .idle)
    }

    func testStoppingAndroidClosesVisibleAppWindows() async {
        let model = GreenhouseAppModel(
            backend: FakeBackend(configuration: .tests)
        )

        await prepareAndStartAndroid(model)
        _ = await model.openApp(.demoNotes)
        _ = await model.openApp(.demoGame)
        await waitUntil {
            model.state(for: .demoNotes) == .visible &&
            model.state(for: .demoGame) == .visible
        }

        await model.stopAndroid()
        await waitUntil {
            model.snapshot.vmLifecycle == .stopped &&
            model.state(for: .demoNotes) == .closed &&
            model.state(for: .demoGame) == .closed
        }
    }

    func testBackendCrashClosesVisibleAppWindows() async {
        let model = GreenhouseAppModel(
            backend: FakeBackend(configuration: .tests)
        )

        await prepareAndStartAndroid(model)
        _ = await model.openApp(.demoNotes)
        await waitUntil { model.state(for: .demoNotes) == .visible }

        await model.simulate(.backendCrash)
        await waitUntil {
            model.snapshot.vmLifecycle == .crashed &&
            model.state(for: .demoNotes) == .closed
        }
    }

    func testResetInvalidatesInFlightPreparation() async {
        let model = GreenhouseAppModel(
            backend: FakeBackend(
                configuration: FakeBackend.Configuration(
                    stepDelay: .milliseconds(25)
                )
            )
        )

        let preparation = Task {
            await model.prepareRuntime()
        }
        await waitUntil {
            model.snapshot.runtimeInstallation == .downloading
        }

        model.resetFakeBackend()
        await preparation.value
        await waitUntil {
            model.snapshot.runtimeInstallation == .missing &&
            model.snapshot.currentOperation == .idle
        }

        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.snapshot.runtimeInstallation, .missing)
        XCTAssertEqual(model.snapshot.currentOperation, .idle)
    }

    private func prepareAndStartAndroid(_ model: GreenhouseAppModel) async {
        await model.prepareRuntime()
        await waitUntil { model.snapshot.runtimeInstallation == .ready }
        await model.startAndroid()
        await waitUntil { model.snapshot.androidReadiness == .ready }
    }

    private func waitUntil(
        attempts: Int = 100,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<attempts {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition was not met before timeout")
    }
}

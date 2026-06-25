import CoreMedia
import CoreVideo
import Foundation
import Observation

@MainActor
@Observable
public final class AppStreamModel {
    public private(set) var displayID: Int?
    public private(set) var videoWidth = 0
    public private(set) var videoHeight = 0
    public private(set) var pixelBuffer: CVPixelBuffer?
    public private(set) var frameSequence = 0
    public private(set) var presentationTime: CMTime = .invalid
    public private(set) var errorMessage: String?
    public private(set) var measuredFramesPerSecond: Double = 0
    public private(set) var frameJitterMilliseconds: Double = 0
    public private(set) var controlRoundTripMilliseconds: Double?
    public private(set) var decodeLatencyMilliseconds: Double?
    public private(set) var presentationLatencyMilliseconds: Double?
    public private(set) var audioLatencyMilliseconds: Double?
    public private(set) var audioScope: String?
    public private(set) var audioPackageName: String?
    public private(set) var isMuted = false
    public private(set) var controllerConnected = false
    public private(set) var controllerFocused = false
    public private(set) var controllerName: String?

    private var recentPresentationTimes: [CMTime] = []
    private var recentDecodeLatencies: [Double] = []
    private var recentPresentationLatencies: [Double] = []
    private var recentAudioLatencies: [Double] = []
    private var lastPresentedSequence = 0

    public init() {}

    func setDisplayID(_ displayID: Int) {
        self.displayID = displayID
    }

    func setVideoSize(width: Int, height: Int) {
        videoWidth = width
        videoHeight = height
    }

    func present(
        _ pixelBuffer: CVPixelBuffer,
        at presentationTime: CMTime,
        decodeLatencyMilliseconds: Double?
    ) {
        self.pixelBuffer = pixelBuffer
        self.presentationTime = presentationTime
        frameSequence += 1
        if let decodeLatencyMilliseconds {
            recentDecodeLatencies.append(decodeLatencyMilliseconds)
            trim(&recentDecodeLatencies)
            self.decodeLatencyMilliseconds = percentile95(recentDecodeLatencies)
        }
        recentPresentationTimes.append(presentationTime)
        if recentPresentationTimes.count > 120 {
            recentPresentationTimes.removeFirst(recentPresentationTimes.count - 120)
        }
        updateFramePacing()
    }

    func updateControlRoundTrip(_ milliseconds: Double?) {
        controlRoundTripMilliseconds = milliseconds
    }

    func setAudioScope(_ scope: String?, packageName: String?) {
        audioScope = scope
        audioPackageName = packageName
    }

    func setMuted(_ isMuted: Bool) {
        self.isMuted = isMuted
    }

    func setControllerStatus(
        connected: Bool,
        focused: Bool,
        name: String?
    ) {
        controllerConnected = connected
        controllerFocused = focused
        controllerName = name
    }

    func recordAudioLatency(_ milliseconds: Double?) {
        guard let milliseconds else { return }
        recentAudioLatencies.append(milliseconds)
        trim(&recentAudioLatencies)
        audioLatencyMilliseconds = percentile95(recentAudioLatencies)
    }

    func markPresented(sequence: Int, latencyMilliseconds: Double?) {
        guard sequence > lastPresentedSequence else { return }
        lastPresentedSequence = sequence
        guard let latencyMilliseconds else { return }
        recentPresentationLatencies.append(latencyMilliseconds)
        trim(&recentPresentationLatencies)
        presentationLatencyMilliseconds = percentile95(recentPresentationLatencies)
    }

    func fail(_ message: String) {
        errorMessage = message
    }

    private func updateFramePacing() {
        guard recentPresentationTimes.count >= 3 else { return }
        let seconds = recentPresentationTimes.map(\.seconds)
        let intervals = zip(seconds.dropFirst(), seconds).map { newer, older in
            newer - older
        }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        guard mean > 0 else { return }
        measuredFramesPerSecond = 1 / mean
        let variance = intervals.reduce(0) { total, interval in
            let delta = interval - mean
            return total + delta * delta
        } / Double(intervals.count)
        frameJitterMilliseconds = sqrt(variance) * 1_000
    }

    private func trim(_ values: inout [Double]) {
        if values.count > 120 {
            values.removeFirst(values.count - 120)
        }
    }

    private func percentile95(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = min(Int(Double(sorted.count - 1) * 0.95), sorted.count - 1)
        return sorted[index]
    }
}

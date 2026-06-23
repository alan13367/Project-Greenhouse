import CoreMedia
import Foundation

final class StreamClockSynchronizer: @unchecked Sendable {
    private let lock = NSLock()
    private var guestMinusHostNanos: Double?
    private var latestRoundTripNanos: Double?

    func acceptPong(
        hostSendNanos: UInt64,
        guestReceiveNanos: UInt64,
        guestSendNanos: UInt64,
        hostReceiveNanos: UInt64
    ) {
        guard hostReceiveNanos >= hostSendNanos,
              guestSendNanos >= guestReceiveNanos else {
            return
        }
        let offset = (
            Double(guestReceiveNanos) - Double(hostSendNanos)
                + Double(guestSendNanos) - Double(hostReceiveNanos)
        ) / 2
        let roundTrip = Double(hostReceiveNanos - hostSendNanos)
            - Double(guestSendNanos - guestReceiveNanos)

        lock.lock()
        if let current = guestMinusHostNanos {
            guestMinusHostNanos = current * 0.8 + offset * 0.2
        } else {
            guestMinusHostNanos = offset
        }
        latestRoundTripNanos = max(roundTrip, 0)
        lock.unlock()
    }

    func hostLatencyMilliseconds(
        forGuestPresentationTime presentationTime: CMTime,
        hostNowNanos: UInt64
    ) -> Double? {
        guard presentationTime.isNumeric else { return nil }
        lock.lock()
        let offset = guestMinusHostNanos
        lock.unlock()
        guard let offset else { return nil }

        let guestNanos = presentationTime.seconds * 1_000_000_000
        let estimatedHostProductionNanos = guestNanos - offset
        let latency = Double(hostNowNanos) - estimatedHostProductionNanos
        guard latency >= 0, latency < 10_000_000_000 else { return nil }
        return latency / 1_000_000
    }

    var roundTripMilliseconds: Double? {
        lock.lock()
        defer { lock.unlock() }
        return latestRoundTripNanos.map { $0 / 1_000_000 }
    }
}

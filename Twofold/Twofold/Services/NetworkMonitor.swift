//
//  NetworkMonitor.swift
//  Twofold
//
//  App-wide connectivity signal — one shared NWPathMonitor everything can read from. Introduced
//  for GameSessionStore's offline answer queueing, but deliberately generic so any other feature
//  can just read `NetworkMonitor.shared.isConnected` without spinning up its own monitor.
//

import Foundation
import Network
import Observation

@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected = true
    /// True on cellular/personal-hotspot — anything the system considers metered. Bulk background
    /// work (see `AppModel.prefetchMemoryPhotos`) waits for a cheap path rather than quietly
    /// spending someone's data allowance on photos they haven't asked to see yet.
    private(set) var isExpensive = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.orangefinch.Twofold.NetworkMonitor")

    private init() {
        #if DEBUG
        // A way to exercise the offline paths without taking the *machine* offline.
        //
        // The offline behaviour is a large part of this app now — cached Home, the on-device game
        // catalogue, locally started sessions — and the only way to test it was to switch off the
        // Mac's Wi-Fi, which disconnects the simulator and everything else along with it. That
        // makes offline regressions effectively untested, which is how a stack of 60-second
        // timeouts shipped in the offline game paths without anyone noticing.
        //
        // Launch with `TWOFOLD_FORCE_OFFLINE=1` (or `TEST_RUNNER_TWOFOLD_FORCE_OFFLINE=1` for a
        // UI test, which runs on the simulator and inherits nothing else). DEBUG only, so there is
        // no path to it in a shipped build.
        if ProcessInfo.processInfo.environment["TWOFOLD_FORCE_OFFLINE"] == "1" {
            isConnected = false
            isExpensive = false
            return
        }
        #endif
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let expensive = path.isExpensive
            DispatchQueue.main.async {
                self?.isConnected = connected
                self?.isExpensive = expensive
            }
        }
        monitor.start(queue: queue)
    }
}

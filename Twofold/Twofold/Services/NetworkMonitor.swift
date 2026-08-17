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

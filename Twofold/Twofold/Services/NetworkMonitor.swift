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

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.orangefinch.Twofold.NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }
}

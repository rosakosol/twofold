//
//  DemoMode.swift
//  Twofold
//
//  `-demoMode`: the app filled with a sample couple, Sam in Melbourne and Alex in Rome, and no
//  backend at all. It exists for marketing screenshots, so the website shows the app as it really
//  looks, with the same data every time, and without anyone's real account in the picture.
//
//  DEBUG only. In a release build `isOn` is a constant false, so every `DemoMode.isOn` check the
//  network code makes compiles down to nothing.
//
//  Launch arguments, all optional beyond the first:
//    -demoMode                     the sample couple, signed in, Premium, nothing fetched
//    -demoTab home|travel|memories|games|stats
//    -demoTravelSegment flights    the Travel sheet on Flights rather than Trips
//    -demoScreen flight|memory|trip|connected|ourStory|pads
//    -demoPartner none             no partner connected: Home shows "Set up your partner"
//    -demoLatency 3                weather and memory photos take that many seconds to arrive, so
//                                  the screens' loading states can be seen and recorded
//

import Foundation

enum DemoMode {
    #if DEBUG
    static let isOn = ProcessInfo.processInfo.arguments.contains("-demoMode")

    /// The value after `-name` on the command line, if there is one.
    static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-\(name)"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// `-demoLatency`, as a delay to wait before answering. Nil when it isn't set.
    static var latency: Duration? {
        guard isOn, let seconds = argument("demoLatency").flatMap(Double.init), seconds > 0 else { return nil }
        return .milliseconds(Int(seconds * 1000))
    }
    #else
    static let isOn = false
    static func argument(_ name: String) -> String? { nil }
    static var latency: Duration? { nil }
    #endif
}

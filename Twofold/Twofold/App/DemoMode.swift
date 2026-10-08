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
    #else
    static let isOn = false
    static func argument(_ name: String) -> String? { nil }
    #endif
}

//
//  AppleWeatherMark.swift
//  Twofold
//
//  Lives in Shared/ because both targets display WeatherKit data and both therefore have to carry
//  the trademark: the app on the Home time card, and the Time & Weather widget. Same reasoning as
//  TimeMath.swift — the widget extension can't reach the app's DesignSystem, so anything both need
//  comes from here.
//

import Foundation

/// The Apple Weather trademark: the Apple logo (U+F8FF, a private-use codepoint that renders as
/// the logo on Apple platforms) followed by "Weather". Not the words "Apple Weather" — the logo is
/// the mark.
///
/// Apple requires this wherever WeatherKit data is shown, alongside a link to its legal attribution
/// page. The app pairs it with that link in `WeatherAttributionView`; the widget carries the mark
/// alone, since a widget can't host one.
let appleWeatherMark = "\u{F8FF} Weather"

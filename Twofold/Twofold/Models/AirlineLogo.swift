//
//  AirlineLogo.swift
//  Twofold
//
//  AeroAPI doesn't provide airline logos at all (confirmed on FlightAware's own support forum —
//  "logos are not available through FlightXML... our app includes the logos within the app
//  itself"). Rather than bundle a logo image per airline, this derives a URL from a public,
//  no-auth-required logo CDN keyed by IATA code (used by a number of travel apps), the same way
//  `AvatarView` loads a user's photo — a graceful icon fallback covers anything the CDN doesn't
//  have (see AirlineLogoView).
//

import Foundation

enum AirlineLogo {
    static func url(forIATACode code: String?) -> URL? {
        guard let code, code.count == 2 || code.count == 3 else { return nil }
        return URL(string: "https://images.kiwi.com/airlines/64/\(code.uppercased()).png")
    }
}

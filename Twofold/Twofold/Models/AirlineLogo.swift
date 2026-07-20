//
//  AirlineLogo.swift
//  Twofold
//
//  AeroAPI doesn't provide airline logos at all (confirmed on FlightAware's own support forum —
//  "logos are not available through FlightXML... our app includes the logos within the app
//  itself"). Rather than bundle a logo image per airline, this derives a URL from the
//  `airline-logo` edge function, keyed by IATA code — that function mirrors a public logo CDN
//  into our own Supabase Storage on first request for a given code and redirects there, so every
//  later load for that airline is served from our own CDN-backed Storage instead of re-fetching
//  from the third-party CDN every time. A graceful icon fallback covers anything neither source
//  has (see AirlineLogoView).
//

import Foundation

enum AirlineLogo {
    static func url(forIATACode code: String?) -> URL? {
        guard let code, code.count == 2 || code.count == 3 else { return nil }
        return URL(string: "\(SupabaseConfig.projectURL.absoluteString)/functions/v1/airline-logo?code=\(code.uppercased())")
    }
}

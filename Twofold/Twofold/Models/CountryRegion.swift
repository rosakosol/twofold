//
//  CountryRegion.swift
//  Twofold
//
//  Buckets a country name (as it comes back from the `airports` reference table — full English
//  names like "United States", "South Korea") into one of nine broad travel regions, for the
//  Passport "Countries & Territories" region grid. Best-effort: a reasonable geographic grouping,
//  not an authoritative geoscheme — a handful of transcontinental/disputed cases (Russia, Turkey,
//  Egypt) are bucketed by conventional travel-region intuition rather than strict continent lines.
//  A country not in the table below simply doesn't add to any region's count.
//

import Foundation

enum CountryRegion: String, CaseIterable, Identifiable {
    case europe = "Europe"
    case northAmerica = "North America"
    case middleEast = "Middle East"
    case asia = "Asia"
    case africa = "Africa"
    case centralAmerica = "Central America"
    case caribbean = "Caribbean"
    case oceania = "Oceania"
    case southAmerica = "South America"

    var id: String { rawValue }

    private static let countriesByRegion: [CountryRegion: Set<String>] = [
        .europe: [
            "United Kingdom", "Ireland", "France", "Germany", "Spain", "Portugal", "Italy",
            "Netherlands", "Belgium", "Luxembourg", "Switzerland", "Austria", "Denmark", "Norway",
            "Sweden", "Finland", "Iceland", "Poland", "Czech Republic", "Czechia", "Slovakia",
            "Hungary", "Romania", "Bulgaria", "Greece", "Croatia", "Slovenia", "Serbia", "Bosnia and Herzegovina",
            "Montenegro", "North Macedonia", "Albania", "Kosovo", "Moldova", "Ukraine", "Belarus",
            "Estonia", "Latvia", "Lithuania", "Malta", "Cyprus", "Monaco", "Andorra", "San Marino",
            "Liechtenstein", "Vatican City", "Russia", "Russian Federation",
        ],
        .northAmerica: [
            "United States", "United States of America", "Canada", "Mexico", "Greenland", "Bermuda",
        ],
        .middleEast: [
            "United Arab Emirates", "Saudi Arabia", "Qatar", "Kuwait", "Bahrain", "Oman", "Yemen",
            "Israel", "Jordan", "Lebanon", "Syria", "Iraq", "Iran", "Turkey",
        ],
        .asia: [
            "China", "Japan", "South Korea", "North Korea", "Republic of Korea", "Korea, Republic of",
            "Taiwan", "Hong Kong", "Macau", "Mongolia", "India", "Pakistan", "Bangladesh", "Sri Lanka",
            "Nepal", "Bhutan", "Maldives", "Afghanistan", "Kazakhstan", "Uzbekistan", "Turkmenistan",
            "Tajikistan", "Kyrgyzstan", "Azerbaijan", "Armenia", "Georgia", "Singapore", "Malaysia",
            "Indonesia", "Thailand", "Vietnam", "Philippines", "Myanmar", "Cambodia", "Laos", "Brunei",
            "Timor-Leste",
        ],
        .africa: [
            "Egypt", "Libya", "Tunisia", "Algeria", "Morocco", "Sudan", "South Sudan", "Ethiopia",
            "Eritrea", "Djibouti", "Somalia", "Kenya", "Uganda", "Tanzania", "Rwanda", "Burundi",
            "Democratic Republic of the Congo", "Congo", "Republic of the Congo", "Gabon",
            "Equatorial Guinea", "Cameroon", "Central African Republic", "Chad", "Niger", "Nigeria",
            "Benin", "Togo", "Ghana", "Ivory Coast", "Cote d'Ivoire", "Liberia", "Sierra Leone",
            "Guinea", "Guinea-Bissau", "Senegal", "Gambia", "Mauritania", "Mali", "Burkina Faso",
            "Cabo Verde", "Cape Verde", "Sao Tome and Principe", "Angola", "Zambia", "Malawi",
            "Mozambique", "Zimbabwe", "Botswana", "Namibia", "South Africa", "Lesotho", "Eswatini",
            "Swaziland", "Madagascar", "Mauritius", "Seychelles", "Comoros",
        ],
        .centralAmerica: [
            "Guatemala", "Belize", "Honduras", "El Salvador", "Nicaragua", "Costa Rica", "Panama",
        ],
        .caribbean: [
            "Cuba", "Jamaica", "Haiti", "Dominican Republic", "Bahamas", "Puerto Rico",
            "Trinidad and Tobago", "Barbados", "Saint Lucia", "Grenada", "Saint Vincent and the Grenadines",
            "Antigua and Barbuda", "Saint Kitts and Nevis", "Dominica", "Aruba", "Curacao",
            "Cayman Islands", "Turks and Caicos Islands", "British Virgin Islands", "US Virgin Islands",
            "Anguilla", "Montserrat", "Guadeloupe", "Martinique",
        ],
        .oceania: [
            "Australia", "New Zealand", "Fiji", "Papua New Guinea", "Solomon Islands", "Vanuatu",
            "New Caledonia", "Samoa", "American Samoa", "Tonga", "Kiribati", "Tuvalu", "Nauru",
            "Palau", "Micronesia", "Marshall Islands", "French Polynesia", "Guam", "Cook Islands",
            "Niue",
        ],
        .southAmerica: [
            "Brazil", "Argentina", "Chile", "Peru", "Colombia", "Venezuela", "Ecuador", "Bolivia",
            "Paraguay", "Uruguay", "Guyana", "Suriname", "French Guiana",
        ],
    ]

    private static let regionByCountry: [String: CountryRegion] = {
        var map: [String: CountryRegion] = [:]
        for (region, countries) in countriesByRegion {
            for country in countries { map[country] = region }
        }
        return map
    }()

    static func region(for country: String) -> CountryRegion? {
        regionByCountry[country]
    }
}

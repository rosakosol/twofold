//
//  Scenario.swift
//  TwofoldUITests
//
//  The state a test starts from, built fresh for that test on the local stack.
//
//  Every scenario makes brand-new accounts with addresses no other test uses, so tests share
//  nothing and nothing needs resetting between them: there is no "the test couple" whose state one
//  run can leave wrong for the next. The cost is accounts piling up in the local database, which a
//  `supabase db reset --local` clears whenever that matters.
//
//  The state is built the way the app builds it wherever the app has a way:
//
//    - Pairing goes through `create_invite_code` → `redeem_invite_code` → the inviter's
//      `respond_to_connection_request`, each called as the person who calls it in the app. A couple
//      inserted directly would skip the parts of pairing that move solo game sessions across and
//      mark the invite redeemed, and a test of a paired couple should be a test of a couple pairing
//      actually produces.
//    - Finishing onboarding is the same `profiles.onboarding_completed_at` update
//      `BackendService.markOnboardingCompleted` makes, as the account itself.
//    - Trips and memories are the app's own table inserts, as a partner (there is no RPC), after
//      the tier is set — adding needs a subscription, by RLS. For a couple with none, they are
//      inserted with the service role instead, which is the only way such a couple comes to have
//      any: they made them while they were paying.
//
//  The one thing the app can never write is subscription state. In production only the RevenueCat
//  webhook does (`reject_client_subscription_writes` refuses the client), so `apply(tier:)` writes
//  the same columns the webhook's `applyState` writes, with the same service role, plus the
//  `subscription_events` rows it logs. The app is told the matching store answer through
//  `TWOFOLD_E2E_TIER`, so client and server agree as they do for a subscriber whose webhook has
//  landed.
//

import Foundation

/// One account the test runner made and can act as.
struct TestAccount {
    let id: UUID
    let email: String
    let password: String
    let firstName: String
    let accessToken: String

    var caller: LocalStack.Caller { .user(accessToken: accessToken) }
}

/// What the couple's subscription is, server-side and on the device.
enum TestTier: String {
    /// Never subscribed. Eligible for the Plus trial.
    case none
    case plus
    case premium
    /// Subscribed once and let it expire: no active plan, and no trial on offer any more.
    case lapsed
}

struct Scenario {
    /// The account the app signs in as.
    let me: TestAccount
    /// Their partner, for a paired scenario.
    let partner: TestAccount?
    let coupleID: UUID?
    let tier: TestTier

    // MARK: - The scenarios

    /// One person, onboarding finished, nobody to pair with yet.
    static func solo(tier: TestTier = .none, name: String = "Sam") async throws -> Scenario {
        let me = try await makeAccount(firstName: name)
        try await completeOnboarding(me)
        try await apply(tier: tier, to: me)
        return Scenario(me: me, partner: nil, coupleID: nil, tier: tier)
    }

    /// A couple formed through the invite flow. `payer` is whose subscription it is: one partner's
    /// covers both, which is the case that has gone wrong before (see `fetchSubscriptionSnapshot`),
    /// so it is worth being able to say which.
    static func paired(
        tier: TestTier,
        payer: Payer = .me,
        myName: String = "Sam",
        partnerName: String = "Alex"
    ) async throws -> Scenario {
        let me = try await makeAccount(firstName: myName)
        let partner = try await makeAccount(firstName: partnerName)
        try await completeOnboarding(me)
        try await completeOnboarding(partner)
        let coupleID = try await pair(inviter: me, redeemer: partner)
        try await apply(tier: tier, to: payer == .me ? me : partner)
        return Scenario(me: me, partner: partner, coupleID: coupleID, tier: tier)
    }

    enum Payer { case me, partner }

    static func pairedPlus() async throws -> Scenario { try await paired(tier: .plus) }
    static func pairedPremium() async throws -> Scenario { try await paired(tier: .premium) }
    /// A couple whose subscription ran out. Their history is theirs to read; adding to it is not.
    static func lapsed() async throws -> Scenario { try await paired(tier: .lapsed) }

    /// An account that exists and has not finished onboarding — what somebody is after creating
    /// one on "Save your progress" and closing the app. Signing in lands on onboarding's first
    /// question rather than the app.
    static func midOnboarding(name: String = "Sam") async throws -> Scenario {
        let me = try await makeAccount(firstName: name)
        return Scenario(me: me, partner: nil, coupleID: nil, tier: .none)
    }

    // MARK: - Optional content

    /// A trip between two cities, in the couple's history. `daysFromNow` negative for a past one.
    @discardableResult
    func addTrip(
        from origin: TestPlace = .melbourne,
        to destination: TestPlace = .rome,
        daysFromNow: Int = 30,
        category: String = "seeing_each_other"
    ) async throws -> UUID {
        let coupleID = try requireCouple()
        let originID = try await placeID(origin)
        let destinationID = try await placeID(destination)
        let id = UUID()
        let departure = Date().addingTimeInterval(TimeInterval(daysFromNow) * 86_400)
        try await LocalStack.send("POST", "rest/v1/trips", body: [
            "id": id.uuidString,
            "couple_id": coupleID.uuidString,
            "traveler_ids": [me.id.uuidString],
            "origin_id": originID.uuidString,
            "destination_id": destinationID.uuidString,
            "departure_at": Self.iso(departure),
            "arrival_at": Self.iso(departure.addingTimeInterval(86_400)),
            "category": category,
            "distance_km": 15_000,
        ], as: contentWriter)
        return id
    }

    @discardableResult
    func addMemory(title: String, at place: TestPlace = .rome, daysAgo: Int = 10) async throws -> UUID {
        let coupleID = try requireCouple()
        let id = UUID()
        try await LocalStack.send("POST", "rest/v1/memories", body: [
            "id": id.uuidString,
            "couple_id": coupleID.uuidString,
            "place_id": try await placeID(place).uuidString,
            "title": title,
            "note": "",
            "occurred_at": Self.iso(Date().addingTimeInterval(-TimeInterval(daysAgo) * 86_400)),
        ], as: contentWriter)
        return id
    }

    /// A flight, written the way `add-flight` writes one: with the service role, since no client
    /// may insert into `flights`. Times are offsets from now in seconds, so a test can put a flight
    /// in the past, in the air or ahead. San Francisco to Melbourne, both zones known.
    @discardableResult
    func addFlight(
        number: String = "UA60",
        departsIn: TimeInterval,
        arrivesIn: TimeInterval,
        status: String = "scheduled",
        tracking: Bool = true,
        tripID: UUID? = nil,
        departureDelaySeconds: Int? = nil,
        refreshedNow: Bool = true
    ) async throws -> UUID {
        let coupleID = try requireCouple()
        let id = UUID()
        let now = Date()
        let scheduledOut = now.addingTimeInterval(departsIn)
        var body: [String: Any] = [
            "id": id.uuidString,
            "couple_id": coupleID.uuidString,
            "created_by": me.id.uuidString,
            "traveler_ids": [me.id.uuidString],
            "fa_flight_id": "\(number)-e2e-\(id.uuidString.prefix(6))",
            "flight_number_iata": number,
            "airline_code": String(number.prefix(2)),
            "airline_name": "United",
            "origin_iata": "SFO", "origin_city": "San Francisco", "origin_timezone": "America/Los_Angeles",
            "destination_iata": "MEL", "destination_city": "Melbourne", "destination_timezone": "Australia/Melbourne",
            "scheduled_out": Self.iso(scheduledOut),
            "scheduled_in": Self.iso(now.addingTimeInterval(arrivesIn)),
            "status": status,
            "tracking_enabled": tracking,
        ]
        // The provider sets both for a cancellation; the app reads either.
        if status == "cancelled" { body["cancelled"] = true }
        if let tripID { body["trip_id"] = tripID.uuidString }
        if let departureDelaySeconds {
            body["departure_delay_seconds"] = departureDelaySeconds
            body["estimated_out"] = Self.iso(scheduledOut.addingTimeInterval(TimeInterval(departureDelaySeconds)))
        }
        if refreshedNow { body["last_refreshed_at"] = Self.iso(now) }
        try await LocalStack.send("POST", "rest/v1/flights", body: body, as: .service)
        return id
    }

    /// A Sudoku already under way, through the RPC the difficulty picker calls.
    @discardableResult
    func startSudoku(difficulty: String = "easy") async throws -> UUID {
        let rows = try await LocalStack.rpc("start_sudoku_session", ["p_difficulty": difficulty], as: me.caller) as? [[String: Any]]
        guard let raw = rows?.first?["session_id"] as? String, let id = UUID(uuidString: raw) else {
            throw LocalStack.Failure(description: "start_sudoku_session returned \(String(describing: rows))")
        }
        return id
    }

    /// A deck game started through `start_deck_session`, the RPC the deck screen calls, on a deck
    /// the couple's tier can open and that has prompts on this stack.
    ///
    /// Chosen here rather than by tapping whatever the Games hub lists first: the local database
    /// carries every deck row but not every deck's prompts (production has content that was added
    /// outside the migrations), so the hub's first deck may be one the RPC refuses as empty.
    func startDeck(gameType: String) async throws -> UUID {
        let table = [
            "trivia_battle": "trivia_questions",
            "more_likely": "more_likely_prompts",
            "this_or_that": "this_or_that_prompts",
            "deep_conversations": "deep_conversation_topics",
        ][gameType]
        guard let table else { throw LocalStack.Failure(description: "\(gameType) has no decks") }
        let prompts = try await LocalStack.send(
            "GET", "rest/v1/\(table)",
            query: [
                URLQueryItem(name: "select", value: "deck_id,game_decks!inner(tier,game_type)"),
                URLQueryItem(name: "active", value: "is.true"),
                URLQueryItem(name: "game_decks.tier", value: tier == .premium ? "in.(plus,premium)" : "eq.plus"),
                URLQueryItem(name: "limit", value: "1"),
            ],
            as: .service
        ) as? [[String: Any]]
        guard let deckID = prompts?.first?["deck_id"] as? String else {
            throw LocalStack.Failure(description: "no \(gameType) deck with content on this stack")
        }
        let session = try await LocalStack.rpc("start_deck_session", ["p_deck_id": deckID], as: me.caller)
        guard let raw = session as? String ?? (session as? [String: Any])?["id"] as? String,
              let id = UUID(uuidString: raw) else {
            throw LocalStack.Failure(description: "start_deck_session returned \(String(describing: session))")
        }
        return id
    }

    /// A game session's status as the server has it — for asserting on what the UI did.
    func gameSessionStatus(_ id: UUID) async throws -> String? {
        let rows = try await LocalStack.send(
            "GET", "rest/v1/game_sessions",
            query: [URLQueryItem(name: "id", value: "eq.\(id)"), URLQueryItem(name: "select", value: "status")],
            as: .service
        ) as? [[String: Any]]
        return rows?.first?["status"] as? String
    }

    /// The couple's memories as the server has them, by title — for asserting on what reached it.
    func memoryRows() async throws -> [(id: UUID, title: String)] {
        let coupleID = try requireCouple()
        let rows = try await LocalStack.send(
            "GET", "rest/v1/memories",
            query: [URLQueryItem(name: "couple_id", value: "eq.\(coupleID)"), URLQueryItem(name: "select", value: "id,title")],
            as: .service
        ) as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let raw = row["id"] as? String, let id = UUID(uuidString: raw),
                  let title = row["title"] as? String else { return nil }
            return (id, title)
        }
    }

    /// One row of a table as the server has it, by id — the columns asked for, read with the
    /// service role.
    func row(_ table: String, id: UUID, columns: String) async throws -> [String: Any]? {
        let rows = try await LocalStack.send(
            "GET", "rest/v1/\(table)",
            query: [URLQueryItem(name: "id", value: "eq.\(id)"), URLQueryItem(name: "select", value: columns)],
            as: .service
        ) as? [[String: Any]]
        return rows?.first
    }

    /// An edit the partner makes from their phone: the app's own table update, as them.
    func updateAsPartner(_ table: String, id: UUID, _ fields: [String: Any]) async throws {
        guard let partner else { throw LocalStack.Failure(description: "updateAsPartner needs a paired scenario") }
        try await LocalStack.send(
            "PATCH", "rest/v1/\(table)",
            query: [URLQueryItem(name: "id", value: "eq.\(id)")],
            body: fields,
            as: partner.caller
        )
    }

    /// Ends a game as the partner would from their phone, through the RPC their abandon menu calls.
    func abandonAsPartner(_ id: UUID) async throws {
        guard let partner else { throw LocalStack.Failure(description: "abandonAsPartner needs a paired scenario") }
        _ = try await LocalStack.rpc("abandon_game_session", ["p_session_id": id.uuidString], as: partner.caller)
    }

    /// Every Sudoku session this account started, newest first.
    func sudokuSessions() async throws -> [(id: UUID, status: String)] {
        try await sessions(gameType: "sudoku")
    }

    /// Every session of one game this account started, newest first.
    func sessions(gameType: String) async throws -> [(id: UUID, status: String)] {
        let rows = try await LocalStack.send(
            "GET", "rest/v1/game_sessions",
            query: [
                URLQueryItem(name: "initiator_id", value: "eq.\(me.id)"),
                URLQueryItem(name: "game_type", value: "eq.\(gameType)"),
                URLQueryItem(name: "select", value: "id,status"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ],
            as: .service
        ) as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let raw = row["id"] as? String, let id = UUID(uuidString: raw),
                  let status = row["status"] as? String else { return nil }
            return (id, status)
        }
    }

    // MARK: - Building blocks

    /// Unique per call, so no two tests — or two runs of one — ever meet the same account.
    static func makeAccount(firstName: String) async throws -> TestAccount {
        let tag = UUID().uuidString.prefix(8).lowercased()
        let email = "e2e-\(firstName.lowercased())-\(tag)@e2e.twofold.test"
        let password = "e2e-\(UUID().uuidString)"
        let id = try await LocalStack.createUser(email: email, password: password, firstName: firstName)
        let token = try await LocalStack.signIn(email: email, password: password)
        return TestAccount(id: id, email: email, password: password, firstName: firstName, accessToken: token)
    }

    /// `BackendService.markOnboardingCompleted`, made as the account. Also stamps account creation,
    /// which in-app onboarding writes at "Save your progress".
    static func completeOnboarding(_ account: TestAccount) async throws {
        let now = iso(Date())
        try await LocalStack.send(
            "PATCH", "rest/v1/profiles",
            query: [URLQueryItem(name: "id", value: "eq.\(account.id)")],
            body: ["onboarding_completed_at": now, "onboarding_account_created_at": now],
            as: account.caller
        )
    }

    /// The invite flow, each step as the person who takes it in the app. Redeemed by code rather
    /// than by link, so the inviter's accept is a step of its own — a link would auto-accept, which
    /// skips `respond_to_connection_request` entirely.
    static func pair(inviter: TestAccount, redeemer: TestAccount) async throws -> UUID {
        let invite = try await LocalStack.rpc("create_invite_code", as: inviter.caller) as? [String: Any]
        guard let code = invite?["code"] as? String else {
            throw LocalStack.Failure(description: "create_invite_code returned \(String(describing: invite))")
        }
        let redeemed = try await LocalStack.rpc(
            "redeem_invite_code", ["p_code": code, "p_origin": "code"], as: redeemer.caller
        ) as? [[String: Any]]
        guard let requestID = redeemed?.first?["id"] as? String else {
            throw LocalStack.Failure(description: "redeem_invite_code refused: \(String(describing: redeemed))")
        }
        let couple = try await LocalStack.rpc(
            "respond_to_connection_request", ["p_request_id": requestID, "p_accept": true], as: inviter.caller
        ) as? [String: Any]
        guard let raw = couple?["id"] as? String, let id = UUID(uuidString: raw) else {
            throw LocalStack.Failure(description: "respond_to_connection_request returned \(String(describing: couple))")
        }
        return id
    }

    /// `create_invite_code`, as the inviter — the code their "Share my invite code" mints.
    static func inviteCode(from inviter: TestAccount) async throws -> String {
        let invite = try await LocalStack.rpc("create_invite_code", as: inviter.caller) as? [String: Any]
        guard let code = invite?["code"] as? String else {
            throw LocalStack.Failure(description: "create_invite_code returned \(String(describing: invite))")
        }
        return code
    }

    /// `redeem_invite_code` as the redeemer, by typed code: a request the inviter has to answer.
    static func requestToConnect(redeemer: TestAccount, code: String) async throws {
        let redeemed = try await LocalStack.rpc(
            "redeem_invite_code", ["p_code": code, "p_origin": "code"], as: redeemer.caller
        ) as? [[String: Any]]
        guard redeemed?.first?["id"] is String else {
            throw LocalStack.Failure(description: "redeem_invite_code refused: \(String(describing: redeemed))")
        }
    }

    /// The partner leaves, through the RPC "Disconnect my partner" calls. The couple is archived,
    /// not deleted, which is what lets a later accept offer to bring it back.
    func partnerLeaves() async throws {
        guard let partner, let coupleID else { throw LocalStack.Failure(description: "partnerLeaves needs a paired scenario") }
        _ = try await LocalStack.rpc("leave_couple", ["p_couple_id": coupleID.uuidString], as: partner.caller)
    }

    /// The active couple between these two, if there is one — for asserting on a pairing.
    static func activeCouple(between a: TestAccount, and b: TestAccount) async throws -> UUID? {
        let rows = try await LocalStack.send(
            "GET", "rest/v1/couples",
            query: [
                URLQueryItem(name: "status", value: "eq.active"),
                URLQueryItem(name: "or", value: "(and(partner_a_id.eq.\(a.id),partner_b_id.eq.\(b.id)),and(partner_a_id.eq.\(b.id),partner_b_id.eq.\(a.id)))"),
                URLQueryItem(name: "select", value: "id"),
            ],
            as: .service
        ) as? [[String: Any]]
        return (rows?.first?["id"] as? String).flatMap(UUID.init(uuidString:))
    }

    /// `block_profile`, as `blocker` — the block the request screen's menu makes.
    static func block(_ blocked: TestAccount, by blocker: TestAccount) async throws {
        _ = try await LocalStack.rpc("block_profile", ["p_profile_id": blocked.id.uuidString], as: blocker.caller)
    }

    /// Whether `blocker` still has `blocked` blocked, as the server has it.
    static func isBlocked(_ blocked: TestAccount, by blocker: TestAccount) async throws -> Bool {
        let rows = try await LocalStack.send(
            "GET", "rest/v1/blocked_profiles",
            query: [
                URLQueryItem(name: "blocker_id", value: "eq.\(blocker.id)"),
                URLQueryItem(name: "blocked_id", value: "eq.\(blocked.id)"),
                URLQueryItem(name: "select", value: "blocked_id"),
            ],
            as: .service
        ) as? [[String: Any]] ?? []
        return !rows.isEmpty
    }

    /// The account the app made for an email, once onboarding has created it — for a test that
    /// signs up through the screens rather than through `makeAccount`.
    static func profile(email: String) async throws -> [String: Any]? {
        let users = try await LocalStack.send("GET", "auth/v1/admin/users", query: [URLQueryItem(name: "per_page", value: "1000")], as: .service) as? [String: Any]
        let list = users?["users"] as? [[String: Any]] ?? []
        guard let raw = list.first(where: { ($0["email"] as? String) == email })?["id"] as? String else { return nil }
        let rows = try await LocalStack.send(
            "GET", "rest/v1/profiles",
            query: [URLQueryItem(name: "id", value: "eq.\(raw)"), URLQueryItem(name: "select", value: "id,onboarding_account_created_at")],
            as: .service
        ) as? [[String: Any]]
        return rows?.first
    }

    /// What the RevenueCat webhook's `applyState` would have written for this person, and the
    /// `subscription_events` it would have logged on the way.
    static func apply(tier: TestTier, to account: TestAccount) async throws {
        let now = Date()
        let day: TimeInterval = 86_400
        let profile: [String: Any]
        var events: [[String: Any?]] = []
        switch tier {
        case .none:
            return
        case .plus, .premium:
            profile = [
                "subscription_active": true,
                "subscription_tier": tier.rawValue,
                "subscription_checked_at": iso(now),
                "subscription_started_at": iso(now.addingTimeInterval(-30 * day)),
                "subscription_will_renew": true,
                "subscription_store": "app_store",
                "subscription_is_trial": false,
                "subscription_expires_at": iso(now.addingTimeInterval(30 * day)),
            ]
            events = [["event_type": "INITIAL_PURCHASE", "tier": tier.rawValue, "state_as_of": iso(now.addingTimeInterval(-30 * day))]]
        case .lapsed:
            // On expiry the webhook clears everything but the active flag and the stamp, so a
            // lapsed row looks like a never-subscribed one. What tells them apart is the history.
            profile = [
                "subscription_active": false,
                "subscription_tier": NSNull(),
                "subscription_checked_at": iso(now),
                "subscription_started_at": NSNull(),
                "subscription_will_renew": NSNull(),
                "subscription_store": NSNull(),
                "subscription_is_trial": NSNull(),
                "subscription_expires_at": NSNull(),
            ]
            events = [
                ["event_type": "INITIAL_PURCHASE", "tier": "plus", "state_as_of": iso(now.addingTimeInterval(-60 * day))],
                ["event_type": "EXPIRATION", "tier": nil, "state_as_of": iso(now.addingTimeInterval(-5 * day)), "expiration_reason": "UNSUBSCRIBE"],
            ]
        }
        try await LocalStack.send(
            "PATCH", "rest/v1/profiles",
            query: [URLQueryItem(name: "id", value: "eq.\(account.id)")],
            body: profile,
            as: .service
        )
        for event in events {
            var row: [String: Any] = ["profile_id": account.id.uuidString, "outcome": "written", "event_id": "e2e-\(UUID())"]
            for (key, value) in event { row[key] = value ?? NSNull() }
            try await LocalStack.send("POST", "rest/v1/subscription_events", body: row, as: .service)
        }
    }

    // MARK: - Helpers

    /// The partner adds content when the couple pays, the way the app would; otherwise the service
    /// role stands in for the past in which they did. See the header.
    private var contentWriter: LocalStack.Caller {
        switch tier {
        case .plus, .premium: me.caller
        case .none, .lapsed: .service
        }
    }

    private func requireCouple() throws -> UUID {
        guard let coupleID else { throw LocalStack.Failure(description: "this scenario has no couple to add content to") }
        return coupleID
    }

    /// `find_or_create_place`, the RPC `BackendService.findOrCreatePlaceID` calls.
    private func placeID(_ place: TestPlace) async throws -> UUID {
        let result = try await LocalStack.rpc("find_or_create_place", [
            "p_city": place.city,
            "p_country": place.country,
            "p_iata_code": place.iata,
            "p_latitude": place.latitude,
            "p_longitude": place.longitude,
            "p_timezone": place.timeZone,
        ], as: me.caller)
        guard let raw = result as? String, let id = UUID(uuidString: raw) else {
            throw LocalStack.Failure(description: "find_or_create_place returned \(String(describing: result))")
        }
        return id
    }

    static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

struct TestPlace {
    let city: String
    let country: String
    let iata: String
    let latitude: Double
    let longitude: Double
    let timeZone: String

    static let melbourne = TestPlace(city: "Melbourne", country: "Australia", iata: "MEL", latitude: -37.8136, longitude: 144.9631, timeZone: "Australia/Melbourne")
    static let rome = TestPlace(city: "Rome", country: "Italy", iata: "FCO", latitude: 41.9028, longitude: 12.4964, timeZone: "Europe/Rome")
}

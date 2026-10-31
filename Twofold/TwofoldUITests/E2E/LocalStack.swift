//
//  LocalStack.swift
//  TwofoldUITests
//
//  The test runner's own line to the local Supabase stack: Auth's admin API to create accounts,
//  password sign-in to act as them, and PostgREST for the app's RPCs and the few writes only the
//  subscription webhook is allowed to make.
//
//  The runner can reach 127.0.0.1 because a simulator shares the Mac's network, so this talks to
//  the same stack the app under test does (`SUPABASE_ENV=local`). Both keys are the Supabase CLI's
//  fixed defaults, printed by `supabase start` on every machine and worthless against any real
//  project. The publishable one is written out below. The secret one is not: it still has the shape
//  of a service key, and GitHub's push protection refuses any commit carrying one. It is read
//  instead from `.env.e2e.local` at the repo root (git-ignored), which
//  `supabase status -o env > .env.e2e.local` writes.
//
//  Never pointed anywhere else. The URL is a constant rather than read from the environment on
//  purpose: a seeding helper that writes subscription state with a service key is the last thing
//  that should be one mistyped variable away from production.
//

import Foundation
import XCTest

enum LocalStack {
    static let url = URL(string: "http://127.0.0.1:54321")!
    static let publishableKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
    /// Service-role. Used for exactly two things: creating users through the admin API, and the
    /// writes the app is refused (`profiles.subscription_*`, `subscription_events`), which in
    /// production only the RevenueCat webhook makes — with this same role.
    ///
    /// Found from this file's own path rather than the bundle: the simulator shares the Mac's
    /// filesystem, and a file inside the test target's folder would be copied into the bundle.
    static func secretKey() throws -> String {
        let keysFile = URL(filePath: #filePath)
            .deletingLastPathComponent()  // E2E
            .deletingLastPathComponent()  // TwofoldUITests
            .deletingLastPathComponent()  // Twofold
            .deletingLastPathComponent()  // repo root
            .appending(path: ".env.e2e.local")
        let contents = (try? String(contentsOf: keysFile, encoding: .utf8)) ?? ""
        for line in contents.split(whereSeparator: \.isNewline) where line.hasPrefix("SECRET_KEY=") {
            let value = line.dropFirst("SECRET_KEY=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            if !value.isEmpty { return value }
        }
        throw Failure(description: "No SECRET_KEY in \(keysFile.path). From the repo root, with the local stack running:\n  \(keysCommand)")
    }

    static let keysCommand = "supabase status -o env > .env.e2e.local"

    static let startCommand = "supabase start -x studio,logflare,vector,imgproxy,mailpit,edge-runtime,realtime,supavisor,postgres-meta --ignore-health-check"

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// Fails the calling test with instructions when nothing answers, rather than letting the first
    /// seed call fail with a bare "could not connect".
    static func requireReachable(file: StaticString = #filePath, line: UInt = #line) async throws {
        var request = URLRequest(url: url.appending(path: "auth/v1/health"))
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 200 { return }
        } catch {}
        let message = "The local Supabase stack isn't answering at \(url). Start it from the repo root with:\n  \(startCommand)\n(and `supabase db reset --local` if migrations are behind)."
        XCTFail(message, file: file, line: line)
        throw Failure(description: message)
    }

    /// Same idea for the key file: fail at the start of the test with the command to run, rather
    /// than at the first seed call.
    static func requireSecretKey(file: StaticString = #filePath, line: UInt = #line) throws {
        do {
            _ = try secretKey()
        } catch {
            XCTFail(String(describing: error), file: file, line: line)
            throw error
        }
    }

    // MARK: - Requests

    enum Caller {
        /// Signed in as an account, through its access token — RLS applies, as it does to the app.
        case user(accessToken: String)
        /// Service role. Bypasses RLS and the client-write guards.
        case service
    }

    @discardableResult
    static func send(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Any? = nil,
        as caller: Caller,
        prefer: String? = nil
    ) async throws -> Any? {
        var components = URLComponents(url: url.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch caller {
        case .user(let token):
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .service:
            let secretKey = try secretKey()
            request.setValue(secretKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(secretKey)", forHTTPHeaderField: "Authorization")
        }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw Failure(description: "\(method) \(path) → \(status): \(text)")
        }
        guard !data.isEmpty else { return nil }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// `POST /rest/v1/rpc/<name>` — the app's own database functions, called as whoever `caller` is.
    @discardableResult
    static func rpc(_ name: String, _ params: [String: Any] = [:], as caller: Caller) async throws -> Any? {
        try await send("POST", "rest/v1/rpc/\(name)", body: params, as: caller)
    }

    // MARK: - Auth

    /// A confirmed account, created the way an admin would — no email round trip. `first_name` in
    /// the metadata is what `handle_new_user` copies onto the profile row it creates.
    static func createUser(email: String, password: String, firstName: String) async throws -> UUID {
        let json = try await send("POST", "auth/v1/admin/users", body: [
            "email": email,
            "password": password,
            "email_confirm": true,
            "user_metadata": ["first_name": firstName],
        ], as: .service) as? [String: Any]
        guard let raw = json?["id"] as? String, let id = UUID(uuidString: raw) else {
            throw Failure(description: "admin create user returned no id: \(String(describing: json))")
        }
        return id
    }

    /// The same password grant the app's email form uses.
    static func signIn(email: String, password: String) async throws -> String {
        var request = URLRequest(url: url.appending(path: "auth/v1/token").appending(queryItems: [
            URLQueryItem(name: "grant_type", value: "password"),
        ]))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = json?["access_token"] as? String else {
            throw Failure(description: "password sign-in for \(email) failed: \(String(data: data, encoding: .utf8) ?? "")")
        }
        return token
    }
}

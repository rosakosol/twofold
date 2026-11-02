//
//  EdgeFunctions.swift
//  Twofold
//
//  The one way the app calls a Supabase Edge Function (CORE-22).
//
//  Every caller used to build its own `URLRequest` to `functions/v1/<name>`, set the key, bearer
//  and content type by hand, and decode failures its own way: `{ "error": … }` in one place, a
//  bare status code in another, nothing at all in a third. They now all come through here, so the
//  token is always the refreshed one, every request has the same timeout, and a failure always
//  arrives in the same shape. Each caller still turns that shape into its own error type, which
//  is what its screen already knows how to show.
//

import Foundation

enum EdgeFunctions {

    /// How a call failed, when it got as far as the function or had no session to call as.
    /// Transport failures (`URLError`: offline, timed out) are thrown as they are, because callers
    /// already tell those apart and `BackendService.isPermanentRefusal` treats them as temporary.
    enum Failure: Error, Equatable {
        /// No session, so nothing was sent.
        case notAuthenticated
        /// The function answered with a status outside 2xx. `message` is its `{ "error": … }` text
        /// when it sent one, and `body` the raw bytes for callers that read more fields than that.
        case status(Int, message: String?, body: Data)
        /// A 2xx answer whose body is not the shape asked for.
        case undecodable
    }

    /// How long a call may sit with nothing arriving before it gives up. `URLRequest`'s own default
    /// is 60 seconds, which for a quick function reads as a hang. The functions that wait on
    /// somebody else (an airline feed, a language model) pass `slowTimeout`.
    nonisolated static let defaultTimeout: TimeInterval = 30
    nonisolated static let slowTimeout: TimeInterval = 60

    /// The request for `name`, ready to send. Separate so the headers can be checked without a
    /// network.
    static func request(_ name: String, body: Data?, accessToken: String, timeout: TimeInterval = defaultTimeout) -> URLRequest {
        var request = URLRequest(url: SupabaseConfig.projectURL.appendingPathComponent("functions/v1/\(name)"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apiKey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    /// Calls `name` and returns the body of its 2xx answer.
    ///
    /// The token is `BackendService.freshAccessToken()`, refreshed if it has expired, unless the
    /// caller already holds one for a batch of calls (see `R2Storage.readURLs`). `body` is sent as
    /// JSON; nil sends no body at all, which is what the functions that take none expect.
    @discardableResult
    static func send(
        _ name: String,
        body: [String: Any]? = nil,
        accessToken suppliedToken: String? = nil,
        timeout: TimeInterval = defaultTimeout
    ) async throws -> Data {
        let token: String?
        if let suppliedToken { token = suppliedToken } else { token = await BackendService.freshAccessToken() }
        guard let accessToken = token else { throw Failure.notAuthenticated }

        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let (responseData, response) = try await URLSession.shared.data(for: request(name, body: data, accessToken: accessToken, timeout: timeout))
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw Failure.status(status, message: errorMessage(in: responseData), body: responseData)
        }
        return responseData
    }

    /// `send`, with the answer decoded as `Response`.
    static func invoke<Response: Decodable>(
        _ name: String,
        body: [String: Any]? = nil,
        accessToken: String? = nil,
        timeout: TimeInterval = defaultTimeout,
        decoder: JSONDecoder = JSONDecoder(),
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await send(name, body: body, accessToken: accessToken, timeout: timeout)
        guard let decoded = try? decoder.decode(Response.self, from: data) else { throw Failure.undecodable }
        return decoded
    }

    /// The `{ "error": "…" }` every function answers a failure with. Nil when the body is not that
    /// shape or the text is empty, so a caller falls back to its own wording rather than a blank.
    static func errorMessage(in body: Data) -> String? {
        struct ErrorBody: Decodable { var error: String? }
        guard let message = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error, !message.isEmpty else { return nil }
        return message
    }
}

//
//  PermanentRefusalTests.swift
//  TwofoldTests
//
//  `BackendService.isPermanentRefusal` decides whether a failed write is rolled back or kept and
//  sent again later (CORE-35). It used to match on the error's description, which never contains
//  the status code for the errors the SDK actually throws, and could not see a refused photo
//  upload at all — so those were retried for ever.
//

import Foundation
import Testing
import Supabase
@testable import Twofold

struct PermanentRefusalTests {

    private static func http(_ status: Int) -> HTTPError {
        let response = HTTPURLResponse(url: URL(string: "https://example.invalid")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return HTTPError(data: Data(), response: response)
    }

    @Test("refusals", arguments: [
        PostgrestError(code: "42501", message: "new row violates row-level security policy for table \"memories\"") as Error,
        PostgrestError(code: "42501", message: "account_deleted"),
        http(403),
        FunctionsError.httpError(code: 403, data: Data()),
        R2Storage.StorageError.refused(status: 403),
        BackendService.WriteAffectedNoRows(),
    ])
    func refused(_ error: Error) {
        #expect(BackendService.isPermanentRefusal(error), "\(error)")
    }

    @Test("failures worth trying again", arguments: [
        URLError(.notConnectedToInternet) as Error,
        URLError(.timedOut),
        PostgrestError(code: "PGRST301", message: "JWT expired"),
        // An expired access token. Refreshed, the same write goes through.
        http(401),
        FunctionsError.httpError(code: 401, data: Data()),
        PostgrestError(code: "57014", message: "canceling statement due to statement timeout"),
        http(500),
        http(503),
        FunctionsError.httpError(code: 502, data: Data()),
        R2Storage.StorageError.uploadFailed,
        R2Storage.StorageError.urlUnavailable,
    ])
    func transient(_ error: Error) {
        #expect(!BackendService.isPermanentRefusal(error), "\(error)")
    }
}

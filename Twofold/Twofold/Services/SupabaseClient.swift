//
//  SupabaseClient.swift
//  Twofold
//
//  Single shared client instance, reused across auth/database calls.
//

import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.projectURL,
    supabaseKey: SupabaseConfig.publishableKey,
    options: SupabaseClientOptions(
        // Opts into supabase-swift's upcoming default now: emit the locally stored session
        // immediately rather than emitting nil whenever a background token refresh happens
        // to fail (e.g. a brief network hiccup at launch). We don't gate anything off
        // `authStateChanges` ourselves — `BackendService.restoreSession()` calls
        // `supabase.auth.session` directly, which already refreshes/validates properly — so
        // this only affects internal SDK subscribers (e.g. Realtime's token sync) and quiets
        // the console warning. See https://github.com/supabase/supabase-swift/pull/822.
        auth: .init(emitLocalSessionAsInitialSession: true)
    )
)

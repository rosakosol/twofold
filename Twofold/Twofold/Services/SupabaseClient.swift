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
    supabaseKey: SupabaseConfig.publishableKey
)

//
//  SupabaseConfig.swift
//  Twofold
//
//  The publishable (anon) key is meant to ship inside the client — it's scoped by
//  Row Level Security, not secrecy. Nothing privileged is ever called with it.
//

import Foundation

enum SupabaseConfig {
    static let projectURL = URL(string: "https://ipfzswswwukfqphloojo.supabase.co")!
    static let publishableKey = "sb_publishable_KvH6r2_haPL1sbAc1d4F-Q_5l1ImkpK"
}

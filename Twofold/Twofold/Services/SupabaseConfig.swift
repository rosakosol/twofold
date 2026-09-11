//
//  SupabaseConfig.swift
//  Twofold
//
//  The publishable (anon) key is meant to ship inside the client — it's scoped by
//  Row Level Security, not secrecy. Nothing privileged is ever called with it.
//
//  Which backend a build talks to is resolved at launch from the environment rather than
//  hardcoded, because the alternative was hand-editing the constants below to point at a local
//  Supabase and remembering to revert before committing. That worked until it didn't: a stray
//  `http://127.0.0.1` shipped in a release build would break the app for everyone, and the only
//  thing standing between us and that was remembering to check `git status`. Environment
//  variables live in the Xcode scheme, aren't part of the source tree, and can't be committed.
//
//  Release builds ignore the environment entirely and always use production — an override that
//  only exists in DEBUG can't leak into an archive no matter what's set on the build machine.
//
//  To point a debug build somewhere else, edit the Twofold scheme (Product ▸ Scheme ▸ Edit Scheme
//  ▸ Run ▸ Arguments ▸ Environment Variables) and tick one of:
//
//    SUPABASE_ENV = local          talks to the Supabase CLI's default local stack
//    SUPABASE_URL = https://…      plus SUPABASE_PUBLISHABLE_KEY, for a staging project
//
//  On a physical device `SUPABASE_ENV=local` won't resolve — 127.0.0.1 is the phone itself — so
//  set SUPABASE_URL to the Mac's LAN address (e.g. http://192.168.1.20:54321) instead.
//

import Foundation

enum SupabaseConfig {
    /// The real backend. Also the fallback whenever no override is set, and the only thing a
    /// Release build will ever use.
    private enum Production {
        static let url = URL(string: "https://ipfzswswwukfqphloojo.supabase.co")!
        static let publishableKey = "sb_publishable_KvH6r2_haPL1sbAc1d4F-Q_5l1ImkpK"
    }

    /// Fixed defaults baked into the Supabase CLI — the same values `supabase start` prints for
    /// every project on every machine, so there's nothing machine-specific to configure.
    ///
    /// This URL is plain `http`, which App Transport Security blocks by default. What allows it is
    /// `NSAppTransportSecurity` → `NSAllowsLocalNetworking` in `Info.plist`: that key relaxes ATS
    /// for loopback and link-local addresses **only**, so it cannot weaken TLS for any remote host
    /// and production traffic is unaffected by it.
    ///
    /// Recorded here rather than beside the key itself because that explanation used to be an XML
    /// comment in `Info.plist`, and Xcode 27 rewriting the file deleted it — build settings and
    /// generated plists have nowhere to keep a comment, so the reasoning has to live in source.
    /// If that key ever disappears, this is what breaks: `SUPABASE_ENV=local` starts failing every
    /// request with an ATS error rather than anything that names the real cause.
    private enum Local {
        static let url = URL(string: "http://127.0.0.1:54321")!
        static let publishableKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
    }

    private static let resolved: (url: URL, publishableKey: String) = {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment

        if let raw = environment["SUPABASE_URL"], let url = URL(string: raw), url.host != nil {
            // A custom URL needs its own key — production's won't authenticate against another
            // project, and silently pairing them would fail in a way that looks like an outage.
            guard let key = environment["SUPABASE_PUBLISHABLE_KEY"], !key.isEmpty else {
                fatalError("SUPABASE_URL is set without SUPABASE_PUBLISHABLE_KEY — set both or neither.")
            }
            return (url, key)
        }

        if environment["SUPABASE_ENV"]?.lowercased() == "local" {
            return (Local.url, Local.publishableKey)
        }
        #endif

        return (Production.url, Production.publishableKey)
    }()

    static var projectURL: URL { resolved.url }
    static var publishableKey: String { resolved.publishableKey }

    /// True whenever this build is pointed at something other than production. Handy for putting a
    /// visible marker in the UI so a screenshot from a local stack is never mistaken for real data.
    static var isUsingProduction: Bool { resolved.url == Production.url }
}

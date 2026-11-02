//
//  BackendService+Realtime.swift
//  Twofold
//
//  The one way a screen listens for database changes (CORE-25).
//
//  Five subscribe functions each made a channel, made an `AsyncStream`, and started a task that
//  ran `try? await channel.subscribeWithError()` before forwarding the changes. The `try?` meant a
//  channel that failed to join was silent: the screen simply never updated live, and nothing said
//  why. They now share `realtimeStream`, which says so in the log, and stops forwarding when
//  whoever was reading the stream stops.
//

import Foundation
import Supabase

extension BackendService {

    /// One kind of row change a channel listens for.
    struct RealtimeChange {
        enum Event { case insert, update }
        var event: Event
        var table: String
        var filter: RealtimePostgresFilter?

        static func insert(_ table: String, filter: RealtimePostgresFilter? = nil) -> RealtimeChange {
            RealtimeChange(event: .insert, table: table, filter: filter)
        }

        static func update(_ table: String, filter: RealtimePostgresFilter? = nil) -> RealtimeChange {
            RealtimeChange(event: .update, table: table, filter: filter)
        }
    }

    /// A channel that yields once for every change in `changes`, with no payload. The caller
    /// re-fetches through the RLS-protected select rather than trusting what realtime carried.
    static func signalStream(channelName: String, changes: [RealtimeChange]) -> (channel: RealtimeChannelV2, stream: AsyncStream<Void>) {
        let channel = supabase.channel(channelName)
        // Registered before subscribing: a channel only delivers to listeners it had when it joined.
        let sources: [RealtimeSource<Void>] = changes.map { change in
            switch change.event {
            case .insert:
                let inserts = channel.postgresChange(InsertAction.self, table: change.table, filter: change.filter)
                return { continuation in for await _ in inserts { continuation.yield(()) } }
            case .update:
                let updates = channel.postgresChange(UpdateAction.self, table: change.table, filter: change.filter)
                return { continuation in for await _ in updates { continuation.yield(()) } }
            }
        }
        return (channel, realtimeStream(channel, name: channelName, sources: sources))
    }

    /// Forwards what one listener on a channel hears into the stream the caller reads.
    typealias RealtimeSource<Element> = @MainActor @Sendable (AsyncStream<Element>.Continuation) async -> Void

    /// Subscribes `channel`, then runs every source until they all end or the reader stops.
    ///
    /// A failed subscribe is logged rather than thrown: the screen still has what it loaded, and
    /// the next foreground or pull-to-refresh reads again. Before this it was not even logged.
    static func realtimeStream<Element>(_ channel: RealtimeChannelV2, name: String, sources: [RealtimeSource<Element>]) -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream<Element>.makeStream()
        let forwarding = Task {
            do {
                try await channel.subscribeWithError()
            } catch {
                print("[realtime] \(name) did not subscribe, so it will not update live: \(error)")
            }
            await withTaskGroup(of: Void.self) { group in
                for source in sources {
                    group.addTask { await source(continuation) }
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in forwarding.cancel() }
        return stream
    }
}

import Foundation
import Supabase

/// Server-side verification of the premium entitlement (S5.3).
///
/// The freemium gate trusts StoreKit on device, but the leagues RPCs enforce
/// the free one-league cap against a server-verified entitlement
/// (`premium_entitlements`, S5.1). `PremiumSync` is the bridge: it posts the
/// JWS of the verified current entitlement to the `verify-premium` Edge
/// Function so the server can build its own entitlement record.
///
/// The sync is strictly **best effort**: it runs in the background, never
/// blocks the UI, never throws to the caller, and reports failures through the
/// crash reporter's sanitized path only (`CrashReporting.capture` collapses
/// any non-`CrashReport` error into the fallback bucket, so no response body
/// or URL ever leaves the device, S5).
///
/// Dedupe: the same JWS is posted at most once per session. StoreKit replays
/// `Transaction.updates` on every launch and the service re-reads the plan on
/// every paywall close, but the server answer for a given JWS cannot change,
/// so one post is enough.
protocol PremiumSyncing {

    /// Posts the JWS of the verified current entitlement. Best effort:
    /// deduped per session and silently reported on failure.
    func post(jws: String) async
}

/// Boundary between `PremiumSync` and the `verify-premium` Edge Function, so
/// the sync logic is tested without a network (contract fixed by S5.2).
protocol PremiumSyncEndpoint {

    /// Posts `jws` as the body of `POST verify-premium` with the session JWT.
    /// Throws on every non-2xx answer (400 `invalid_jws`, 401, 409
    /// `transaction_linked`) and on transport errors.
    func verify(jws: String) async throws
}

/// Real endpoint of S5.2: the `verify-premium` Edge Function of the project's
/// Supabase instance.
///
/// supabase-swift attaches the signed-in user's JWT to every function
/// invocation automatically (`SupabaseClient.functions` builds the call on
/// `fetchWithAuth`, v2.55.5), so the body carries only the JWS.
struct SupabasePremiumSyncEndpoint: PremiumSyncEndpoint {

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    func verify(jws: String) async throws {
        // The `Void` overload of `invoke` throws `FunctionsError.httpError`
        // on every non-2xx status: `PremiumSync` needs no response body, the
        // distinction between 400/401/409 only matters for the log code.
        try await client.functions.invoke(
            "verify-premium",
            options: .init(body: ["jws": jws])
        )
    }
}

/// Best-effort poster of the premium JWS to `verify-premium` (S5.3).
///
/// Called at launch after sign-in (the plan read of `FreemiumService.refresh`)
/// and on every StoreKit transaction update `FreemiumService` already
/// observes; also after a purchase or restore, which produce transactions the
/// server has not seen yet. All are one path: `FreemiumService.apply`.
@MainActor
final class PremiumSync: PremiumSyncing {

    private let endpoint: PremiumSyncEndpoint

    /// JWSs already posted this session, so `Transaction.updates` replays and
    /// plan re-reads never cause a second post of the same transaction.
    private var postedJWSs: Set<String> = []

    // Nonisolated so it can be a default argument of `FreemiumService.init`
    // (default arguments are evaluated outside the main actor); it only stores.
    nonisolated init(endpoint: PremiumSyncEndpoint = SupabasePremiumSyncEndpoint()) {
        self.endpoint = endpoint
    }

    /// Posts `jws` once per session, never throws.
    ///
    /// The dedupe marker is inserted *before* the request so two concurrent
    /// reads of the same entitlement cannot start two posts. A failed post is
    /// not retried within the session: the next StoreKit transaction (renewal,
    /// purchase) carries a different JWS and starts a new attempt, and the
    /// launch after a restart re-posts the still-current JWS.
    func post(jws: String) async {
        guard !postedJWSs.contains(jws) else { return }
        postedJWSs.insert(jws)

        do {
            try await endpoint.verify(jws: jws)
        } catch {
            // Not a `CrashReport`: the sanitizer replaces it with the stable
            // fallback bucket, so no JWS, URL or response body leaves the
            // device (S5).
            CrashReporting.capture(error)
        }
    }
}

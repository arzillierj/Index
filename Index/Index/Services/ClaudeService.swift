import Foundation
import SwiftData

/// Foundation for the optional AI meal-photo macro estimator.
///
/// This commit ships ONLY the money-safety scaffolding: Keychain
/// API-key storage, monthly cost tracking via `AIUsageRecord`,
/// and a hard monthly budget gate. The actual vision API call
/// lands in a follow-up commit — nothing here invokes the
/// network. Building the cap first means the network commit
/// can't ship a code path that spends without a limit already
/// in place.
///
/// Security model: the Anthropic API key is stored in iOS
/// Keychain (`kSecAttrAccessibleAfterFirstUnlock` +
/// `kSecAttrSynchronizable`) entered once by the user. The key
/// is NEVER compiled in, NEVER committed, NEVER written to a
/// doc. This is correct for a private TestFlight app; it is NOT
/// hacker-proof — any key shipped to a device is extractable.
/// A true zero-extraction setup would need a backend proxy and
/// is explicitly out of scope.
///
/// Cost constants below are CURRENT as of May 2026, Claude Haiku
/// 4.5 (`claude-haiku-4-5-20251001`). Anthropic can change
/// pricing — if month-to-date totals look off, re-verify against
/// anthropic.com/pricing and update the constants here.
@Observable
@MainActor
final class ClaudeService {

    /// Keychain account string. Namespaced to avoid collision
    /// with `DevIdentityService`'s `index.dev.userId`.
    private static let apiKeyAccount = "index.ai.anthropicAPIKey"

    /// UserDefaults key for the monthly budget cap (USD).
    /// UserDefaults is correct here — this is operational state
    /// (a toggle / threshold), not identity-bearing data.
    static let monthlyBudgetKey = "ai.monthlyBudgetUSD"

    /// Default cap if the user never edits it. $2/month covers
    /// roughly 200 meal-photo estimates at typical token counts.
    static let defaultMonthlyBudgetUSD: Double = 2.0

    /// Anthropic API pricing per million tokens. Haiku 4.5
    /// (claude-haiku-4-5-20251001), verified May 2026. Update
    /// alongside any model swap or price change.
    static let inputCostPerMTok:  Double = 1.00
    static let outputCostPerMTok: Double = 5.00

    /// Observable flag for Settings UI gating ("Set" vs
    /// "Configured ✓"). Mirrors the Keychain state; reset by
    /// `setAPIKey` / `clearAPIKey`.
    private(set) var hasAPIKey: Bool

    init() {
        self.hasAPIKey = Keychain.has(Self.apiKeyAccount)
    }

    // MARK: - Key storage

    /// Writes the key to Keychain and flips `hasAPIKey`. Throws
    /// the (rare) SecItemAdd failure path so the Settings sheet
    /// can surface a banner; the call site treats success as
    /// "dismiss + show Configured ✓".
    func setAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeyError.empty }
        guard Keychain.write(Self.apiKeyAccount, value: trimmed) else {
            throw KeyError.keychainWriteFailed
        }
        hasAPIKey = true
    }

    /// Removes the key from Keychain. Settings calls this from
    /// the "Remove key" destructive button.
    func clearAPIKey() {
        Keychain.delete(Self.apiKeyAccount)
        hasAPIKey = false
    }

    /// Internal read for the network commit's eventual API call.
    /// Settings never reads the key back — Keychain stores it,
    /// the UI only knows "is configured."
    func apiKey() -> String? {
        Keychain.read(Self.apiKeyAccount)
    }

    enum KeyError: Error {
        case empty
        case keychainWriteFailed
    }

    // MARK: - Budget

    /// Read-write monthly cap in USD. Backed by UserDefaults.
    /// Default falls back to `defaultMonthlyBudgetUSD` ($2.00)
    /// on first read after install.
    var monthlyBudgetUSD: Double {
        get {
            let stored = UserDefaults.standard.object(forKey: Self.monthlyBudgetKey) as? Double
            return stored ?? Self.defaultMonthlyBudgetUSD
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.monthlyBudgetKey)
        }
    }

    // MARK: - Usage tracking

    /// Sum of `estimatedCostUSD` across `AIUsageRecord` rows
    /// dated within the current calendar month. The follow-up
    /// commit's API call gates on `isWithinBudget` before each
    /// network attempt.
    func monthToDateSpendUSD(in context: ModelContext) -> Double {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: .now) else { return 0 }
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<AIUsageRecord>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.reduce(0) { $0 + $1.estimatedCostUSD }
    }

    /// True when month-to-date spend is strictly under the
    /// monthly budget. Callers must check this before an API
    /// call — if false, abort and surface a budget-reached
    /// banner.
    func isWithinBudget(in context: ModelContext) -> Bool {
        monthToDateSpendUSD(in: context) < monthlyBudgetUSD
    }

    /// Inserts an `AIUsageRecord` for a successful API call.
    /// Cost is computed from the token counts via the per-
    /// million-token constants. Explicit `try context.save()`
    /// per the no-silent-write-failures audit rule (H6 / H12) —
    /// SwiftData autosave wouldn't make the usage durable
    /// before an app kill, and losing a $0.01 row a hundred
    /// times in a row would silently bust the cap.
    @discardableResult
    func recordUsage(
        inputTokens: Int,
        outputTokens: Int,
        in context: ModelContext
    ) throws -> AIUsageRecord {
        let cost = Self.cost(inputTokens: inputTokens, outputTokens: outputTokens)
        let record = AIUsageRecord(
            date: .now,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCostUSD: cost
        )
        context.insert(record)
        do {
            try context.save()
        } catch {
            throw UsageError.saveFailed(error)
        }
        return record
    }

    /// Pure-static cost calculator. Token counts × per-million-
    /// token rates. Exposed `static` so unit tests + Settings
    /// previews can verify without standing up the service.
    static func cost(inputTokens: Int, outputTokens: Int) -> Double {
        let inCost  = Double(inputTokens)  / 1_000_000 * inputCostPerMTok
        let outCost = Double(outputTokens) / 1_000_000 * outputCostPerMTok
        return inCost + outCost
    }

    enum UsageError: Error {
        case saveFailed(Error)
    }
}

import Foundation
import SwiftData

/// One row per successful AI API call. Drives the monthly cost
/// cap on `ClaudeService` (sum estimatedCostUSD for rows in the
/// current calendar month; abort the API call when that sum
/// exceeds `ClaudeService.monthlyBudgetUSD`).
///
/// Cost is computed at insert time from token counts × the
/// per-million-token rates published by Anthropic — see
/// `ClaudeService.cost(inputTokens:outputTokens:)` for the
/// current Haiku 4.5 prices. The stored value is the snapshot at
/// the time of the call; if Anthropic later changes pricing,
/// historical rows reflect what was actually billed.
///
/// CloudKit shape (re-verified): every property has a default,
/// no relationships, no `@Attribute(.unique)`. id is a plain UUID
/// — not a unique attribute — so an iCloud-side ingest collision
/// would dedupe at the app layer rather than at SwiftData.
@Model
final class AIUsageRecord {
    var id: UUID = UUID()
    var date: Date = Date.now
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var estimatedCostUSD: Double = 0

    init(
        id: UUID = UUID(),
        date: Date = .now,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        estimatedCostUSD: Double = 0
    ) {
        self.id = id
        self.date = date
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.estimatedCostUSD = estimatedCostUSD
    }
}

import Foundation
import SwiftData
import UIKit

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

    // MARK: - Vision call (meal-photo macro estimate)

    /// Anthropic model id used for the meal-photo macro estimate.
    /// Haiku 4.5 — cheap enough that the default $2/month budget
    /// covers ~200 photos at typical token counts.
    static let visionModel = "claude-haiku-4-5-20251001"

    /// Anthropic Messages API endpoint.
    private static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!

    /// API version header value. Anthropic pins behavior to this
    /// date; bump alongside any breaking-protocol change.
    private static let anthropicVersion = "2023-06-01"

    /// Pre-flight + network + parse for a single meal-photo
    /// estimate. Pre-flights are budget gate AND key gate — both
    /// throw without touching the network. The image is downscaled
    /// (longest edge 1024px, JPEG q=0.7) before the request so
    /// input-token cost stays low. After the response, usage tokens
    /// are recorded into `AIUsageRecord` BEFORE the JSON-parse step
    /// — the tokens were spent regardless of parse success, and
    /// losing the usage row would silently bust the cap.
    func estimateMacros(
        from imageData: Data,
        in context: ModelContext
    ) async throws -> MacroEstimate {
        // 0. Demo gate. Demo mode is entirely offline + free —
        //    no Anthropic network calls, no AIUsageRecord writes,
        //    so the Settings month-to-date spend figure never
        //    reflects synthetic usage. Surfaces as a distinct
        //    error so the camera screen can show a demo-aware
        //    message rather than the no-key prompt.
        guard !DemoMode.isEnabled else { throw ClaudeServiceError.demoModeActive }

        // 1. Key gate. No key → no call.
        guard let key = apiKey() else { throw ClaudeServiceError.noAPIKey }

        // 2. Budget gate. Strict `<` so a $0 budget blocks.
        guard isWithinBudget(in: context) else {
            throw ClaudeServiceError.budgetExceeded
        }

        // 3. Downscale + JPEG-encode. UIImage throws lazily so a
        //    nil decode means we got something that isn't a real
        //    image (camera glitch, picker race). Bail with a
        //    parse error rather than firing the network on garbage.
        guard let source = UIImage(data: imageData) else {
            throw ClaudeServiceError.couldNotParse
        }
        guard let payload = Self.downscaleJPEG(source) else {
            throw ClaudeServiceError.couldNotParse
        }

        // 4. Build the request.
        let base64 = payload.base64EncodedString()
        let body: [String: Any] = [
            "model": Self.visionModel,
            "max_tokens": 512,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64,
                            ] as [String: Any],
                        ] as [String: Any],
                        [
                            "type": "text",
                            "text": Self.visionPrompt,
                        ] as [String: Any],
                    ],
                ] as [String: Any],
            ],
        ]
        var request = URLRequest(url: Self.messagesURL)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw ClaudeServiceError.network(error)
        }

        // 5. Hit the network.
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeServiceError.network(error)
        }

        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            // Anthropic returns useful error text on non-2xx. Pass
            // through as a network error so the call site surfaces
            // a "couldn't estimate, try again" alert; user doesn't
            // benefit from raw HTTP detail.
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? "HTTP \(http.statusCode)"
            throw ClaudeServiceError.network(NSError(
                domain: "Anthropic",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: String(snippet)]
            ))
        }

        // 6. Record usage IMMEDIATELY — before parsing the
        //    content. Tokens were spent; losing the row on a
        //    parse failure would silently bust the cap. The
        //    helper short-circuits if `usage` is missing
        //    (recordUsage(0, 0) is a no-op cost-wise).
        let envelope: AnthropicResponse
        do {
            envelope = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        } catch {
            throw ClaudeServiceError.couldNotParse
        }
        do {
            try recordUsage(
                inputTokens: envelope.usage?.input_tokens ?? 0,
                outputTokens: envelope.usage?.output_tokens ?? 0,
                in: context
            )
        } catch {
            // Don't abort the estimate on a save failure — log
            // and continue. The user's photo is mid-flight; the
            // cost row dropping is a worse bug than the UX of
            // discarding their result.
            print("[ClaudeService] recordUsage failed (estimate continues): \(error)")
        }

        // 7. Parse the JSON estimate. The model is instructed to
        //    return bare JSON but may wrap it in ```json fences;
        //    strip them defensively before decoding.
        guard let assistantText = envelope.content.first(where: { $0.type == "text" })?.text else {
            throw ClaudeServiceError.couldNotParse
        }
        let cleaned = Self.stripCodeFences(assistantText)
        let estimate: MacroEstimate
        do {
            estimate = try JSONDecoder().decode(MacroEstimate.self, from: Data(cleaned.utf8))
        } catch {
            throw ClaudeServiceError.couldNotParse
        }
        return estimate
    }

    // MARK: - Vision helpers (file-private static)

    /// The prompt sent alongside the image block. Single text
    /// block per Anthropic Messages API; the model returns one
    /// content text block in response. Keep this string in lockstep
    /// with `MacroEstimate`'s CodingKeys so the round-trip stays
    /// stable. Updating one without the other breaks parsing.
    private static let visionPrompt: String = """
    You are a nutrition estimator. The image should show a meal or food item. Respond with ONLY a JSON object, no prose, no markdown fences, in exactly this shape:
    {"isFood": true/false, "name": "short label", "kcal": int, "protein": int, "carbs": int, "fat": int, "confidence": "low"/"medium"/"high"}
    If the image does not show food, return isFood false and set all numeric fields to 0. Estimate macros for the full portion visible. Grams for protein/carbs/fat, kilocalories for kcal.
    """

    /// Resizes so the longest edge is ≤ `longestEdge`, JPEG-encodes
    /// at `quality`. Skips the resize when the source is already
    /// smaller (small camera frames on older devices). UIGraphics
    /// renderer uses scale 1 so the output pixel count matches the
    /// requested size; the default Retina scale would up-sample by
    /// 2× or 3× and waste tokens.
    private static func downscaleJPEG(
        _ image: UIImage,
        longestEdge: CGFloat = 1024,
        quality: CGFloat = 0.7
    ) -> Data? {
        let size = image.size
        let scale = min(longestEdge / max(size.width, size.height), 1.0)
        let target: CGSize
        let rendered: UIImage
        if scale >= 1.0 {
            rendered = image
            target = size
        } else {
            target = CGSize(width: size.width * scale, height: size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: target, format: format)
            rendered = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
        }
        return rendered.jpegData(compressionQuality: quality)
    }

    /// Strips a ```json ... ``` or ``` ... ``` wrap if the model
    /// returned one despite the prompt. Conservative — only strips
    /// the outer fence pair when both ends match.
    private static func stripCodeFences(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            // Drop the opening fence + optional language tag through
            // the first newline.
            if let newlineIdx = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: newlineIdx)...])
            }
            if s.hasSuffix("```") {
                s = String(s.dropLast(3))
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Decoding shapes (internal-only)

    private struct AnthropicResponse: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        struct Usage: Decodable {
            let input_tokens: Int
            let output_tokens: Int
        }
        let content: [ContentBlock]
        let usage: Usage?
    }
}

/// Parsed meal-photo estimate. Confidence is a free-form string
/// from the model — "low" / "medium" / "high" per the prompt
/// contract. The result sheet surfaces "low" with a warning tint
/// so the user knows to scrutinise.
struct MacroEstimate: Decodable, Sendable {
    let isFood: Bool
    let name: String
    let kcal: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let confidence: String
}

/// Errors surfaced by `ClaudeService.estimateMacros`. Each maps to
/// a specific UI message; cases stay coarse so the call site
/// (CameraView's error branching) doesn't need to inspect inner
/// detail.
enum ClaudeServiceError: Error, LocalizedError {
    case noAPIKey
    case budgetExceeded
    case network(Error)
    case couldNotParse
    case notFood
    case demoModeActive

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Add an Anthropic API key in Settings to use AI estimates."
        case .budgetExceeded:
            return "You've reached this month's AI budget. Raise it in Settings or enter the meal manually."
        case .network(let underlying):
            return "Couldn't reach the estimator (\(underlying.localizedDescription))."
        case .couldNotParse:
            return "Couldn't estimate that photo. Try again, or enter manually."
        case .notFood:
            return "That doesn't look like food. Try another photo."
        case .demoModeActive:
            return "AI estimates are off in demo mode. Turn demo mode off in Settings or enter the meal manually."
        }
    }
}

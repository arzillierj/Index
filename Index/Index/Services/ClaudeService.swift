import Foundation

/// Single-purpose service: photo → estimated macros. No meal suggestions,
/// no other API calls. The Anthropic API key is user-provided and stored
/// in UserDefaults — Phase 7 Settings will surface a secure field for it.
struct ClaudeService {

    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: apiKeyDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyDefaultsKey) }
    }

    static var hasAPIKey: Bool { !apiKey.isEmpty }

    static let apiKeyDefaultsKey = "claude_api_key"

    /// Wire model + endpoint kept identical to v0's pattern so existing
    /// debugging muscle-memory ports over.
    private static let model = "claude-haiku-4-5-20251001"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let timeoutSeconds: TimeInterval = 30
    private static let maxTokens = 256

    /// Sends a meal photo to Claude Haiku and returns an estimated macro
    /// breakdown for the visible portion. Caller is responsible for
    /// JPEG-encoding the image before invoking — the request hardcodes
    /// `image/jpeg`.
    /// DECISION: hardcoded media type avoids a magic-byte sniff that would
    /// only ever see JPEG in practice (UIImage.jpegData is the capture path).
    static func estimateMacros(from photoData: Data) async throws -> MacroEstimate {
        let key = apiKey
        guard !key.isEmpty else { throw ClaudeError.missingAPIKey }

        let base64 = photoData.base64EncodedString()
        let prompt = """
        You are a nutrition estimator. Look at this meal photo and estimate \
        the macronutrients for the visible portion. Be conservative when uncertain.

        Return strictly JSON with this exact shape (no markdown fences, no prose):
        {
          "label": "short meal name, 2-5 words",
          "kcal": <integer>,
          "protein_g": <integer>,
          "carbs_g": <integer>,
          "fat_g": <integer>
        }
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: endpoint, timeoutInterval: timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeError.networkError(error)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw ClaudeError.invalidAPIKey }
            guard (200..<300).contains(http.statusCode) else {
                throw ClaudeError.badResponse
            }
        }

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = payload["content"] as? [[String: Any]],
              let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let raw = textBlock["text"] as? String else {
            throw ClaudeError.badResponse
        }

        // Defensively strip markdown fences — Claude sometimes wraps JSON
        // despite the explicit instruction not to.
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        struct RawEstimate: Decodable {
            let label: String
            let kcal: Double
            let protein_g: Double
            let carbs_g: Double
            let fat_g: Double
        }
        guard let jsonData = cleaned.data(using: .utf8),
              let r = try? JSONDecoder().decode(RawEstimate.self, from: jsonData) else {
            throw ClaudeError.parseError
        }

        return MacroEstimate(
            label: r.label,
            kcal: r.kcal,
            protein: r.protein_g,
            carbs: r.carbs_g,
            fat: r.fat_g
        )
    }
}

struct MacroEstimate: Sendable {
    let label: String
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

enum ClaudeError: Error {
    case missingAPIKey
    case invalidAPIKey
    case networkError(Error)
    case badResponse
    case parseError
}

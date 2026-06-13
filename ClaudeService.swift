import UIKit
import Foundation

// MARK: - Photo Input

struct AnalysisPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let pose: String

    /// Max base64 payload must stay under 5 MB (5,242,880 bytes).
    /// Base64 inflates by ~33%, so raw JPEG must be under ~3.9 MB.
    private static let maxJPEGBytes = 3_900_000

    var jpegData: Data? {
        let resized = AnalysisPhoto.downsizedIfNeeded(image)
        // Try quality 0.7 first, then step down if still too large
        for quality: CGFloat in [0.7, 0.5, 0.35, 0.2] {
            if let data = resized.jpegData(compressionQuality: quality),
               data.count <= AnalysisPhoto.maxJPEGBytes {
                return data
            }
        }
        // Last resort: lowest quality. Honor the size contract — if even this exceeds the
        // base64 payload ceiling, return nil rather than shipping an over-limit image that
        // the API would reject (the caller skips photos with nil data).
        if let data = resized.jpegData(compressionQuality: 0.1),
           data.count <= AnalysisPhoto.maxJPEGBytes {
            return data
        }
        return nil
    }

    /// Downscale so the longest edge is at most 2048px (keeps detail, cuts file size)
    private static func downsizedIfNeeded(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 2048
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }

        let scale: CGFloat
        if size.width > size.height {
            scale = maxDimension / size.width
        } else {
            scale = maxDimension / size.height
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Claude Service

class ClaudeService {
    static let shared = ClaudeService()
    private init() {}

    // MARK: - Multi-Photo Body Analysis

    func analyzeBody(photos: [AnalysisPhoto]) async throws -> BodyAnalysisResult {
        guard !photos.isEmpty else { throw ClaudeError.noPhotos }

        let poseList = photos.map { $0.pose }.joined(separator: ", ")

        let systemPrompt = """
        You are a multidisciplinary physique and health assessment panel. Your team includes:

        1. EXERCISE PHYSIOLOGIST — Evidence-based hypertrophy science (Schoenfeld, Israetel). Evaluates mechanical tension, volume landmarks, muscle development by region, and movement pattern recommendations.

        2. SPORTS DIETITIAN — Body recomposition specialist (Helms, McDonald). Evaluates body composition, nutrient timing, protein prioritization, energy flux, and metabolic efficiency.

        3. SPORTS MEDICINE PHYSICIAN — Assesses injury risk, postural deviations, muscle imbalances that predispose to injury, joint health indicators, and general health markers visible from physique.

        4. SPORT PSYCHOLOGIST — Evaluates behavioral sustainability, adherence patterns, realistic goal-setting, body image considerations, and motivation strategies.

        Client profile:
        \(Config.analysisClientProfilePrompt)

        You are reviewing \(photos.count) photo(s) from these angles: \(poseList).
        \(photos.count > 1 ? "Cross-reference all views to produce a comprehensive assessment. Note differences visible between angles." : "Assess what is visible and note limitations from having only one angle.")

        ASSESSMENT METHODOLOGY BY REGION:

        CHEST: Upper vs lower pec ratio. Clavicular head development. Thickness vs width.
        SHOULDERS: All three heads — anterior, lateral, posterior. Lateral/rear delt width contribution. Anterior dominance patterns.
        ARMS: Bicep peak vs width. Tricep long head vs lateral head. Forearm proportion.
        BACK (if visible): Lat insertion and flare. V-taper. Upper back thickness vs lat dominance.
        CORE/ABS: Rectus abdominis development vs body fat coverage. Waist-to-shoulder ratio. Oblique development.
        GLUTES (if visible): Size, shape, hamstring tie-in.
        LEGS (if visible): Quad sweep vs mass. Hamstring-to-quad balance. Calf proportion.
        POSTURE: Anterior pelvic tilt, forward head, rounded shoulders, rib flare.
        BODY COMPOSITION: Estimate body fat from visible landmarks — serratus visibility, oblique definition, ab striation, vascularity.

        RECOMMENDATION STANDARDS:
        - Workout recs must reference specific movement patterns (e.g. "incline pressing for upper chest" not "train chest more")
        - Volume recs should reference MEV/MAV ranges where relevant
        - Diet recs must be specific to this user's stated goal and lifestyle constraints — not generic
        - Include concrete daily macro targets tailored to this client
        - Identify the #1 highest-leverage change for visible transformation
        - Metabolic health notes should address the user's stated schedule and recovery constraints when relevant
        - Psychological insights should address adherence strategies realistic for this user's work/life context
        - Injury risk notes should flag any visible imbalances or postural issues that increase injury risk under heavy training loads
        - structuredTrainingIntent must translate the assessment into a machine-readable hypertrophy programming contract
        - weeklyTrainingDays in structuredTrainingIntent must stay between 4 and 6
        - Each structuredTrainingIntent priority must describe a real programming need, not generic filler
        - weeklyDayTarget, weeklyExerciseTarget, volumeBias, and directWorkBias should reflect realistic recoverable hypertrophy exposure for this client
        - preferredStyles should use only: Push, Pull, Legs, Lower, Upper, Arms
        - weeklyDayTarget and weeklyExerciseTarget should reflect realistic weekly exposure for hypertrophy, not arbitrary numbers

        Report your complete assessment by calling the emit_body_analysis tool. Never respond with
        free text. The tool input must match this shape exactly:
        {
          "overallAssessment": "3-4 sentence physique summary with estimated body fat % range, primary visual bottleneck, and overall development rating",
          "regionBreakdown": [
            {
              "region": "Region name",
              "assessment": "Specific technical observation using correct anatomy",
              "priority": "High | Medium | Low"
            }
          ],
          "topLeverageChange": "The single highest-impact change for visible transformation",
          "priorityMuscles": ["muscle1", "muscle2", "muscle3"],
          "workoutRecommendations": [
            "Specific recommendation with movement patterns, sets/rep ranges, and rationale"
          ],
          "dietRecommendations": [
            "Specific nutrition recommendation accounting for this user's stated schedule and recovery constraints"
          ],
          "macroTargets": {
            "calories": 2300,
            "proteinG": 210,
            "carbsG": 220,
            "fatG": 70
          },
          "posturalNotes": "Specific postural deviations and how they affect the assessment",
          "estimatedBodyFat": "e.g. 16-18%",
          "metabolicHealthNotes": "Metabolic considerations and strategies tailored to this user's schedule and recovery constraints",
          "psychologicalInsights": "Adherence strategies, realistic goal-setting, sustainability notes",
          "injuryRiskNotes": "Visible imbalances or patterns that increase injury risk and preventive recommendations",
          "structuredTrainingIntent": {
            "splitRecommendation": "Short label for the recommended split structure",
            "weeklyTrainingDays": 5,
            "priorities": [
              {
                "area": "Upper Chest",
                "priorityLevel": "High",
                "rationale": "Why this area deserves extra programming attention",
                "weeklyDayTarget": 2,
                "weeklyExerciseTarget": 3,
                "preferredStyles": ["Push", "Upper"],
                "preferredMovementPatterns": ["incline press", "low incline fly"],
                "volumeBias": "High",
                "directWorkBias": "Direct emphasis"
              }
            ],
            "programmingNotes": [
              "1-3 notes describing split logic, fatigue management, and recovery constraints"
            ]
          }
        }
        """

        // Build content array with all photos + text prompt
        var contentArray: [[String: Any]] = []

        for (index, photo) in photos.enumerated() {
            guard let jpegData = photo.jpegData else { continue }
            let base64 = jpegData.base64EncodedString()

            contentArray.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64
                ]
            ])
            contentArray.append([
                "type": "text",
                "text": "Photo \(index + 1): \(photo.pose) view"
            ])
        }

        contentArray.append([
            "type": "text",
            "text": "Analyze \(photos.count > 1 ? "all \(photos.count) photos together" : "this photo") and report the assessment by calling the emit_body_analysis tool."
        ])

        let tool: [String: Any] = [
            "name": ClaudeService.analysisToolName,
            "description": "Emit the full physique assessment in the required structured shape. Always call this tool; never respond with free text.",
            "input_schema": bodyAnalysisToolSchema()
        ]

        let requestBody: [String: Any] = [
            "model": Config.claudeModel,
            "max_tokens": 4096,
            "system": systemPrompt,
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": ClaudeService.analysisToolName],
            "messages": [
                [
                    "role": "user",
                    "content": contentArray
                ]
            ]
        ]

        return try await makeAnalysisRequest(body: requestBody)
    }

    // MARK: - Single-Photo (backward compat convenience)

    func analyzeBody(imageData: Data, pose: String) async throws -> BodyAnalysisResult {
        guard let image = UIImage(data: imageData) else { throw ClaudeError.invalidImage }
        return try await analyzeBody(photos: [AnalysisPhoto(image: image, pose: pose)])
    }

    // MARK: - Network Request

    static let analysisToolName = "emit_body_analysis"

    private func makeAnalysisRequest(body: [String: Any]) async throws -> BodyAnalysisResult {
        // The model is forced into a tool_use response, so the returned string is already the
        // tool's `input` JSON object — no preamble, no markdown fences, no hand-rolled extraction.
        let jsonString = try await AnthropicClient.shared.sendStructuredRequest(
            body: body,
            toolName: ClaudeService.analysisToolName,
            timeout: 120
        )

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ClaudeError.parseError("Response was not valid text")
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(BodyAnalysisResult.self, from: jsonData)
        } catch let decodingError {
            throw ClaudeError.parseError("Could not decode body analysis: \(decodingError)")
        }
    }

    // MARK: - Body Analysis Tool Schema

    private func numberProp(_ description: String? = nil) -> [String: Any] {
        var prop: [String: Any] = ["type": "number"]
        if let description {
            prop["description"] = description
        }
        return prop
    }

    private func arrayProp(of items: [String: Any], description: String? = nil) -> [String: Any] {
        var prop: [String: Any] = ["type": "array", "items": items]
        if let description {
            prop["description"] = description
        }
        return prop
    }

    func bodyAnalysisToolSchema() -> [String: Any] {
        let regionItem: [String: Any] = [
            "type": "object",
            "properties": [
                "region": stringProp("Region name"),
                "assessment": stringProp("Specific technical observation using correct anatomy"),
                "priority": stringProp("High | Medium | Low")
            ],
            "required": ["region", "assessment", "priority"],
            "additionalProperties": false
        ]

        let macroTargets: [String: Any] = [
            "type": "object",
            "properties": [
                "calories": integerProp(minimum: 1000, maximum: 6000),
                "proteinG": numberProp(),
                "carbsG": numberProp(),
                "fatG": numberProp()
            ],
            "required": ["calories", "proteinG", "carbsG", "fatG"],
            "additionalProperties": false
        ]

        let priorityItem: [String: Any] = [
            "type": "object",
            "properties": [
                "area": stringProp(),
                "priorityLevel": stringProp("High | Medium | Low"),
                "rationale": stringProp("Why this area deserves extra programming attention"),
                "weeklyDayTarget": integerProp(minimum: 0, maximum: 7),
                "weeklyExerciseTarget": integerProp(minimum: 0, maximum: 12),
                "preferredStyles": arrayProp(of: stringProp(), description: "Use only: Push, Pull, Legs, Lower, Upper, Arms"),
                "preferredMovementPatterns": arrayProp(of: stringProp()),
                "volumeBias": stringProp(),
                "directWorkBias": stringProp()
            ],
            "required": [
                "area", "priorityLevel", "rationale", "weeklyDayTarget", "weeklyExerciseTarget",
                "preferredStyles", "preferredMovementPatterns", "volumeBias", "directWorkBias"
            ],
            "additionalProperties": false
        ]

        let structuredIntent: [String: Any] = [
            "type": "object",
            "properties": [
                "splitRecommendation": stringProp("Short label for the recommended split structure"),
                "weeklyTrainingDays": integerProp(minimum: 4, maximum: 6),
                "priorities": arrayProp(of: priorityItem),
                "programmingNotes": arrayProp(of: stringProp(), description: "1-3 notes describing split logic, fatigue management, and recovery constraints")
            ],
            "required": ["splitRecommendation", "weeklyTrainingDays", "priorities", "programmingNotes"],
            "additionalProperties": false
        ]

        let properties: [String: Any] = [
            "overallAssessment": stringProp("3-4 sentence physique summary with estimated body fat % range, primary visual bottleneck, and overall development rating"),
            "regionBreakdown": arrayProp(of: regionItem),
            "topLeverageChange": stringProp("The single highest-impact change for visible transformation"),
            "priorityMuscles": arrayProp(of: stringProp()),
            "workoutRecommendations": arrayProp(of: stringProp(), description: "Specific recommendations with movement patterns, sets/rep ranges, and rationale"),
            "dietRecommendations": arrayProp(of: stringProp(), description: "Specific nutrition recommendations accounting for the user's stated schedule and recovery constraints"),
            "macroTargets": macroTargets,
            "posturalNotes": stringProp("Specific postural deviations and how they affect the assessment"),
            "estimatedBodyFat": stringProp("e.g. 16-18%"),
            "metabolicHealthNotes": stringProp("Metabolic considerations and strategies tailored to this user's schedule and recovery constraints"),
            "psychologicalInsights": stringProp("Adherence strategies, realistic goal-setting, sustainability notes"),
            "injuryRiskNotes": stringProp("Visible imbalances or patterns that increase injury risk and preventive recommendations"),
            "structuredTrainingIntent": structuredIntent
        ]

        let required: [String] = [
            "overallAssessment", "regionBreakdown", "topLeverageChange", "priorityMuscles",
            "workoutRecommendations", "dietRecommendations", "macroTargets", "posturalNotes",
            "estimatedBodyFat", "metabolicHealthNotes", "psychologicalInsights",
            "injuryRiskNotes", "structuredTrainingIntent"
        ]

        return [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false
        ]
    }

    // MARK: - Robust JSON Extraction

    /// Extracts the first complete JSON object from a string, handling preamble, markdown fences, and trailing text.
    static func extractJSON(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the first '{' and match to its closing '}'
        guard let startIndex = cleaned.firstIndex(of: "{") else {
            return cleaned
        }

        var depth = 0
        var endIndex = cleaned.endIndex
        var inString = false
        // Track the run of consecutive backslashes immediately preceding the current
        // character. A quote is only an escaped quote when that run is odd; `\\"` is a
        // literal backslash followed by an unescaped quote (even run), which the previous
        // `prevChar != "\\"` check mishandled and could break brace matching.
        var pendingBackslashes = 0

        for i in cleaned[startIndex...].indices {
            let ch = cleaned[i]
            if ch == "\"" {
                if pendingBackslashes % 2 == 0 {
                    inString.toggle()
                }
            } else if !inString {
                if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        endIndex = cleaned.index(after: i)
                        break
                    }
                }
            }

            pendingBackslashes = (ch == "\\") ? pendingBackslashes + 1 : 0
        }

        return String(cleaned[startIndex..<endIndex])
    }
}

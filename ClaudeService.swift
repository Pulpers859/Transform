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
        // Last resort: lowest quality, still subject to the hard API payload cap.
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

        // Encode every photo up front. A silently dropped image would leave the
        // prompt claiming N photos while fewer are attached, and the model would
        // fabricate an assessment for a view it never saw — fail loudly instead.
        var encodedPhotos: [(pose: String, base64: String)] = []
        for photo in photos {
            guard let jpegData = photo.jpegData else {
                throw ClaudeError.invalidImage
            }
            encodedPhotos.append((photo.pose, jpegData.base64EncodedString()))
        }

        let poseList = encodedPhotos.map { $0.pose }.joined(separator: ", ")

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

        You MUST respond with ONLY valid JSON. No preamble, no markdown, no text outside JSON.

        JSON schema:
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

        for (index, encoded) in encodedPhotos.enumerated() {
            contentArray.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": encoded.base64
                ]
            ])
            contentArray.append([
                "type": "text",
                "text": "Photo \(index + 1): \(encoded.pose) view"
            ])
        }

        contentArray.append([
            "type": "text",
            "text": "Analyze \(encodedPhotos.count > 1 ? "all \(encodedPhotos.count) photos together" : "this photo"). Respond with ONLY the JSON object specified in your instructions. Do not include any text before or after the JSON."
        ])

        // Note: no assistant prefill — current Claude models reject prefilled
        // assistant turns with a 400. extractJSON handles any stray preamble.
        let requestBody: [String: Any] = [
            "model": Config.claudeModel,
            "max_tokens": 8192,
            "system": systemPrompt,
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

    private func makeAnalysisRequest(body: [String: Any]) async throws -> BodyAnalysisResult {
        let text = try await AnthropicClient.shared.sendRequest(body: body, timeout: 120)

        // Extract JSON object from response
        let jsonString = ClaudeService.extractJSON(from: text)

        guard let jsonData = jsonString.data(using: .utf8) else {
            print("[ClaudeService] Could not convert cleaned text to Data")
            print("[ClaudeService] Raw response (first 500 chars): \(String(text.prefix(500)))")
            throw ClaudeError.parseError("Response was not valid text")
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(BodyAnalysisResult.self, from: jsonData)
        } catch let decodingError {
            print("[ClaudeService] JSON decode failed: \(decodingError)")
            print("[ClaudeService] Extracted JSON (first 500 chars): \(String(jsonString.prefix(500)))")
            throw ClaudeError.parseError("\(decodingError)")
        }
    }

    // MARK: - Robust JSON Extraction

    /// Extracts the first complete JSON object from a string, handling preamble, markdown fences, and trailing text.
    /// Brace matching starts at the first `{`, so fences and preamble fall away naturally —
    /// no global character stripping that could corrupt backticks inside JSON string values.
    static func extractJSON(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the first '{' and match to its closing '}'
        guard let startIndex = cleaned.firstIndex(of: "{") else {
            return cleaned
        }

        var depth = 0
        var endIndex = cleaned.endIndex
        var inString = false
        var escaped = false

        for i in cleaned[startIndex...].indices {
            let ch = cleaned[i]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        endIndex = cleaned.index(after: i)
                        break
                    }
                }
            }
        }

        return String(cleaned[startIndex..<endIndex])
    }
}

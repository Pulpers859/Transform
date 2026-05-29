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
        // Last resort: lowest quality
        return resized.jpegData(compressionQuality: 0.1)
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

    func analyzeBody(
        photos: [AnalysisPhoto],
        inputContext suppliedInputContext: AnalysisInputContext? = nil
    ) async throws -> BodyAnalysisResult {
        guard !photos.isEmpty else { throw ClaudeError.noPhotos }

        let poseList = photos.map { $0.pose }.joined(separator: ", ")
        let inputContext = suppliedInputContext ?? Config.analysisInputContext

        let systemPrompt = """
        You are an AI photo-based physique analysis system. Your job is to produce a useful,
        honest assessment organized into four coaching domains:

        1. TRAINING — visible muscular development, physique bottlenecks, hypertrophy priorities,
           and movement-pattern implications
        2. NUTRITION — body-composition interpretation and nutrition priorities consistent with the
           user's goal and context
        3. RECOVERY & RISK — cautious, non-diagnostic observations about visible posture/presentation
           patterns, likely recovery constraints, and programming risk-management considerations
        4. ADHERENCE — realistic coaching considerations about consistency and plan design that are
           supported by the client profile or stated context, not guessed from appearance alone

        User context for this analysis:
        \(inputContext.promptDescription)

        You are reviewing \(photos.count) photo(s) from these angles: \(poseList).
        \(photos.count > 1 ? "Cross-reference all views to produce a comprehensive assessment. Note differences visible between angles." : "Assess what is visible and note limitations from having only one angle.")

        HARD SCOPE LIMITS:
        - This is a photo-based physique analysis, not a medical evaluation.
        - Do NOT claim to diagnose injuries, metabolic disease, posture disorders, or psychological states from photos.
        - Use cautious wording such as "may suggest", "can support", "visually appears", or
          "photo-based inference is limited" whenever certainty is low.
        - Training observations can be relatively direct. Recovery/risk and adherence observations
          must be more conservative.
        - If a conclusion would require training logs, symptoms, labs, or conversation history,
          say that directly in analysisLimitations instead of pretending certainty.

        ASSESSMENT METHODOLOGY BY REGION:

        CHEST: Upper vs lower pec ratio. Clavicular head development. Thickness vs width.
        SHOULDERS: All three heads — anterior, lateral, posterior. Lateral/rear delt width contribution. Anterior dominance patterns.
        ARMS: Bicep peak vs width. Tricep long head vs lateral head. Forearm proportion.
        BACK (if visible): Lat insertion and flare. V-taper. Upper back thickness vs lat dominance.
        CORE/ABS: Rectus abdominis development vs body fat coverage. Waist-to-shoulder ratio. Oblique development.
        GLUTES (if visible): Size, shape, hamstring tie-in.
        LEGS (if visible): Quad sweep vs mass. Hamstring-to-quad balance. Calf proportion.
        POSTURE/PRESENTATION: ribcage-pelvis relationship, shoulder position, stance asymmetry,
        and other visible patterns. Treat these as coaching observations, not diagnoses.
        BODY COMPOSITION: Estimate body fat from visible landmarks — serratus visibility, oblique definition, ab striation, vascularity.

        RECOMMENDATION STANDARDS:
        - Workout recs must reference specific movement patterns (e.g. "incline pressing for upper chest" not "train chest more")
        - Volume recs should reference MEV/MAV ranges where relevant
        - Diet recs must be specific to this user's stated goal and lifestyle constraints — not generic
        - Include concrete daily macro targets tailored to this client
        - Identify the #1 highest-leverage change for visible transformation
        - Metabolic health notes should stay conservative and focus on practical recovery/energy-management implications, not disease claims
        - Psychological/adherence insights should address realistic plan design and consistency strategies grounded in the user's stated context
        - Injury/risk notes should flag visible patterns that may justify more careful exercise selection or setup cues, without acting like a diagnosis
        - structuredTrainingIntent must translate the assessment into a machine-readable hypertrophy programming contract
        - weeklyTrainingDays in structuredTrainingIntent must stay between 4 and 6
        - Each structuredTrainingIntent priority must describe a real programming need, not generic filler
        - weeklyDayTarget, weeklyExerciseTarget, volumeBias, and directWorkBias should reflect realistic recoverable hypertrophy exposure for this client
        - preferredStyles should use only: Push, Pull, Legs, Lower, Upper, Arms
        - weeklyDayTarget and weeklyExerciseTarget should reflect realistic weekly exposure for hypertrophy, not arbitrary numbers
        - analysisLimitations must explicitly state what this photo-only assessment can and cannot support confidently

        You MUST respond with ONLY valid JSON. No preamble, no markdown, no text outside JSON.

        JSON schema:
        {
          "overallAssessment": "3-4 sentence physique summary with estimated body fat % range, primary visual bottleneck, and overall development rating",
          "trainingAssessment": "1-3 sentences on the most defensible training implications from visible physique patterns",
          "nutritionAssessment": "1-3 sentences on body-composition and nutrition implications consistent with the client's goal/context",
          "recoveryRiskAssessment": "1-3 cautious sentences on visible risk-management/recovery considerations; non-diagnostic",
          "adherenceAssessment": "1-3 sentences on realistic consistency/planning considerations grounded in stated context, not appearance alone",
          "analysisLimitations": "2-4 sentences on what this photo-based analysis cannot assess confidently without more data",
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
          "posturalNotes": "Visible presentation/posture observations and how they may affect training setup; non-diagnostic wording",
          "estimatedBodyFat": "e.g. 16-18%",
          "metabolicHealthNotes": "Conservative recovery/energy-management considerations tailored to this user's schedule and recovery constraints",
          "psychologicalInsights": "Adherence strategies, realistic goal-setting, and sustainability notes grounded in stated context",
          "injuryRiskNotes": "Visible imbalances or patterns that may justify more careful exercise selection or setup cues; non-diagnostic wording",
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
            "text": "Analyze \(photos.count > 1 ? "all \(photos.count) photos together" : "this photo"). Respond with ONLY the JSON object specified in your instructions. Do not include any text before or after the JSON. Start your response with {"
        ])

        let requestBody: [String: Any] = [
            "model": Config.claudeModel,
            "max_tokens": 4096,
            "cache_control": ["type": "ephemeral"],
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": contentArray
                ],
                [
                    "role": "assistant",
                    "content": "{"
                ]
            ]
        ]

        let decodedResult = try await makeAnalysisRequest(body: requestBody)
        return decodedResult.withInputContext(inputContext)
    }

    // MARK: - Single-Photo (backward compat convenience)

    func analyzeBody(
        imageData: Data,
        pose: String,
        inputContext: AnalysisInputContext? = nil
    ) async throws -> BodyAnalysisResult {
        guard let image = UIImage(data: imageData) else { throw ClaudeError.invalidImage }
        return try await analyzeBody(
            photos: [AnalysisPhoto(image: image, pose: pose)],
            inputContext: inputContext
        )
    }

    // MARK: - Network Request

    private func makeAnalysisRequest(body: [String: Any]) async throws -> BodyAnalysisResult {
        let text = try await AnthropicClient.shared.sendRequest(body: body, timeout: 120)

        // Prepend "{" since we used assistant prefill starting with "{"
        let fullText = "{" + text

        // Extract JSON object from response
        let jsonString = ClaudeService.extractJSON(from: fullText)

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
        var prevChar: Character = " "

        for i in cleaned[startIndex...].indices {
            let ch = cleaned[i]
            if ch == "\"" && prevChar != "\\" {
                inString.toggle()
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
            prevChar = ch
        }

        return String(cleaned[startIndex..<endIndex])
    }
}

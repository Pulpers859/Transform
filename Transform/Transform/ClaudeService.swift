#if canImport(UIKit)
import UIKit
#endif
import Foundation

// MARK: - Photo Input

// UIKit-only: the photo/body-analysis path depends on UIImage. Guarded so the
// generator core compiles on macOS (headless test harness). Inert on iOS/device
// builds where canImport(UIKit) is true — no behavior change.
#if canImport(UIKit)
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
#endif

// MARK: - Claude Service

class ClaudeService {
    static let shared = ClaudeService()
    private init() {}

    // MARK: - Multi-Photo Body Analysis

    // UIKit-only body-analysis entry points (consume AnalysisPhoto / UIImage). Guarded
    // so the generator core is buildable headlessly on macOS; active on device.
    #if canImport(UIKit)
    func analyzeBody(
        photos: [AnalysisPhoto],
        inputContext suppliedInputContext: AnalysisInputContext? = nil,
        priorAnalysis: BodyAnalysisResult? = nil
    ) async throws -> BodyAnalysisResult {
        guard !photos.isEmpty else { throw ClaudeError.noPhotos }

        let inputContext = suppliedInputContext ?? Config.analysisInputContext

        // Encode every photo FIRST, then describe coverage from the encoded set only.
        // A photo that fails JPEG conversion used to be silently skipped from the request
        // while the prompt still claimed that angle (count, pose list, quality caveats
        // were built from the requested photos) — so the model could "assess" an angle it
        // never actually received. Deriving everything below from encodedPhotos keeps the
        // prompt honest about what the model can see.
        let encodedPhotos: [(pose: String, base64: String)] = photos.compactMap { photo in
            guard let data = photo.jpegData else { return nil }
            return (pose: photo.pose, base64: data.base64EncodedString())
        }
        guard !encodedPhotos.isEmpty else { throw ClaudeError.invalidImage }

        let poseList = encodedPhotos.map(\.pose).joined(separator: ", ")
        let encodedCount = encodedPhotos.count

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

        You are reviewing \(encodedCount) photo(s) from these angles: \(poseList).
        \(encodedCount > 1 ? "Cross-reference all views to produce a comprehensive assessment. Note differences visible between angles." : "Assess what is visible and note limitations from having only one angle.")
        \(ClaudeService.photoQualityContext(poses: encodedPhotos.map(\.pose)))
        \(ClaudeService.priorAnalysisContext(priorAnalysis))

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
        - macroTargets must include a macroRationale explaining which inputs controlled the target (weight trend, goal rate, recovery constraints, adherence level, training demand, shift-work schedule). If the data is insufficient to set confident targets, say so.
        - macroTargets must be arithmetically self-consistent: proteinG×4 + carbsG×4 + fatG×9 must land within ~5% of the calories value. Anchor calories to the client's logged bodyweight, weekly weight trend, and stated goal rate — not to the visual body-fat estimate alone.
        - Reconcile your visual impressions against the objective data provided (logged weekly bodyweight trend, circumference-measurement changes, and logged performance). Where the photos suggest a change the logged trend or measurements contradict, say so explicitly rather than asserting the visual read as fact.
        - Identify the #1 highest-leverage change for visible transformation
        - Metabolic health notes should stay conservative and focus on practical recovery/energy-management implications, not disease claims
        - Psychological/adherence insights should address realistic plan design and consistency strategies grounded in the user's stated context
        - Injury/risk notes should flag visible patterns that may justify more careful exercise selection or setup cues, without acting like a diagnosis
        - structuredTrainingIntent must translate the assessment into a machine-readable hypertrophy programming contract
        - priorityMuscles must name the same areas emphasized in structuredTrainingIntent.priorities, so the physique summary and the programming contract agree rather than diverge
        - weeklyTrainingDays in structuredTrainingIntent must stay between 4 and 6
        - Each structuredTrainingIntent priority must describe a real programming need, not generic filler
        - weeklyDayTarget, weeklyExerciseTarget, volumeBias, and directWorkBias should reflect realistic recoverable hypertrophy exposure for this client
        - preferredStyles should use only: Push, Pull, Legs, Lower, Upper, Arms
        - weeklyDayTarget and weeklyExerciseTarget should reflect realistic weekly exposure for hypertrophy, not arbitrary numbers
        - For any single priority, weeklyDayTarget must not exceed 3 and weeklyExerciseTarget must not exceed 5, even for a top-priority lagging area — spreading beyond that is not recoverable
        - analysisLimitations must explicitly state what this photo-only assessment can and cannot support confidently

        CONFIDENCE BY DOMAIN:
        Each domain assessment has different inherent confidence from photo-based analysis.
        State your confidence explicitly within each assessment field:
        - trainingAssessment: state confidence (typically medium-high for visible musculature)
        - nutritionAssessment: state confidence (typically medium — body composition is visible but intake is not)
        - recoveryRiskAssessment: state confidence (typically low-medium — posture/presentation can suggest but not confirm)
        - adherenceAssessment: state confidence (typically low — adherence cannot be assessed from photos; state what context informed your observations)
        - estimatedBodyFat: state confidence (typically medium — visual landmarks are useful but not validated against criterion methods like DXA)
        Use phrasing like "Confidence: medium-high based on clear multi-angle visibility" or "Confidence: low — this inference requires training logs to confirm."

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
            "calories": 2350,
            "proteinG": 210,
            "carbsG": 220,
            "fatG": 70,
            "macroRationale": "1-2 sentences explaining which inputs controlled these targets (weight trend, goal rate, recovery, adherence, training demand)"
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

        // Build content array from the already-encoded photos + text prompt. The empty
        // guard above guarantees at least one image, so no per-item skip is needed here.
        var contentArray: [[String: Any]] = []

        for (index, photo) in encodedPhotos.enumerated() {
            contentArray.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": photo.base64
                ]
            ])
            contentArray.append([
                "type": "text",
                "text": "Photo \(index + 1): \(photo.pose) view"
            ])
        }

        contentArray.append([
            "type": "text",
            "text": "Analyze \(encodedCount > 1 ? "all \(encodedCount) photos together" : "this photo"). Respond with ONLY the JSON object specified in your instructions. Do not include any text before or after the JSON. Start your response with {"
        ])

        let requestBody: [String: Any] = [
            "model": Config.claudeModel,
            // Headroom so a rich multi-region assessment + prior-analysis comparison
            // doesn't get truncated mid-JSON (which surfaces to the user as a hard
            // parse failure after they've already shot and uploaded their photos).
            "max_tokens": 16384,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": contentArray
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
    #endif

    // MARK: - Network Request

    private func makeAnalysisRequest(body: [String: Any]) async throws -> BodyAnalysisResult {
        // A single malformed or truncated completion used to be terminal: the user
        // lost the whole run after shooting and uploading photos. The photos and
        // context are identical across attempts, so a fresh completion often parses.
        // Re-request ONLY on a parse/truncation failure; auth, image, and
        // cancellation errors are not retryable and propagate immediately. Bounded
        // to 2 attempts so a genuinely doomed prompt can't burn credits in a loop.
        let maxAttempts = 2
        var lastParseError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await attemptAnalysisRequest(body: body, attempt: attempt, of: maxAttempts)
            } catch let error as ClaudeError {
                if case .parseError = error {
                    lastParseError = error
                    if attempt < maxAttempts {
                        print("[ClaudeService] Body analysis parse failure on attempt \(attempt) of \(maxAttempts) — re-requesting.")
                        continue
                    }
                    // Final attempt still failed to parse. Surface a human message — the
                    // raw Swift DecodingError detail is already logged in
                    // attemptAnalysisRequest and would only confuse the user in an alert.
                    throw ClaudeError.parseError("The analysis response couldn't be read after \(maxAttempts) attempts. Please run the analysis again.")
                }
                throw error
            }
        }

        throw lastParseError ?? ClaudeError.parseError("The analysis response couldn't be read after \(maxAttempts) attempts. Please run the analysis again.")
    }

    private func attemptAnalysisRequest(
        body: [String: Any],
        attempt: Int,
        of maxAttempts: Int
    ) async throws -> BodyAnalysisResult {
        let text = try await AnthropicClient.shared.sendRequest(body: body, timeout: 120)

        // Extract JSON object from response
        let jsonString = ClaudeService.extractJSON(from: text)

        guard let jsonData = jsonString.data(using: .utf8) else {
            print("[ClaudeService] Could not convert cleaned text to Data (attempt \(attempt)/\(maxAttempts))")
            print("[ClaudeService] Raw response (first 500 chars): \(String(text.prefix(500)))")
            throw ClaudeError.parseError("Response was not valid text")
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(BodyAnalysisResult.self, from: jsonData)
        } catch let decodingError {
            print("[ClaudeService] JSON decode failed (attempt \(attempt)/\(maxAttempts)): \(decodingError)")
            print("[ClaudeService] Extracted JSON (first 500 chars): \(String(jsonString.prefix(500)))")
            throw ClaudeError.parseError("\(decodingError)")
        }
    }

    // MARK: - Robust JSON Extraction

    /// Extracts the first complete JSON object from a string, handling preamble, markdown fences, and trailing text.
    nonisolated static func extractJSON(from text: String) -> String {
        // Don't blindly strip markdown fences with replacingOccurrences — that can
        // corrupt a "```" that legitimately appears inside a JSON string value.
        // Brace-matching from the first '{' naturally skips fences and preamble.
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

    // MARK: - Photo Quality Context

    static func photoQualityContext(poses: [String]) -> String {
        let allPoses = Set(["Front", "Back", "Side (Left)", "Side (Right)"])
        let provided = Set(poses)
        let missing = allPoses.subtracting(provided)

        guard !missing.isEmpty else {
            return "Photo coverage: all four standard angles provided. Full assessment confidence is available."
        }

        var limitations: [String] = []
        if missing.contains("Back") {
            limitations.append("back development, lat width, rear delt, and posterior posture")
        }
        if missing.contains("Front") {
            limitations.append("anterior development, chest detail, and frontal body composition")
        }
        if missing.contains("Side (Left)") || missing.contains("Side (Right)") {
            let missingSides = missing.filter { $0.hasPrefix("Side") }
            if missingSides.count == 2 {
                limitations.append("lateral proportions, arm thickness, and side-profile posture")
            } else {
                limitations.append("one side profile — asymmetry assessment is limited")
            }
        }

        let limitationText = limitations.joined(separator: "; ")
        return "Photo coverage: \(poses.count) of 4 angles. Missing: \(missing.sorted().joined(separator: ", ")). Reduce confidence for: \(limitationText). State these limitations in analysisLimitations."
    }

    // MARK: - Prior Analysis Comparison Context

    static func priorAnalysisContext(_ prior: BodyAnalysisResult?) -> String {
        guard let prior else { return "" }

        var lines: [String] = [
            "",
            "PRIOR ANALYSIS COMPARISON:",
            "The user has a previous body analysis on file. Compare your current assessment against it and note changes — improvements, regressions, or areas that appear unchanged. Be specific about what looks different.",
            "Previous overall assessment: \(prior.overallAssessment)",
            "Previous estimated body fat: \(prior.estimatedBodyFat)",
            "Previous top leverage change: \(prior.topLeverageChange)",
            "Previous priority muscles: \(prior.priorityMuscles.joined(separator: ", "))"
        ]

        if !prior.regionBreakdown.isEmpty {
            let regionSummary = prior.regionBreakdown.map { "\($0.region) [\($0.priority)]" }.joined(separator: ", ")
            lines.append("Previous region priorities: \(regionSummary)")
        }

        if let macros = prior.macroTargets {
            lines.append("Previous macro targets: \(macros.calories) kcal, \(Int(macros.proteinG))g protein, \(Int(macros.carbsG))g carbs, \(Int(macros.fatG))g fat")
        }

        lines.append("In your overallAssessment, explicitly address what has changed since the prior analysis — visually improved areas, areas that still need attention, and any new observations. Do not just repeat the prior assessment.")

        return lines.joined(separator: "\n")
    }
}

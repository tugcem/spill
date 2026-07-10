import Foundation
import FoundationModels

// Protocol with narrator.rb: stdin carries one fact block per repo, joined
// by ASCII Record Separator (\u{1E}); stdout returns one summary per block —
// same order, same count, same separator. A block that fails or is refused
// comes back empty so the others still land. Exit 2 = model unavailable.
let model = SystemLanguageModel.default
guard case .available = model.availability else {
    FileHandle.standardError.write("unavailable\n".data(using: .utf8)!)
    exit(2)
}
let input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
let blocks = input.components(separatedBy: "\u{1E}")
let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 70)
var summaries: [String] = []
for block in blocks {
    let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        summaries.append("")
        continue
    }
    // A fresh session per repo keeps one repo's work from bleeding into
    // another repo's summary.
    let session = LanguageModelSession(instructions: """
    You write standup updates. Reply with one short first-person sentence (two \
    at most) that compresses the developer's listed activity. Items under \
    FINISHED are done; items under IN PROGRESS are still open. Only restate \
    what is listed — never invent anything, never repeat the list itself, and \
    never describe unmerged work as merged. Be concrete; no vague phrases like \
    "made improvements". No preamble, no repository name, no bullets.
    """)
    // The task lives in the prompt, not just the instructions: without it the
    // small model sometimes continues the fact list instead of summarizing it.
    let prompt = "Summarize this activity into one first-person standup sentence:\n\n" + trimmed
    do {
        let response = try await session.respond(to: prompt, options: options)
        summaries.append(response.content
            .replacingOccurrences(of: "\u{1E}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines))
    } catch {
        summaries.append("")
    }
}
print(summaries.joined(separator: "\u{1E}"))

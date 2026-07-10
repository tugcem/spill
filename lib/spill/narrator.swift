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
let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 120)
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
    You summarize a developer's activity as a standup update: at most three short \
    first-person sentences of flowing prose. Never a list, never dashes, never \
    quotation marks, and never any introduction — start directly with the first \
    sentence of the update. Items under FINISHED are done work: past tense. Items \
    under IN PROGRESS are still open: present tense. Only restate what is listed — \
    never invent anything, never describe unmerged work as merged. Be concrete; \
    no vague phrases like "made improvements". No repository name.
    """)
    // The task lives in the prompt, not just the instructions, and "Summarize"
    // is the load-bearing verb: without both, the small model sometimes
    // continues or echoes the fact list instead of summarizing it.
    let prompt = "Summarize this activity into a first-person standup update of at most three sentences:\n\n" + trimmed
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

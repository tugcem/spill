import Foundation
import FoundationModels

let model = SystemLanguageModel.default
guard case .available = model.availability else {
    FileHandle.standardError.write("unavailable\n".data(using: .utf8)!)
    exit(2)
}
let input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
let session = LanguageModelSession(instructions: """
You turn a developer's standup report into a first-person spoken summary. \
Write 2-4 plain sentences: first what was accomplished, then what is in progress. \
Mention repo names naturally. No markdown, no bullet points, no preamble, no questions.
""")
let response = try await session.respond(to: input)
print(response.content)

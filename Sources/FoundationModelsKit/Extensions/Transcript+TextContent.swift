import Foundation
import FoundationModels

public extension Sequence where Element == Transcript.Segment {
    func joinedTextContent(separator: String = " ") -> String? {
        let text = compactMap { segment in
            if case .text(let textSegment) = segment {
                return textSegment.content
            }
            return nil
        }
        .joined(separator: separator)

        return text.isEmpty ? nil : text
    }

    func textContentJoined(separator: String = " ") -> String? {
        joinedTextContent(separator: separator)
    }
}

public extension Transcript.Entry {
    func textContentJoined(separator: String = " ") -> String? {
        switch self {
        case .prompt(let prompt):
            return prompt.segments.joinedTextContent(separator: separator)
        case .response(let response):
            return response.segments.joinedTextContent(separator: separator)
        case .toolOutput(let toolOutput):
            return toolOutput.segments.joinedTextContent(separator: separator)
        #if compiler(>=6.4)
        case .reasoning(let reasoning):
            return reasoning.segments.joinedTextContent(separator: separator)
        #endif
        default:
            return nil
        }
    }
}

public extension Transcript {
    func latestResponseText(after entryCount: Int) -> String {
        for entry in dropFirst(entryCount).reversed() {
            switch entry {
            case .response:
                return entry.textContentJoined() ?? ""
            case .prompt:
                return ""
            default:
                continue
            }
        }
        return ""
    }

    func latestNonEmptyResponseText(startingAt startIndex: Index) -> String? {
        guard indices.contains(startIndex) || startIndex == endIndex else {
            return nil
        }

        for entry in self[startIndex...].reversed() {
            guard case .response = entry else { continue }
            guard let text = entry.textContentJoined()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else {
                continue
            }
            return text
        }
        return nil
    }
}

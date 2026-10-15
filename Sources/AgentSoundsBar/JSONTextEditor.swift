import Foundation

/// Minimal tree for rendering JSON we insert, using the host file's indentation.
indirect enum JNode {
    case string(String)
    case object([(String, JNode)])
    case array([JNode])

    func render(indent: String, unit: String) -> String {
        switch self {
        case .string(let s):
            return JSONText.quote(s)
        case .array(let items):
            if items.isEmpty { return "[]" }
            let inner = indent + unit
            return "[\n" + items.map { inner + $0.render(indent: inner, unit: unit) }.joined(separator: ",\n")
                + "\n" + indent + "]"
        case .object(let members):
            if members.isEmpty { return "{}" }
            let inner = indent + unit
            return "{\n" + members.map { inner + JSONText.quote($0.0) + ": " + $0.1.render(indent: inner, unit: unit) }
                .joined(separator: ",\n") + "\n" + indent + "}"
        }
    }
}

enum JSONEditError: Error, CustomStringConvertible {
    case invalid(String)
    case unsupported(String)

    var description: String {
        switch self {
        case .invalid(let m): return "Invalid JSON: \(m)"
        case .unsupported(let m): return "Unexpected structure: \(m)"
        }
    }
}

/// Edits a JSON document as text so everything we do not touch stays byte-for-byte
/// identical (key order, indentation, escapes). Only the operations the hook
/// connector needs are implemented: find members/elements, insert as first child,
/// replace a value, remove a child.
struct JSONText {
    private(set) var bytes: [UInt8]

    init(_ string: String) { bytes = Array(string.utf8) }
    var string: String { String(decoding: bytes, as: UTF8.self) }

    struct Child {
        var key: String?        // nil for array elements
        var start: Int          // first byte of the child (the key's quote for members)
        var valueStart: Int
        var end: Int            // exclusive end of the value
    }

    static func quote(_ s: String) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes]),
              let arr = String(data: d, encoding: .utf8) else { return "\"\(s)\"" }
        return String(arr.dropFirst().dropLast())
    }

    // MARK: Scanning

    private func at(_ i: Int) -> UInt8 { i >= 0 && i < bytes.count ? bytes[i] : 0 }
    func char(at i: Int) -> Character { Character(UnicodeScalar(at(i))) }

    func skipWS(_ i: Int) -> Int {
        var j = i
        while j < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[j]) { j += 1 }
        return j
    }

    private func stringEnd(_ i: Int) throws -> Int {
        guard at(i) == 0x22 else { throw JSONEditError.invalid("expected string at \(i)") }
        var j = i + 1
        while j < bytes.count {
            if bytes[j] == 0x5C { j += 2; continue }
            if bytes[j] == 0x22 { return j + 1 }
            j += 1
        }
        throw JSONEditError.invalid("unterminated string")
    }

    /// Exclusive end of the value that starts at `i`.
    func valueEnd(_ i: Int) throws -> Int {
        switch at(i) {
        case 0x22:
            return try stringEnd(i)
        case 0x7B, 0x5B:
            return try container(at: i).close + 1
        case 0:
            throw JSONEditError.invalid("unexpected end")
        default:
            var j = i
            while j < bytes.count, ![0x2C, 0x7D, 0x5D, 0x20, 0x0A, 0x0D, 0x09].contains(bytes[j]) { j += 1 }
            guard j > i else { throw JSONEditError.invalid("bad value at \(i)") }
            return j
        }
    }

    /// Children of the object or array whose opening bracket is at `open`.
    func container(at open: Int) throws -> (children: [Child], close: Int) {
        let isObject = at(open) == 0x7B
        guard isObject || at(open) == 0x5B else { throw JSONEditError.invalid("expected container at \(open)") }
        let closer: UInt8 = isObject ? 0x7D : 0x5D
        var children: [Child] = []
        var j = skipWS(open + 1)
        if at(j) == closer { return (children, j) }
        while true {
            j = skipWS(j)
            let start = j
            var key: String?
            if isObject {
                let kEnd = try stringEnd(j)
                key = try decodeString(j, kEnd)
                j = skipWS(kEnd)
                guard at(j) == 0x3A else { throw JSONEditError.invalid("expected ':' at \(j)") }
                j = skipWS(j + 1)
            }
            let vStart = j
            let vEnd = try valueEnd(j)
            children.append(Child(key: key, start: start, valueStart: vStart, end: vEnd))
            j = skipWS(vEnd)
            if at(j) == 0x2C { j += 1; continue }
            if at(j) == closer { return (children, j) }
            throw JSONEditError.invalid("expected ',' or closer at \(j)")
        }
    }

    func decodeString(_ start: Int, _ end: Int) throws -> String {
        let slice = Data(bytes[start..<end])
        guard let s = try? JSONSerialization.jsonObject(with: slice, options: [.fragmentsAllowed]) as? String
        else { throw JSONEditError.invalid("bad string at \(start)") }
        return s
    }

    // MARK: Formatting helpers

    /// Whitespace at the start of the line that contains offset `i`.
    func lineIndent(at i: Int) -> String {
        var s = min(i, bytes.count)
        while s > 0, bytes[s - 1] != 0x0A { s -= 1 }
        var e = s
        while e < bytes.count, bytes[e] == 0x20 || bytes[e] == 0x09 { e += 1 }
        return String(decoding: bytes[s..<e], as: UTF8.self)
    }

    /// Indent step used by the document (defaults to two spaces).
    func detectUnit() -> String {
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0x0A {
                var j = i + 1
                while j < bytes.count, bytes[j] == 0x20 || bytes[j] == 0x09 { j += 1 }
                if j > i + 1, j < bytes.count, bytes[j] != 0x0A { return String(decoding: bytes[(i + 1)..<j], as: UTF8.self) }
            }
            i += 1
        }
        return "  "
    }

    // MARK: Edits

    mutating func replace(_ range: Range<Int>, with text: String) {
        bytes.replaceSubrange(range, with: Array(text.utf8))
    }

    /// Insert `rendered` as the first child of the container opening at `open`.
    /// Inserting first avoids handling trailing commas, and `removeChild` undoes it exactly.
    mutating func insertFirst(containerAt open: Int, rendered: String, unit: String) throws {
        let (children, close) = try container(at: open)
        let base = lineIndent(at: open)
        if children.isEmpty {
            replace((open + 1)..<close, with: "\n" + base + unit + rendered + "\n" + base)
        } else {
            replace((open + 1)..<(open + 1), with: "\n" + base + unit + rendered + ",")
        }
    }

    /// Remove child `index` of the container at `open`, including its comma.
    mutating func removeChild(containerAt open: Int, index: Int) throws {
        let (children, close) = try container(at: open)
        guard children.indices.contains(index) else { throw JSONEditError.unsupported("no child \(index)") }
        if children.count == 1 {
            replace((open + 1)..<close, with: "")
        } else if index == 0 {
            let comma = skipWS(children[0].end)
            replace((open + 1)..<(comma + 1), with: "")
        } else {
            replace(children[index - 1].end..<children[index].end, with: "")
        }
    }
}

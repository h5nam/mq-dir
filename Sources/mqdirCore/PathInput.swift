import Foundation

/// Turns text the user pastes or types — into the Go to Folder field, or as
/// a ⌘V on the file list — into a location on disk.
///
/// Copied paths arrive in whatever shape their source used: wrapped in
/// quotes by a terminal or chat app, shell-escaped (`My\ Folder`), as a
/// `file://` URL, starting with `~`, or with a compiler's `:line:column`
/// suffix. `resolve` tries the text as written first and only then the
/// unescaped / suffix-stripped variants, so a real file named `a\ b` or
/// `notes:2` still wins over the guess.
enum PathInput {
    enum Resolution: Equatable, Sendable {
        /// Open this folder.
        case folder(URL)
        /// Show this file selected inside its parent folder.
        case file(URL)
        /// Nothing exists at the expanded path, which is carried for display.
        case notFound(String)
        case empty

        /// True when there is somewhere to go.
        var exists: Bool {
            switch self {
            case .folder, .file: true
            case .notFound, .empty: false
            }
        }
    }

    /// A subfolder that finishes the last path component being typed.
    struct Completion: Equatable, Sendable {
        /// The folder's name, NFC-normalized for display.
        let name: String
        /// Field text after accepting this completion. Keeps the user's
        /// prefix (`~/`, relative, absolute) and ends with "/".
        let text: String
        /// Absolute path to the folder.
        let path: String
    }

    /// - Parameters:
    ///   - base: folder that relative input resolves against; home when nil.
    ///   - isDirectory: nil when nothing exists at the path. Injected so tests
    ///     need no real files.
    ///   - canonicalize: the on-disk spelling of an existing path. APFS finds
    ///     `~/dev` or an NFC-typed Hangul name that is stored as `~/Dev` or
    ///     NFD; the canonical form keeps the breadcrumb and selection-by-path
    ///     matching what the folder listing reports.
    static func resolve(
        _ text: String,
        relativeTo base: String?,
        home: String = NSHomeDirectory(),
        isDirectory: (String) -> Bool? = directoryStatus,
        canonicalize: (String) -> String = canonicalPath
    ) -> Resolution {
        guard let cleaned = clean(text) else { return .empty }
        let literal = expand(cleaned, relativeTo: base, home: home)
        guard !literal.contains("\0") else { return .notFound(literal) }
        for candidate in variants(of: cleaned).map({ expand($0, relativeTo: base, home: home) }) {
            switch isDirectory(candidate) {
            case true?: return .folder(URL(fileURLWithPath: canonicalize(candidate), isDirectory: true))
            case false?: return .file(URL(fileURLWithPath: canonicalize(candidate)))
            case nil: continue
            }
        }
        return .notFound(literal)
    }

    /// The cleaned path when pasteboard text is clearly meant as one —
    /// absolute, `~`, `$HOME` or `file://` — so ⌘V on the file list can go
    /// there. Bare words stay inert: copying "Sources" from a chat must not
    /// navigate into a subfolder that happens to share the name.
    static func pastedPath(_ text: String?) -> String? {
        guard let text, let cleaned = clean(text) else { return nil }
        // `clean` has already turned a `file://` URL into "/…".
        let isPathLike = ["/", "~", "$HOME", "${HOME}"].contains { cleaned.hasPrefix($0) }
        return isPathLike ? cleaned : nil
    }

    // MARK: Completion

    /// Folders whose names start with the last component of `text`, matched
    /// case- and Unicode-normalization-insensitively. Hidden folders appear
    /// only once the typed component starts with ".".
    static func completions(
        for text: String,
        relativeTo base: String?,
        home: String = NSHomeDirectory(),
        limit: Int = 8,
        subfolders: (String) -> [String] = subfolderNames
    ) -> [Completion] {
        guard let (directory, partial) = split(text) else { return [] }
        let parent = expand(directory, relativeTo: base, home: home)
        let key = matchKey(partial)
        let names = subfolders(parent)
            .filter { partial.hasPrefix(".") || !$0.hasPrefix(".") }
            .filter { matchKey($0).hasPrefix(key) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return names.prefix(limit).map { name in
            let display = name.precomposedStringWithCanonicalMapping
            return Completion(
                name: display,
                text: directory + display + "/",
                path: parent == "/" ? "/" + name : parent + "/" + name
            )
        }
    }

    /// Shell-style Tab: the longest prefix every completion shares, when it
    /// adds to what was typed. A single completion is accepted outright.
    static func commonCompletion(_ completions: [Completion], for text: String) -> String? {
        guard let first = completions.first, let (directory, partial) = split(text) else { return nil }
        if completions.count == 1 { return first.text }
        let keys = completions.map { Array(matchKey($0.name)) }
        var length = 0
        while keys.allSatisfy({ length < $0.count && $0[length] == keys[0][length] }) {
            length += 1
        }
        guard length > partial.count else { return nil }
        return directory + String(Array(first.name).prefix(length))
    }

    // MARK: Parsing

    /// First non-empty line, trimmed, with wrapping quotes removed and a
    /// `file://` URL decoded to its path. Nil when nothing is left.
    static func clean(_ text: String) -> String? {
        guard let line = text.split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty })
        else { return nil }
        let unquoted = unwrap(line).trimmingCharacters(in: .whitespaces)
        let path = filePath(fromURL: unquoted) ?? unquoted
        return path.isEmpty ? nil : path
    }

    private static let quotePairs: [(Character, Character)] = [
        ("\"", "\""), ("'", "'"), ("`", "`"), ("“", "”"), ("‘", "’"), ("<", ">"),
    ]

    private static func unwrap(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, let last = text.last,
            quotePairs.contains(where: { $0.0 == first && $0.1 == last })
        else { return text }
        return String(text.dropFirst().dropLast())
    }

    private static func filePath(fromURL text: String) -> String? {
        guard text.lowercased().hasPrefix("file:/") else { return nil }
        if let url = URL(string: text), url.isFileURL {
            return url.path(percentEncoded: false)
        }
        // Unencoded spaces make `URL(string:)` fail; decode by hand.
        var rest = text.dropFirst("file:".count).drop(while: { $0 == "/" })
        if rest.lowercased().hasPrefix("localhost/") { rest = rest.dropFirst("localhost".count) }
        let path = "/" + rest.drop(while: { $0 == "/" })
        return path.removingPercentEncoding ?? path
    }

    /// The text as written, then without shell escapes, then without a
    /// `:line[:column]` suffix, then both. Duplicates removed.
    private static func variants(of text: String) -> [String] {
        let unescaped = text.contains("\\") ? shellUnescaped(text) : text
        let all = [text, unescaped, strippingLineSuffix(text), strippingLineSuffix(unescaped)]
        return all.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    private static func shellUnescaped(_ text: String) -> String {
        var result = ""
        var escaping = false
        for character in text {
            if escaping || character != "\\" {
                result.append(character)
                escaping = false
            } else {
                escaping = true
            }
        }
        return result
    }

    /// `Foo.swift:12:3:` → `Foo.swift`, as compilers, linters and grep print.
    private static func strippingLineSuffix(_ text: String) -> String {
        var result = Substring(text)
        if result.hasSuffix(":") { result = result.dropLast() }
        for _ in 0..<2 {
            guard let colon = result.lastIndex(of: ":") else { break }
            let digits = result[result.index(after: colon)...]
            guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit), colon > result.startIndex else { break }
            result = result[..<colon]
        }
        return String(result)
    }

    /// Absolute and standardized: `~` and `$HOME` expanded, relative paths
    /// joined to `base`, `.`/`..` collapsed, no trailing slash.
    private static func expand(_ text: String, relativeTo base: String?, home: String) -> String {
        var path = text
        if path == "~" || path.hasPrefix("~/") {
            path = home + path.dropFirst()
        } else if path.hasPrefix("~") {
            path = (path as NSString).expandingTildeInPath
        } else if let rest = ["${HOME}", "$HOME"].lazy.compactMap({ path.dropPrefix($0) }).first,
            rest.isEmpty || rest.hasPrefix("/") {
            path = home + rest
        }
        if !path.hasPrefix("/") {
            let root = base ?? home
            path = path.isEmpty ? root : (root.hasSuffix("/") ? root : root + "/") + path
        }
        while path.contains("//") { path = path.replacingOccurrences(of: "//", with: "/") }
        // `URL.standardized` only collapses dot segments; unlike
        // `NSString.standardizingPath` it leaves `/private/…` untouched.
        let standardized = URL(fileURLWithPath: path, isDirectory: false).standardized.path
        return standardized.isEmpty ? "/" : standardized
    }

    /// Splits typed text into the directory part (through the last "/") and
    /// the partial name after it. Nil when there is nothing to complete
    /// against, such as a bare `~user` or multi-line input.
    private static func split(_ text: String) -> (directory: String, partial: String)? {
        guard !text.isEmpty, !text.contains(where: \.isNewline) else { return nil }
        guard let slash = text.lastIndex(of: "/") else {
            return text.hasPrefix("~") || text.hasPrefix("$") ? nil : ("", text)
        }
        return (String(text[...slash]), String(text[text.index(after: slash)...]))
    }

    private static func matchKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    // MARK: File system

    static func directoryStatus(_ path: String) -> Bool? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue
    }

    static func canonicalPath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return (try? url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? path
    }

    /// Names of the folders directly inside `path`, symlinks to folders and
    /// hidden folders included. Empty when the folder can't be read.
    static func subfolderNames(_ path: String) -> [String] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: path, isDirectory: true), includingPropertiesForKeys: keys)
        else { return [] }
        return items.compactMap { item in
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { return nil }
            if values.isDirectory == true { return item.lastPathComponent }
            guard values.isSymbolicLink == true else { return nil }
            return directoryStatus(item.resolvingSymlinksInPath().path) == true ? item.lastPathComponent : nil
        }
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

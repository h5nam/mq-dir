import Foundation

struct FileSystemService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func enumerateDirectory(
        at url: URL, includingHidden: Bool = false,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> [FileEntry] {
        if isCancelled() { throw CancellationError() }
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isHiddenKey,
            .tagNamesKey,
            .labelNumberKey,
        ]

        var options: FileManager.DirectoryEnumerationOptions = []
        if !includingHidden {
            options.insert(.skipsHiddenFiles)
        }

        let urls = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: options
        )

        return try urls.map { childURL in
            if isCancelled() { throw CancellationError() }
            let values = try childURL.resourceValues(forKeys: keys)
            let isDirectory = values.isDirectory ?? false
            let name = childURL.lastPathComponent
            let tagNames = values.tagNames ?? []
            let labelNumber = values.labelNumber ?? 0
            let tagColors = Self.tagColors(for: childURL, names: tagNames, primaryLabelNumber: labelNumber)
            let hasCustomIcon = isDirectory && Self.folderHasCustomIcon(at: childURL)

            return FileEntry(
                // Foundation may return an alias (/private/var for /var).
                // Keep URLs in the requested root's namespace for tree IDs.
                url: Self.entryURL(components: [name], root: url, isDirectory: isDirectory),
                name: name,
                isDirectory: isDirectory,
                size: isDirectory ? nil : values.fileSize.map(Int64.init),
                modificationDate: values.contentModificationDate,
                kind: kind(for: childURL, isDirectory: isDirectory),
                isHidden: values.isHidden ?? name.hasPrefix("."),
                tagNames: tagNames,
                labelNumber: labelNumber,
                tagColors: tagColors,
                hasCustomIcon: hasCustomIcon
            )
        }
    }

    /// Recursive name search rooted at `url`. Visits every descendant via
    /// `FileManager.enumerator`, keeping entries whose name matches `query`
    /// case-insensitively. Errors on individual children are skipped so the
    /// walk doesn't abort on a single inaccessible subfolder. The
    /// `isCancelled` callback is polled periodically so a caller can stop a
    /// long walk when a fresher query supersedes it.
    func enumerateMatching(
        root: URL,
        query: String,
        includingHidden: Bool = false,
        isCancelled: @Sendable () -> Bool = { false },
        onProgress: (@Sendable ([FileEntry]) -> Void)? = nil,
        filter: FileSearchFilter = .init(),
        diagnostics: FileSearchDiagnostics? = nil
    ) throws -> [FileEntry] {
        guard (!query.isEmpty || filter.isActive), !isCancelled() else { return [] }

        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isHiddenKey,
            .tagNamesKey,
            .labelNumberKey,
        ]

        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includingHidden {
            options.insert(.skipsHiddenFiles)
        }

        guard let enumerator = fileManager.enumerator(
            at: root.resolvingSymlinksInPath(),
            includingPropertiesForKeys: Array(keys),
            options: options,
            errorHandler: { _, _ in diagnostics?.recordError(); return true }
        ) else {
            diagnostics?.recordError()
            return []
        }

        var results: [FileEntry] = []
        var nextProgressCount = 1
        for case let childURL as URL in enumerator {
            if isCancelled() { return results }

            let name = childURL.lastPathComponent
            // Match name first (cheap) so the resourceValues fetch
            // only fires for non-name candidates that still might
            // match by Finder tag. Tag-name matching covers the
            // sidebar's "click a tag" path on systems where the
            // tag is localised (e.g. "초록색") and so never appears
            // inside Latin-named files.
            let nameMatches = query.isEmpty || name.localizedCaseInsensitiveContains(query)
            let values = try? childURL.resourceValues(forKeys: keys)
            if values == nil { diagnostics?.recordError(); continue }
            let tagMatches: Bool
            if nameMatches {
                tagMatches = false
            } else {
                tagMatches = (values?.tagNames ?? []).contains {
                    $0.localizedCaseInsensitiveContains(query)
                }
            }
            guard nameMatches || tagMatches else { continue }

            let isDirectory = values?.isDirectory ?? false
            let tagNames = values?.tagNames ?? []
            let labelNumber = values?.labelNumber ?? 0
            let tagColors = Self.tagColors(for: childURL, names: tagNames, primaryLabelNumber: labelNumber)
            let hasCustomIcon = isDirectory && Self.folderHasCustomIcon(at: childURL)
            let relativeComponents = Array(childURL.pathComponents.suffix(enumerator.level))
            let entry = FileEntry(
                url: Self.entryURL(components: relativeComponents, root: root, isDirectory: isDirectory),
                name: name,
                isDirectory: isDirectory,
                size: isDirectory ? nil : (values?.fileSize).map(Int64.init),
                modificationDate: values?.contentModificationDate,
                kind: kind(for: childURL, isDirectory: isDirectory),
                isHidden: values?.isHidden ?? name.hasPrefix("."),
                tagNames: tagNames,
                labelNumber: labelNumber,
                tagColors: tagColors,
                hasCustomIcon: hasCustomIcon
            )
            guard filter.matches(entry) else { continue }
            results.append(entry)
            // Geometric milestones expose early matches while bounding the
            // number and retained size of UI snapshots for very large trees.
            if results.count == nextProgressCount {
                onProgress?(results)
                nextProgressCount = nextProgressCount <= Int.max / 8 ? nextProgressCount * 8 : Int.max
            }
        }

        return results
    }

    /// Preserve the caller's path namespace and exact Unicode filename bytes.
    /// Foundation's metadata URLs can switch /var to /private/var; constructing
    /// from a percent-encoded string also avoids re-normalizing NFC filenames.
    private static func entryURL(components: [String], root: URL, isDirectory: Bool) -> URL {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let path = prefix + components.joined(separator: "/") + (isDirectory ? "/" : "")
        if let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let result = URL(string: "file://" + encoded) {
            return result
        }
        return components.reduce(root) { $0.appendingPathComponent($1) }
    }

    /// Pull per-tag colour indices from `com.apple.metadata:_kMDItemUserTags`.
    /// macOS stores Finder tags there as a binary plist of strings; each
    /// entry is multi-line `"<name>\n<colour 0-7>\n<flag>"` where the
    /// trailing flag line is an internal "system tag" marker. Older
    /// writers (raw `setxattr` callers, third-party taggers) sometimes
    /// emit the flat `"<name>\n<colour>"` form or even bare `"<name>"`
    /// with no colour. Returns an array aligned with `names` so the
    /// dot renderer can paint each tag in its real Finder swatch.
    ///
    /// Pairs xattr entries with `names` *by index* rather than by name.
    /// The original name-based dictionary lookup silently fell back to
    /// `0` whenever the URLResource tag name and the xattr-parsed name
    /// disagreed even slightly — Korean tag names like "빨간색" came
    /// back from URLResource in one Unicode normalisation form and
    /// from the raw xattr in another on real-world files, so every
    /// existing tag rendered grey until the user retagged the file.
    /// macOS keeps the two sources ordered consistently, so
    /// index-pairing sidesteps the whole normalisation question.
    ///
    /// `primaryLabelNumber` is the file's `URLResourceKey.labelNumber`
    /// — a legacy `com.apple.FinderInfo` colour stamp that some files
    /// (especially ones tagged via AppleScript's `label index of`, or
    /// pre-Mavericks Finder labels) carry instead of a populated
    /// `_kMDItemUserTags` xattr. When that's the only source of truth,
    /// stamp it onto the primary tag so the dot renders the right
    /// colour instead of dropping to grey.
    static func tagColors(for url: URL, names: [String], primaryLabelNumber: Int = 0) -> [Int] {
        guard !names.isEmpty else { return [] }
        let parsed = parseUserTagsXattr(for: url)
        var colours: [Int] = (0..<names.count).map { i in
            i < parsed.count ? parsed[i].1 : 0
        }
        // Legacy FinderInfo fallback: tagNames synthesises a name like
        // "Blue" from the labelNumber, but the matching xattr entry
        // (when even present) carries colour 0. Stamp the labelNumber
        // onto the primary slot so the row still paints.
        if primaryLabelNumber > 0, !colours.isEmpty, colours[0] == 0 {
            colours[0] = primaryLabelNumber
        }
        return colours
    }

    /// Decode the raw xattr into `(name, colourIndex)` pairs. Defensive
    /// against malformed data — an unparseable index collapses to `0`
    /// (no colour) rather than blowing up the whole enumeration.
    private static func parseUserTagsXattr(for url: URL) -> [(String, Int)] {
        let path = url.path
        let key = "com.apple.metadata:_kMDItemUserTags"
        let length = getxattr(path, key, nil, 0, 0, 0)
        guard length > 0 else { return [] }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { buf -> ssize_t in
            guard let base = buf.baseAddress else { return -1 }
            return getxattr(path, key, base, length, 0, 0)
        }
        // Deliberate bail-to-empty on the two-call getxattr TOCTOU: the first
        // call sizes the buffer, the second fills it. If another writer
        // retagged the file between the two calls the second read returns a
        // different length; rather than parse a torn buffer we treat the file
        // as untagged for this pass. The next enumeration re-reads it cleanly.
        // This is intentional, not a missing retry loop.
        guard read == length else { return [] }
        guard let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let entries = raw as? [String]
        else { return [] }
        return entries.map { entry -> (String, Int) in
            // Apple's URLResource writer (which Finder uses) stores
            // entries as `"<name>\n<colour>\n<flag>"` — three lines.
            // Raw `setxattr` callers and older writers use the flat
            // `"<name>\n<colour>"` form, and uncoloured tags arrive
            // as bare `"<name>"`. Split into lines and read the
            // colour off line 2 so all three shapes parse the same.
            let lines = entry.split(separator: "\n", omittingEmptySubsequences: false)
            guard let first = lines.first else { return (entry, 0) }
            let name = String(first)
            let colour: Int
            if lines.count >= 2,
               let parsed = Int(lines[1]),
               (0...7).contains(parsed) {
                colour = parsed
            } else {
                colour = 0
            }
            return (name, colour)
        }
    }

    /// Currently-applied Finder tags for `url`. Reads
    /// `com.apple.metadata:_kMDItemUserTags` so the tag picker can paint
    /// checkmarks next to colours the file already carries and so the
    /// toggle helper can compare against the on-disk set. Returns an
    /// empty array for untagged files.
    public static func currentTags(for url: URL) -> [(name: String, colour: Int)] {
        parseUserTagsXattr(for: url)
    }

    /// Replace the Finder-tag set on `url` with `tags`. Pass an empty
    /// array to clear every tag. Routes through `NSURL.setResourceValue`
    /// because `URLResourceValues.tagNames` only gained a setter on
    /// macOS 26 and we still ship to 14.0; the NSURL bridge has owned
    /// this key since 10.9 and macOS normalises the xattr layout +
    /// fires the Spotlight / Finder sync side effects either way.
    public static func setTags(_ tags: [(name: String, colour: Int)], on url: URL) throws {
        // Round-trip asymmetry by design: `currentTags` (via parseUserTagsXattr)
        // reads only the first two lines `"<name>\n<colour>"` and drops Apple's
        // optional third "system tag" flag line. We rewrite in the same two-line
        // form, so a `currentTags` → `setTags` cycle strips that flag. For the
        // plain user tags this app creates (name + colour) the toggle round-trip
        // is lossless; only the rarely-present internal flag is discarded, and
        // macOS re-derives it as needed. Not a bug — don't "fix" by re-emitting
        // a flag line we never parse back.
        let formatted = tags.map { tag -> String in
            guard (1...7).contains(tag.colour) else { return tag.name }
            return "\(tag.name)\n\(tag.colour)"
        }
        try (url as NSURL).setResourceValue(formatted as NSArray, forKey: .tagNamesKey)
    }

    /// Toggle the standard Finder colour `label` (1-7) on `url`. When
    /// the colour is already present, the matching tag is removed;
    /// otherwise `displayName` is appended as a new tag. `displayName`
    /// is what shows in the user's locale ("Red" / "빨강") so Finder
    /// and Spotlight render the same string mq-dir wrote. `label == 0`
    /// is the "clear all tags" affordance the picker uses for its
    /// Clear row.
    public static func toggleColourTag(label: Int, displayName: String, on url: URL) throws {
        var tags = currentTags(for: url)
        if label == 0 {
            tags.removeAll()
        } else if let existing = tags.firstIndex(where: { $0.colour == label }) {
            tags.remove(at: existing)
        } else {
            tags.append((name: displayName, colour: label))
        }
        try setTags(tags, on: url)
    }

    /// Ordered chain of ancestor folder URLs strictly between `root` and
    /// `leaf`, top-down (shallowest first). Powers "Reveal in Tree": every
    /// returned URL is a folder the tree view must expand (and load children
    /// for) so the leaf becomes visible. `root` itself is excluded (it's the
    /// always-expanded tree root) and so is `leaf` (the entry being revealed,
    /// which is selected, not expanded).
    ///
    /// Pure path math — no disk access. Returns `[]` when `leaf` is a direct
    /// child of `root` (nothing to expand) or when `leaf` is not actually
    /// under `root` (defensive: a reveal target from a stale search result).
    /// Path components are compared after standardisation so a `root` carrying
    /// `.`/`..` or a trailing slash still matches a clean `leaf`.
    static func ancestorFolders(from root: URL, to leaf: URL) -> [URL] {
        let rootComponents = root.standardizedFileURL.pathComponents
        let leafComponents = leaf.standardizedFileURL.pathComponents
        // Leaf must be strictly deeper than root and share its prefix.
        guard leafComponents.count > rootComponents.count,
              Array(leafComponents.prefix(rootComponents.count)) == rootComponents
        else { return [] }

        // Intermediate components are everything between the root depth and
        // the leaf's own last component (exclusive on both ends).
        var ancestors: [URL] = []
        var current = root
        for component in leafComponents[rootComponents.count..<(leafComponents.count - 1)] {
            current = current.appendingPathComponent(component)
            ancestors.append(current)
        }
        return ancestors
    }

    /// Bookmarks may resolve /var as /private/var after relaunch. Rebase
    /// remembered paths onto the resolved root without changing their suffix.
    static func restoredPath(_ path: String, under root: URL) -> String? {
        let source = URL(fileURLWithPath: path)
        let rootParts = root.standardizedFileURL.pathComponents
        let sourceParts = source.standardizedFileURL.pathComponents
        guard sourceParts.starts(with: rootParts) else { return nil }
        let suffix = source.pathComponents.suffix(sourceParts.count - rootParts.count)
        return suffix.reduce(root) { $0.appendingPathComponent($1) }.path
    }

    /// Recursively sum the logical sizes of every file under `directory`.
    /// Powers the on-demand "Calculate Size" action — directories carry no
    /// `size` of their own in `enumerateDirectory`, so a folder's footprint
    /// has to be walked. Uses `fileSizeKey` (logical file size) rather than
    /// `totalFileAllocatedSize` so the total stays consistent with the size
    /// column, which renders `fileSize` for individual files.
    ///
    /// Behaviour pinned by `FileSystemServiceSizeTests`:
    /// - Hidden files ARE counted (no `.skipsHiddenFiles`) — a folder's real
    ///   footprint includes its dotfiles; this is "how big is this on disk",
    ///   not "what does the browser show".
    /// - Symlinks are NOT followed: the enumerator descends real directories
    ///   only, and a symlink entry contributes its own (tiny) link size via
    ///   `fileSizeKey`, never the target's bytes. This avoids double-counting
    ///   and infinite loops on cyclic links — the enumerator's default
    ///   (no `.producesRelativePathURLs`, no follow) gives us this for free.
    ///
    /// `isCancelled` is checked before and throughout the walk so navigation
    /// away can stop even a small tree;
    /// on cancel it returns the partial sum gathered so far, which is
    /// harmless because the caller treats the result as a cache entry it can
    /// recompute on demand.
    func directorySize(
        at directory: URL,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> Int64 {
        if isCancelled() { return 0 }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let childURL as URL in enumerator {
            if isCancelled() { return total }
            // Only regular files contribute. Directories report no
            // meaningful `fileSize`; symlinks surface as non-regular and
            // are skipped so the link target's bytes aren't double-counted.
            let values = try? childURL.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            if let size = values?.fileSize {
                total &+= Int64(size)
            }
        }
        return total
    }

    /// Cheap presence check for the `Icon\r` sentinel macOS writes inside
    /// any folder whose icon the user changed via Get Info → drag image.
    /// One `stat(2)` per folder; we deliberately don't load the actual
    /// icon here — that work belongs to the row view via
    /// `NSWorkspace.shared.icon(forFile:)`, which caches internally.
    static func folderHasCustomIcon(at url: URL) -> Bool {
        let iconPath = url.appendingPathComponent("Icon\r").path
        return FileManager.default.fileExists(atPath: iconPath)
    }

    private func kind(for url: URL, isDirectory: Bool) -> String {
        if isDirectory {
            return "Folder"
        }

        let ext = url.pathExtension
        if ext.isEmpty {
            return "Document"
        }

        return "\(ext.uppercased()) Document"
    }
}

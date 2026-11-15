/// A unified diff (`diff -u` format, three lines of context) between two versions of a file.
enum UnifiedDiff {
    static func diff(old: String, new: String, oldPath: String, newPath: String, context: Int = 3) -> String {
        let oldLines = lines(of: old)
        let newLines = lines(of: new)
        return render(
            operations(from: oldLines, to: newLines),
            oldLine: { oldLines[$0] },
            newLine: { newLines[$0] },
            oldPath: oldPath,
            newPath: newPath,
            context: context
        )
    }

    /// The diff of `new`, which is `old` without the bytes of the sorted, disjoint `removed` ranges. Only the lines
    /// that hold removed bytes are compared, so the time follows the size of the removal, not the size of the file:
    /// `diff(old:new:)` compares every line, which takes minutes on a large file. The edit is as small; only where
    /// equal lines leave a choice may the hunks differ.
    static func diff(old: String, new: String, removing removed: [Range<Int>], oldPath: String, newPath: String, context: Int = 3) -> String {
        let oldLines = ByteLines(old)
        let newLines = ByteLines(new)
        return render(
            operations(from: oldLines, to: newLines, removing: removed),
            oldLine: { oldLines[$0] },
            newLine: { newLines[$0] },
            oldPath: oldPath,
            newPath: newPath,
            context: context
        )
    }

    // MARK: - Private

    private enum OperationKind { case equal, delete, insert }

    private struct Operation {
        let kind: OperationKind
        let oldIndex: Int
        let newIndex: Int
    }

    /// The lines of a text, found by their UTF-8 offsets: cut after each line feed (a CRLF terminator ends with
    /// one), like `lines(of:)`.
    private struct ByteLines {
        let text: String
        let byteCount: Int
        /// The UTF-8 offset of the first byte of each line.
        let starts: [Int]

        init(_ text: String) {
            self.text = text
            byteCount = text.utf8.count
            var starts = byteCount == 0 ? [] : [0]
            for (offset, byte) in text.utf8.enumerated() where byte == 0x0A && offset + 1 < byteCount {
                starts.append(offset + 1)
            }
            self.starts = starts
        }

        var count: Int {
            starts.count
        }

        subscript(index: Int) -> Substring {
            let utf8 = text.utf8
            let start = utf8.index(utf8.startIndex, offsetBy: starts[index])
            let end = index + 1 < starts.count ? utf8.index(utf8.startIndex, offsetBy: starts[index + 1]) : utf8.endIndex
            return text[start ..< end]
        }

        /// The line that holds the byte at `offset`, or `count` at the end of the text.
        func index(containing offset: Int) -> Int {
            guard offset < byteCount else { return count }

            var low = 0
            var high = starts.count
            while high - low > 1 {
                let middle = (low + high) / 2
                if starts[middle] <= offset {
                    low = middle
                } else {
                    high = middle
                }
            }
            return low
        }
    }

    /// The lines of a text, each with its terminator; the last one has none when the text does not end with a newline.
    private static func lines(of text: String) -> [Substring] {
        var lines: [Substring] = []
        var start = text.startIndex
        for index in text.indices where text[index] == "\n" || text[index] == "\r\n" {
            let end = text.index(after: index)
            lines.append(text[start ..< end])
            start = end
        }
        if start < text.endIndex {
            lines.append(text[start...])
        }
        return lines
    }

    private static func render(
        _ operations: [Operation],
        oldLine: (Int) -> Substring,
        newLine: (Int) -> Substring,
        oldPath: String,
        newPath: String,
        context: Int
    ) -> String {
        guard operations.contains(where: { $0.kind != .equal }) else { return "" }

        var output = "--- \(oldPath)\n+++ \(newPath)\n"
        for hunk in hunks(of: operations, context: context) {
            output += header(of: hunk)
            for operation in hunk {
                switch operation.kind {
                case .equal: output += line(" ", oldLine(operation.oldIndex))
                case .delete: output += line("-", oldLine(operation.oldIndex))
                case .insert: output += line("+", newLine(operation.newIndex))
                }
            }
        }
        return output
    }

    private static func line(_ prefix: String, _ text: Substring) -> String {
        // A CRLF terminator is a single `Character`, which `hasSuffix("\n")` does not match.
        text.last == "\n" || text.last == "\r\n" ? prefix + text : prefix + text + "\n\\ No newline at end of file\n"
    }

    private static func operations(from oldLines: [Substring], to newLines: [Substring]) -> [Operation] {
        let difference = newLines.difference(from: oldLines)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }

        var operations: [Operation] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count, removed.contains(oldIndex) {
                operations.append(Operation(kind: .delete, oldIndex: oldIndex, newIndex: newIndex))
                oldIndex += 1
            } else if newIndex < newLines.count, inserted.contains(newIndex) {
                operations.append(Operation(kind: .insert, oldIndex: oldIndex, newIndex: newIndex))
                newIndex += 1
            } else {
                operations.append(Operation(kind: .equal, oldIndex: oldIndex, newIndex: newIndex))
                oldIndex += 1
                newIndex += 1
            }
        }
        return operations
    }

    /// The lines that hold no removed byte are equal; the others are grouped into regions, each the lines that hold
    /// overlapping removals in the old file and what is left of them in the new one, compared on their own.
    private static func operations(from oldLines: ByteLines, to newLines: ByteLines, removing removed: [Range<Int>]) -> [Operation] {
        var operations: [Operation] = []
        operations.reserveCapacity(oldLines.count)
        var oldIndex = 0
        var newIndex = 0
        var removedBefore = 0
        var rangeIndex = 0
        while rangeIndex < removed.count {
            let firstLine = oldLines.index(containing: removed[rangeIndex].lowerBound)
            var endLine = firstLine
            var removedInRegion = 0
            repeat {
                // The line that holds the first kept byte joins what is left of the line the removal starts in.
                let upperBound = removed[rangeIndex].upperBound
                endLine = upperBound < oldLines.byteCount ? oldLines.index(containing: upperBound) + 1 : oldLines.count
                removedInRegion += removed[rangeIndex].count
                rangeIndex += 1
            } while rangeIndex < removed.count && oldLines.index(containing: removed[rangeIndex].lowerBound) < endLine

            while oldIndex < firstLine {
                operations.append(Operation(kind: .equal, oldIndex: oldIndex, newIndex: newIndex))
                oldIndex += 1
                newIndex += 1
            }
            let regionEnd = endLine < oldLines.count ? oldLines.starts[endLine] : oldLines.byteCount
            let newEndLine = newLines.index(containing: regionEnd - removedBefore - removedInRegion)
            operations += regionOperations(from: oldLines, oldIndex ..< endLine, to: newLines, newIndex ..< newEndLine)
            oldIndex = endLine
            newIndex = newEndLine
            removedBefore += removedInRegion
        }
        while oldIndex < oldLines.count {
            operations.append(Operation(kind: .equal, oldIndex: oldIndex, newIndex: newIndex))
            oldIndex += 1
            newIndex += 1
        }
        return operations
    }

    /// When a region only loses lines, each new line is matched with the first equal old line, so that a removed
    /// member shows its own lines and not the closing line of the member before it. Otherwise a small region is
    /// compared like whole files, and a large one keeps its common first and last lines and replaces the others.
    private static func regionOperations(from oldLines: ByteLines, _ old: Range<Int>, to newLines: ByteLines, _ new: Range<Int>) -> [Operation] {
        var operations: [Operation] = []
        var newIndex = new.lowerBound
        for oldIndex in old {
            if newIndex < new.upperBound, oldLines[oldIndex] == newLines[newIndex] {
                operations.append(Operation(kind: .equal, oldIndex: oldIndex, newIndex: newIndex))
                newIndex += 1
            } else {
                operations.append(Operation(kind: .delete, oldIndex: oldIndex, newIndex: newIndex))
            }
        }
        guard newIndex < new.upperBound else { return operations }

        if old.count + new.count <= 2000 {
            return Self.operations(from: old.map { oldLines[$0] }, to: new.map { newLines[$0] }).map {
                Operation(kind: $0.kind, oldIndex: $0.oldIndex + old.lowerBound, newIndex: $0.newIndex + new.lowerBound)
            }
        }
        var prefix = 0
        while prefix < min(old.count, new.count), oldLines[old.lowerBound + prefix] == newLines[new.lowerBound + prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix, oldLines[old.upperBound - 1 - suffix] == newLines[new.upperBound - 1 - suffix] {
            suffix += 1
        }
        operations = (0 ..< prefix).map { Operation(kind: .equal, oldIndex: old.lowerBound + $0, newIndex: new.lowerBound + $0) }
        operations += (old.lowerBound + prefix ..< old.upperBound - suffix).map {
            Operation(kind: .delete, oldIndex: $0, newIndex: new.lowerBound + prefix)
        }
        operations += (new.lowerBound + prefix ..< new.upperBound - suffix).map {
            Operation(kind: .insert, oldIndex: old.upperBound - suffix, newIndex: $0)
        }
        operations += (0 ..< suffix).reversed().map {
            Operation(kind: .equal, oldIndex: old.upperBound - 1 - $0, newIndex: new.upperBound - 1 - $0)
        }
        return operations
    }

    private static func hunks(of operations: [Operation], context: Int) -> [ArraySlice<Operation>] {
        let changed = operations.indices.filter { operations[$0].kind != .equal }
        var hunks: [ArraySlice<Operation>] = []
        var start = max(0, changed[0] - context)
        var end = min(operations.count, changed[0] + context + 1)

        for index in changed.dropFirst() {
            if index - context <= end {
                end = min(operations.count, index + context + 1)
            } else {
                hunks.append(operations[start ..< end])
                start = index - context
                end = min(operations.count, index + context + 1)
            }
        }
        hunks.append(operations[start ..< end])
        return hunks
    }

    private static func header(of hunk: ArraySlice<Operation>) -> String {
        let oldCount = hunk.count { $0.kind != .insert }
        let newCount = hunk.count { $0.kind != .delete }
        let first = hunk[hunk.startIndex]
        let oldStart = oldCount == 0 ? first.oldIndex : first.oldIndex + 1
        let newStart = newCount == 0 ? first.newIndex : first.newIndex + 1
        return "@@ -\(range(oldStart, oldCount)) +\(range(newStart, newCount)) @@\n"
    }

    private static func range(_ start: Int, _ count: Int) -> String {
        count == 1 ? "\(start)" : "\(start),\(count)"
    }
}

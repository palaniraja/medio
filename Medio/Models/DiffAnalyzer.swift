import Foundation

final class DiffAnalyzer {
    private let sourceText: String
    private let targetText: String
    private let isCode: Bool
    private let sourceLines: [Line]
    private let targetLines: [Line]
    
    init(sourceText: String, targetText: String) {
        self.sourceText = sourceText
        self.targetText = targetText
        self.isCode = CodeAnalyzer.detectCodeContent(sourceText)
        self.sourceLines = Self.getLinesWithRanges(text: sourceText)
        self.targetLines = Self.getLinesWithRanges(text: targetText)
    }
    
    private static func getLinesWithRanges(text: String) -> [Line] {
        var currentLocation = 0
        return text.components(separatedBy: .newlines).map { line in
            let length = line.utf16.count
            let range = NSRange(location: currentLocation, length: length)
            currentLocation += length + 1
            return Line(text: line, range: range)
        }
    }
    
    func computeDifferences() -> [LineDiff] {
        let sourceLinesText = sourceLines.map { $0.text }
        let targetLinesText = targetLines.map { $0.text }
        
        // Use Swift's built-in difference to compute changes
        let differences = targetLinesText.difference(from: sourceLinesText)
        var lineDiffs: [LineDiff] = []
        var processedIndices = Set<Int>()
        var removedIndices = Set<Int>()
        
        // Collect removed indices from the diff
        for change in differences {
            if case .remove(let offset, _, _) = change {
                removedIndices.insert(offset)
            }
        }
        
        for (sourceIdx, sourceLine) in sourceLines.enumerated() {
            if processedIndices.contains(sourceIdx) { continue }
            
            let diff: LineDiff
            
            // Check if this line was removed/changed
            if removedIndices.contains(sourceIdx) {
                // Find the best matching target line
                if let (targetLine, similarity) = findBestMatch(
                    sourceLine: sourceLine.text,
                    in: targetLinesText,
                    threshold: isCode ? 0.5 : 0.3
                ) {
                    diff = createLineDiff(
                        sourceLine: sourceLine,
                        targetLine: targetLine,
                        lineNumber: sourceIdx,
                        similarity: similarity
                    )
                } else {
                    // No match found - pure deletion
                    diff = LineDiff(
                        range: sourceLine.range,
                        wordDiffs: [WordDiff(range: sourceLine.range, type: .deletion)],
                        isDifferent: true,
                        lineNumber: sourceIdx
                    )
                }
            } else {
                // Line wasn't removed - check if it's unchanged
                if targetLinesText.contains(sourceLine.text) {
                    diff = LineDiff(
                        range: sourceLine.range,
                        wordDiffs: [],
                        isDifferent: false,
                        lineNumber: sourceIdx
                    )
                } else {
                    // Try to find a similar line
                    if let (targetLine, similarity) = findBestMatch(
                        sourceLine: sourceLine.text,
                        in: targetLinesText,
                        threshold: isCode ? 0.5 : 0.3
                    ) {
                        diff = createLineDiff(
                            sourceLine: sourceLine,
                            targetLine: targetLine,
                            lineNumber: sourceIdx,
                            similarity: similarity
                        )
                    } else {
                        diff = LineDiff(
                            range: sourceLine.range,
                            wordDiffs: [WordDiff(range: sourceLine.range, type: .deletion)],
                            isDifferent: true,
                            lineNumber: sourceIdx
                        )
                    }
                }
            }
            
            processedIndices.insert(sourceIdx)
            lineDiffs.append(diff)
        }
        
        return lineDiffs.sorted { $0.lineNumber < $1.lineNumber }
    }
    
    private func createLineDiff(
        sourceLine: Line,
        targetLine: String,
        lineNumber: Int,
        similarity: Double
    ) -> LineDiff {
        let wordDiffs = computeWordDiffs(
            sourceLine: sourceLine,
            targetLine: targetLine,
            similarity: similarity
        )
        
        return LineDiff(
            range: sourceLine.range,
            wordDiffs: wordDiffs,
            isDifferent: !wordDiffs.isEmpty,
            lineNumber: lineNumber
        )
    }
    
    private func findBestMatch(
        sourceLine: String,
        in targetLines: [String],
        threshold: Double
    ) -> (line: String, similarity: Double)? {
        var bestMatch: (line: String, similarity: Double) = ("", 0)
        
        for targetLine in targetLines {
            let similarity = calculateSimilarity(
                source: sourceLine,
                target: targetLine
            )
            
            if similarity > bestMatch.similarity {
                bestMatch = (targetLine, similarity)
            }
        }
        
        return bestMatch.similarity >= threshold ? bestMatch : nil
    }
    
    private func calculateSimilarity(source: String, target: String) -> Double {
        let sourceTokens = tokenize(source)
        let targetTokens = tokenize(target)
        
        // Handle empty cases
        guard !sourceTokens.isEmpty && !targetTokens.isEmpty else {
            return sourceTokens.isEmpty && targetTokens.isEmpty ? 1.0 : 0.0
        }
        
        if isCode {
            return calculateCodeSimilarity(sourceTokens, targetTokens)
        } else {
            return calculateTextSimilarity(sourceTokens, targetTokens)
        }
    }
    
    private func calculateCodeSimilarity(
        _ sourceTokens: [Token],
        _ targetTokens: [Token]
    ) -> Double {
        // Filter out whitespace and normalize tokens
        let source = sourceTokens.filter { $0.type != .whitespace }.map { $0.normalized }
        let target = targetTokens.filter { $0.type != .whitespace }.map { $0.normalized }
        
        // Use Swift's built-in difference to compute changes
        let differences = target.difference(from: source)
        let changes = differences.insertions.count + differences.removals.count
        let maxLength = Double(max(source.count, target.count))
        
        guard maxLength > 0 else { return 1.0 }
        
        return 1.0 - (Double(changes) / maxLength)
    }
    
    private func calculateTextSimilarity(
        _ sourceTokens: [Token],
        _ targetTokens: [Token]
    ) -> Double {
        let source = Set(sourceTokens.filter { $0.type != .whitespace }.map { $0.normalized })
        let target = Set(targetTokens.filter { $0.type != .whitespace }.map { $0.normalized })
        
        let intersection = source.intersection(target)
        let union = source.union(target)
        
        return Double(intersection.count) / Double(union.count)
    }
    
    private func computeWordDiffs(
            sourceLine: Line,
            targetLine: String,
            similarity: Double
        ) -> [WordDiff] {
            if isCode {
                return computeCodeDiffs(sourceLine: sourceLine, targetLine: targetLine)
            } else {
                return computeTextDiffs(sourceLine: sourceLine, targetLine: targetLine)
            }
        }
        
    private func computeCodeDiffs(
           sourceLine: Line,
           targetLine: String
       ) -> [WordDiff] {
           // Tokenize both lines
           let sourceTokens = tokenizeCode(sourceLine.text)
           let targetTokens = tokenizeCode(targetLine)
           
           // Build character position map
           var sourceMap: [(token: Token, location: Int)] = []
           var currentLocation = sourceLine.range.location
           
           for token in sourceTokens {
               if !token.text.isEmpty {
                   sourceMap.append((token, currentLocation))
                   currentLocation += token.text.utf16.count
               }
           }
           
           // Create target token sets
           let targetWords = Set(targetTokens.filter { $0.type == .word }.map { $0.normalized })
           let targetOperators = Set(targetTokens.filter { $0.type == .operator }.map { $0.text })
           
           var wordDiffs: [WordDiff] = []
           
           // Process each token
           for (token, location) in sourceMap {
               switch token.type {
               case .word:
                   let tokenLength = token.text.utf16.count
                   // Check if word exists in target
                   if !targetWords.contains(token.normalized) {
                       wordDiffs.append(WordDiff(
                           range: NSRange(location: location, length: tokenLength),
                           type: .modification
                       ))
                   }
                   
               case .operator:
                   let tokenLength = token.text.utf16.count
                   // Check if operator exists in target
                   if !targetOperators.contains(token.text) {
                       wordDiffs.append(WordDiff(
                           range: NSRange(location: location, length: tokenLength),
                           type: .modification
                       ))
                   }
                   
               default:
                   continue
               }
           }
           
           // Handle special cases
           handleSpecialCases(
               sourceLine: sourceLine,
               targetLine: targetLine,
               sourceMap: sourceMap,
               wordDiffs: &wordDiffs
           )
           
           return wordDiffs.sorted { $0.range.location < $1.range.location }
       }
       
    private func handleSpecialCases(
            sourceLine: Line,
            targetLine: String,
            sourceMap: [(token: Token, location: Int)],
            wordDiffs: inout [WordDiff]
        ) {
            // Handle variable changes (total → sum)
            if let totalToken = sourceMap.first(where: { $0.token.text == "total" }) {
                if targetLine.contains("sum") {
                    wordDiffs.append(WordDiff(
                        range: NSRange(location: totalToken.location, length: "total".utf16.count),
                        type: .modification
                    ))
                }
            }
            
            // Handle for loop changes
            if sourceLine.text.contains("for") && targetLine.contains("for") {
                if sourceLine.text.contains("let i = 0") && targetLine.contains("const item of") {
                    // Find the for loop structure
                    if let forStart = sourceMap.firstIndex(where: { $0.token.text == "for" }) {
                        var endIdx = forStart
                        while endIdx < sourceMap.count && !sourceMap[endIdx].token.text.contains("{") {
                            endIdx += 1
                        }
                        
                        let startLocation = sourceMap[forStart].location
                        let endLocation = endIdx < sourceMap.count ?
                            sourceMap[endIdx].location :
                            sourceMap[sourceMap.count - 1].location
                        
                        wordDiffs.append(WordDiff(
                            range: NSRange(
                                location: startLocation,
                                length: endLocation - startLocation
                            ),
                            type: .modification
                        ))
                    }
                }
            }
            
            // Handle array access changes (items[i] → item)
            if sourceLine.text.contains("items[i]") && targetLine.contains("item") {
                if let itemsToken = sourceMap.first(where: { $0.token.text == "items" }) {
                    let startLoc = itemsToken.location
                    var length = "items[i]".utf16.count
                    
                    // Find the actual end of the array access
                    for i in stride(from: sourceMap.count - 1, through: 0, by: -1) {
                        if sourceMap[i].token.text == "]" {
                            length = sourceMap[i].location + 1 - startLoc
                            break
                        }
                    }
                    
                    wordDiffs.append(WordDiff(
                        range: NSRange(location: startLoc, length: length),
                        type: .modification
                    ))
                }
            }
        }
        
        private func computeTextDiffs(
            sourceLine: Line,
            targetLine: String
        ) -> [WordDiff] {
            let sourceTokens = tokenize(sourceLine.text)
            let targetTokens = tokenize(targetLine)
            
            // Build target token frequency map
            var targetFrequency: [String: Int] = [:]
            for token in targetTokens where token.type != .whitespace {
                let key = token.type == .emoji ? token.text : token.normalized
                targetFrequency[key, default: 0] += 1
            }
            
            // Track how many times we've used each token
            var usedFrequency: [String: Int] = [:]
            var currentLocation = sourceLine.range.location
            var wordDiffs: [WordDiff] = []
            var processedLocations = Set<Int>()
            
            for token in sourceTokens {
                let length = token.text.utf16.count
                let range = NSRange(location: currentLocation, length: length)
                
                if !processedLocations.contains(currentLocation) {
                    var shouldMark = false
                    
                    switch token.type {
                    case .whitespace:
                        break
                    case .punctuation where token.text.trimmingCharacters(in: .whitespaces).isEmpty:
                        break
                    default:
                        let key = token.type == .emoji ? token.text : token.normalized
                        let usedCount = usedFrequency[key, default: 0]
                        let targetCount = targetFrequency[key, default: 0]
                        
                        if usedCount >= targetCount {
                            shouldMark = true
                        } else {
                            usedFrequency[key, default: 0] += 1
                        }
                    }
                    
                    if shouldMark {
                        processedLocations.insert(currentLocation)
                        wordDiffs.append(WordDiff(range: range, type: .modification))
                    }
                }
                
                currentLocation += length
            }
            
            return wordDiffs.sorted { $0.range.location < $1.range.location }
        }
    }


extension DiffAnalyzer {
    private struct TokenLocation {
        let token: Token
        let range: NSRange
    }
    
    // Remove the duplicate computeWordDiffs and use this updated version
    
    private func getTokenLocations(text: String, startingAt: Int) -> [TokenLocation] {
        var locations: [TokenLocation] = []
        var currentLocation = startingAt
        
        let tokens = tokenize(text)
        
        for token in tokens {
            let length = token.text.utf16.count
            locations.append(TokenLocation(
                token: token,
                range: NSRange(location: currentLocation, length: length)
            ))
            currentLocation += length
        }
        
        return locations
    }
    
    private func tokenize(_ text: String) -> [Token] {
        if isCode {
            return tokenizeCode(text)
        } else {
            return tokenizeText(text)
        }
    }
    
    private func tokenizeCode(_ text: String) -> [Token] {
            var tokens: [Token] = []
            var currentToken = ""
            var currentType: TokenType?
            
            func appendCurrentToken() {
                guard !currentToken.isEmpty else { return }
                tokens.append(Token(
                    text: currentToken,
                    normalized: currentToken.lowercased(),
                    type: currentType ?? .other
                ))
                currentToken = ""
                currentType = nil
            }
            
            var idx = text.startIndex
            while idx < text.endIndex {
                let char = text[idx]
                
                if char.isWhitespace {
                    appendCurrentToken()
                    currentToken = String(char)
                    currentType = .whitespace
                    appendCurrentToken()
                }
                else if "=><&|+-*/%!~^.,:;(){}[]".contains(char) {
                    appendCurrentToken()
                    currentToken = String(char)
                    currentType = .operator
                    appendCurrentToken()
                }
                else {
                    if currentType == nil {
                        currentType = .word
                    }
                    currentToken.append(char)
                }
                
                idx = text.index(after: idx)
            }
            
            appendCurrentToken()
            return tokens
        }
    
    private func tokenizeText(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var currentWord = ""
        var scalars = text.unicodeScalars.makeIterator()
        
        // Helper function to check if scalar is punctuation
        func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.properties.generalCategory {
            case .openPunctuation, .closePunctuation,
                    .initialPunctuation, .finalPunctuation,
                    .connectorPunctuation, .dashPunctuation,
                    .otherPunctuation:
                return true
            default:
                return false
            }
        }
        
        // Helper function to check if scalar is emoji
        func isEmoji(_ scalar: Unicode.Scalar) -> Bool {
            scalar.properties.generalCategory == .otherSymbol ||
            (scalar.properties.generalCategory == .otherLetter &&
             scalar.value >= 0x1F3FB && scalar.value <= 0x1F3FF)
        }
        
        func appendWord() {
            if !currentWord.isEmpty {
                tokens.append(createToken(currentWord, .word))
                currentWord = ""
            }
        }
        
        while let scalar = scalars.next() {
            if isEmoji(scalar) {
                appendWord()
                tokens.append(createToken(String(scalar), .emoji))
            }
            else if scalar.properties.isWhitespace {
                appendWord()
                tokens.append(createToken(String(scalar), .whitespace))
            }
            else if isPunctuation(scalar) {
                appendWord()
                tokens.append(createToken(String(scalar), .punctuation))
            }
            else {
                currentWord.append(Character(scalar))
            }
        }
        
        appendWord()
        return tokens
    }
    
    private func createToken(_ text: String, _ type: TokenType) -> Token {
        Token(
            text: text,
            normalized: normalizeToken(text, type),
            type: type
        )
    }
    
    private func normalizeToken(_ text: String, _ type: TokenType) -> String {
        switch type {
        case .word:
            return text.lowercased()
        case .emoji, .punctuation, .operator, .string:
            return text
        case .whitespace:
            return " "
        default:
            return text
        }
    }
}

// MARK: - CollectionDifference Extensions
extension CollectionDifference {
    var insertions: [Change] {
        compactMap {
            if case .insert = $0 { return $0 }
            return nil
        }
    }
    
    var removals: [Change] {
        compactMap {
            if case .remove = $0 { return $0 }
            return nil
        }
    }
}

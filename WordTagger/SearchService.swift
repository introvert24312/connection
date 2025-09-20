import Foundation
import Combine
import CoreLocation

public final class SearchService: ObservableObject {
    @Published public private(set) var isSearching = false
    @Published public private(set) var lastSearchTime: TimeInterval = 0
    
    private let searchThreshold: Double = 0.3
    private let maxResults: Int = 100
    
    // MARK: - Search Debouncing
    private var searchDebouncer: Timer?
    private let debounceDelay: TimeInterval = 0.2
    
    // MARK: - Search Result Caching
    private var searchCache: [String: CachedSearchResult] = [:]
    private let cacheExpirationTime: TimeInterval = 300 // 5分钟
    private let maxCacheSize: Int = 50 // 最多缓存50个查询结果
    
    public static let shared = SearchService()
    
    private init() {
        // 定期清理过期缓存
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.cleanExpiredCache()
        }
    }
    
    // MARK: - Public Search Interface
    
    /// 带防抖的搜索入口 - 推荐使用此方法
    public func debouncedSearch(_ query: String, in nodes: [Node], filter: SearchFilter = SearchFilter()) async -> [SearchResult] {
        return await withCheckedContinuation { continuation in
            // 取消之前的防抖计时器
            searchDebouncer?.invalidate()
            
            // 如果查询为空，立即返回空结果
            guard !query.isEmpty else {
                continuation.resume(returning: [])
                return
            }
            
            // 设置新的防抖计时器
            searchDebouncer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { _ in
                Task {
                    let results = await self.searchWithCache(query, in: nodes, filter: filter)
                    continuation.resume(returning: results)
                }
            }
        }
    }
    
    /// 带缓存的搜索方法
    private func searchWithCache(_ query: String, in nodes: [Node], filter: SearchFilter = SearchFilter()) async -> [SearchResult] {
        let cacheKey = generateCacheKey(query: query, filter: filter, nodeCount: nodes.count)
        
        // 检查缓存
        if let cachedResult = searchCache[cacheKey],
           !cachedResult.isExpired {
            print("🔍 SearchService: 使用缓存结果 - '\(query)' (\(cachedResult.results.count) 结果)")
            return cachedResult.results
        }
        
        // 执行搜索
        let results = await search(query, in: nodes, filter: filter)
        
        // 缓存结果
        cacheSearchResult(key: cacheKey, results: results)
        
        return results
    }
    
    // MARK: - Core Search Methods
    
    public func search(_ query: String, in nodes: [Node], filter: SearchFilter = SearchFilter()) async -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        await MainActor.run {
            isSearching = true
        }
        
        defer {
            Task { @MainActor in
                isSearching = false
                lastSearchTime = CFAbsoluteTimeGetCurrent() - startTime
            }
        }
        
        var filteredNodes = nodes
        
        // Apply filters first
        if let tagType = filter.tagType {
            filteredNodes = filteredNodes.filter { node in
                node.tags.contains { $0.type == tagType }
            }
        }
        
        if let hasLocation = filter.hasLocation {
            filteredNodes = filteredNodes.filter { node in
                let hasLocationTags = !node.locationTags.isEmpty
                return hasLocationTags == hasLocation
            }
        }
        
        // Perform search
        return await performAdvancedSearch(query, in: filteredNodes)
    }
    
    // MARK: - Advanced Search Implementation
    
    private func performAdvancedSearch(_ query: String, in nodes: [Node]) async -> [SearchResult] {
        let searchTerms = preprocessQuery(query)
        var results: [SearchResult] = []
        
        for node in nodes {
            if let result = await evaluateNode(node, against: searchTerms) {
                results.append(result)
            }
        }
        
        // Sort by relevance score and limit results
        let sortedResults = results.sorted { $0.score > $1.score }
        let limitedResults = Array(sortedResults.prefix(maxResults))
        return limitedResults
    }
    
    private func evaluateNode(_ node: Node, against searchTerms: [String]) async -> SearchResult? {
        var totalScore: Double = 0
        var matchedFields: Set<SearchResult.MatchField> = []
        var fieldMatches: [SearchResult.MatchField: Double] = [:]
        
        // Search in node text (highest weight)
        if let score = calculateFieldScore(node.text, against: searchTerms, weight: 3.0) {
            fieldMatches[.text] = score
            matchedFields.insert(.text)
            totalScore += score
        }
        
        // Search in meaning (high weight)
        if let meaning = node.meaning,
           let score = calculateFieldScore(meaning, against: searchTerms, weight: 2.5) {
            fieldMatches[.meaning] = score
            matchedFields.insert(.meaning)
            totalScore += score
        }
        
        // Search in markdown content (high weight)
        if !node.markdown.isEmpty,
           let score = calculateFieldScore(node.markdown, against: searchTerms, weight: 2.0) {
            fieldMatches[.markdown] = score
            matchedFields.insert(.markdown)
            totalScore += score
        }
        
        // Search in phonetic (medium weight)
        if let phonetic = node.phonetic,
           let score = calculateFieldScore(phonetic, against: searchTerms, weight: 1.5) {
            fieldMatches[.phonetic] = score
            matchedFields.insert(.phonetic)
            totalScore += score
        }
        
        // Search in tag values, tag codes (rawValue), and tag display names (medium weight)
        var tagScore: Double = 0
        for tag in node.tags {
            // Search in tag value
            if let score = calculateFieldScore(tag.value, against: searchTerms, weight: 1.8) {
                tagScore = max(tagScore, score)
            }
            
            // Search in tag code (rawValue) - the shortcut key like "dmub"
            if let score = calculateFieldScore(tag.type.rawValue, against: searchTerms, weight: 2.0) {
                tagScore = max(tagScore, score)
            }
            
            // Search in tag display name - the mapped name like "恶心"
            if let score = calculateFieldScore(tag.type.displayName, against: searchTerms, weight: 1.9) {
                tagScore = max(tagScore, score)
            }
        }
        if tagScore > 0 {
            fieldMatches[.tagValue] = tagScore
            matchedFields.insert(.tagValue)
            totalScore += tagScore
        }
        
        // Only return results above threshold
        guard !matchedFields.isEmpty && totalScore >= searchThreshold else { return nil }
        
        // Calculate final weighted score
        let finalScore = calculateFinalScore(fieldMatches)
        
        // Return the original node to preserve identity and references
        return SearchResult(node: node, score: finalScore, matchedFields: matchedFields)
    }
    
    // MARK: - Scoring Algorithms
    
    private func calculateFieldScore(_ text: String, against searchTerms: [String], weight: Double) -> Double? {
        let normalizedText = text.lowercased()
        var bestScore: Double = 0
        
        for term in searchTerms {
            let termScore = calculateTermScore(normalizedText, term: term)
            bestScore = max(bestScore, termScore)
        }
        
        return bestScore > 0 ? bestScore * weight : nil
    }
    
    private func calculateTermScore(_ text: String, term: String) -> Double {
        let normalizedTerm = term.lowercased()
        
        // Exact match
        if text == normalizedTerm {
            return 1.0
        }
        
        // Prefix match
        if text.hasPrefix(normalizedTerm) {
            return 0.9
        }
        
        // Contains match
        if text.contains(normalizedTerm) {
            return 0.7
        }
        
        // Fuzzy match using similarity
        let similarity = text.similarity(to: normalizedTerm)
        return similarity > 0.6 ? similarity * 0.8 : 0
    }
    
    private func calculateFinalScore(_ fieldMatches: [SearchResult.MatchField: Double]) -> Double {
        guard !fieldMatches.isEmpty else { return 0 }
        
        let totalScore = fieldMatches.values.reduce(0, +)
        let fieldCount = Double(fieldMatches.count)
        
        // Boost score for multiple field matches
        let multiFieldBonus = fieldCount > 1 ? 1.0 + (fieldCount - 1) * 0.1 : 1.0
        
        return (totalScore / fieldCount) * multiFieldBonus
    }
    
    // MARK: - Query Preprocessing
    
    private func preprocessQuery(_ query: String) -> [String] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Split by whitespace and filter out empty terms
        let terms = cleanQuery.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        
        return Array(Set(terms)) // Remove duplicates
    }
    
    // MARK: - Specialized Search Methods
    
    public func searchByTag(_ tagType: Tag.TagType, in nodes: [Node]) -> [Node] {
        return nodes.filter { node in
            node.tags.contains { $0.type == tagType }
        }
    }
    
    public func searchByLocation(near coordinate: CLLocationCoordinate2D, 
                               radius: Double, 
                               in nodes: [Node]) -> [Node] {
        return nodes.filter { node in
            node.locationTags.contains { tag in
                guard let lat = tag.latitude, let lng = tag.longitude else { return false }
                let tagCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                return coordinate.distance(to: tagCoordinate) <= radius
            }
        }
    }
    
    public func findSimilarNodes(_ node: Node, in nodes: [Node], threshold: Double = 0.7) -> [Node] {
        return nodes.compactMap { candidate in
            guard candidate.id != node.id else { return nil }
            
            let textSimilarity = node.text.similarity(to: candidate.text)
            let meaningSimilarity = node.meaning?.similarity(to: candidate.meaning ?? "") ?? 0
            
            let overallSimilarity = (textSimilarity + meaningSimilarity) / 2.0
            
            return overallSimilarity >= threshold ? candidate : nil
        }
    }
    
    // MARK: - Performance Metrics
    
    public var searchMetrics: SearchMetrics {
        SearchMetrics(
            lastSearchTime: lastSearchTime,
            isSearching: isSearching,
            searchThreshold: searchThreshold,
            maxResults: maxResults,
            cacheHitRate: calculateCacheHitRate(),
            cacheSize: searchCache.count
        )
    }
    
    // MARK: - Cache Management
    
    private func generateCacheKey(query: String, filter: SearchFilter, nodeCount: Int) -> String {
        let filterHash = "\(filter.tagType?.rawValue ?? "nil")_\(filter.hasLocation?.description ?? "nil")"
        return "\(query.lowercased())_\(filterHash)_\(nodeCount)"
    }
    
    private func cacheSearchResult(key: String, results: [SearchResult]) {
        // 如果缓存已满，移除最旧的条目
        if searchCache.count >= maxCacheSize {
            removeOldestCacheEntry()
        }
        
        searchCache[key] = CachedSearchResult(
            results: results,
            timestamp: Date(),
            expirationTime: cacheExpirationTime
        )
        
        print("🔍 SearchService: 缓存搜索结果 - '\(key)' (\(results.count) 结果)")
    }
    
    private func cleanExpiredCache() {
        let now = Date()
        let expiredKeys = searchCache.compactMap { key, cachedResult in
            cachedResult.timestamp.addingTimeInterval(cacheExpirationTime) < now ? key : nil
        }
        
        for key in expiredKeys {
            searchCache.removeValue(forKey: key)
        }
        
        if !expiredKeys.isEmpty {
            print("🧹 SearchService: 清理过期缓存条目 \(expiredKeys.count) 个")
        }
    }
    
    private func removeOldestCacheEntry() {
        guard let oldestKey = searchCache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key else {
            return
        }
        searchCache.removeValue(forKey: oldestKey)
        print("🗑️ SearchService: 移除最旧缓存条目")
    }
    
    private func calculateCacheHitRate() -> Double {
        // 这里可以添加缓存命中统计，暂时返回0
        return 0.0
    }
    
    /// 清空搜索缓存
    public func clearSearchCache() {
        searchCache.removeAll()
        print("🧹 SearchService: 清空所有搜索缓存")
    }
    
    /// 取消当前的防抖计时器
    public func cancelDebounce() {
        searchDebouncer?.invalidate()
        searchDebouncer = nil
    }
}

// MARK: - Cache Data Structure

private struct CachedSearchResult {
    let results: [SearchResult]
    let timestamp: Date
    let expirationTime: TimeInterval
    
    var isExpired: Bool {
        return Date().timeIntervalSince(timestamp) > expirationTime
    }
}

// MARK: - Search Metrics

public struct SearchMetrics {
    public let lastSearchTime: TimeInterval
    public let isSearching: Bool
    public let searchThreshold: Double
    public let maxResults: Int
    public let cacheHitRate: Double
    public let cacheSize: Int
    
    public var lastSearchTimeFormatted: String {
        return String(format: "%.2f ms", lastSearchTime * 1000)
    }
    
    public var cacheHitRateFormatted: String {
        return String(format: "%.1f%%", cacheHitRate * 100)
    }
}

// MARK: - CLLocationCoordinate2D Distance Extension

extension CLLocationCoordinate2D {
    func distance(to coordinate: CLLocationCoordinate2D) -> Double {
        let earthRadius = 6371000.0 // meters
        
        let lat1Rad = latitude * .pi / 180
        let lat2Rad = coordinate.latitude * .pi / 180
        let deltaLatRad = (coordinate.latitude - latitude) * .pi / 180
        let deltaLngRad = (coordinate.longitude - longitude) * .pi / 180
        
        let a = sin(deltaLatRad/2) * sin(deltaLatRad/2) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(deltaLngRad/2) * sin(deltaLngRad/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        
        return earthRadius * c
    }
}

import Foundation
import Combine
import CoreLocation

public final class GraphService: ObservableObject {
    @Published public private(set) var graph: NodeGraph = NodeGraph()
    @Published public private(set) var isBuilding = false
    @Published public private(set) var lastBuildTime: TimeInterval = 0
    
    private let similarityThreshold: Double = 0.7
    private let maxConnections: Int = 10
    
    public static let shared = GraphService()
    
    private init() {}
    
    // MARK: - Graph Building
    
    public func buildGraph(from words: [Node]) async {
        await MainActor.run {
            isBuilding = true
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        defer {
            Task { @MainActor in
                isBuilding = false
                lastBuildTime = CFAbsoluteTimeGetCurrent() - startTime
            }
        }
        
        let newGraph = await performGraphBuilding(words: words)
        
        await MainActor.run {
            graph = newGraph
        }
    }
    
    private func performGraphBuilding(words: [Node]) async -> NodeGraph {
        var newGraph = NodeGraph()
        
        // Add all words as nodes
        for word in words {
            newGraph.addNode(word)
        }
        
        // Build edges based on different relationship types
        await buildSimilarityEdges(in: &newGraph, words: words)
        await buildTagRelationshipEdges(in: &newGraph, words: words)
        await buildRootNodeEdges(in: &newGraph, words: words)
        await buildLocationProximityEdges(in: &newGraph, words: words)
        
        return newGraph
    }
    
    // MARK: - Edge Building Methods
    
    private func buildSimilarityEdges(in graph: inout NodeGraph, words: [Node]) async {
        for i in 0..<words.count {
            for j in (i+1)..<words.count {
                let word1 = words[i]
                let word2 = words[j]
                
                let similarity = calculateSimilarity(between: word1, and: word2)
                
                if similarity >= similarityThreshold {
                    let edge = NodeEdge(
                        from: word1.id,
                        to: word2.id,
                        type: .similarity,
                        weight: similarity,
                        metadata: ["similarity_score": similarity]
                    )
                    graph.addEdge(edge)
                }
            }
        }
    }
    
    private func buildTagRelationshipEdges(in graph: inout NodeGraph, words: [Node]) async {
        let tagGroups = Dictionary(grouping: words) { word in
            word.tags.map { $0.type }
        }
        
        for (_, wordsWithTags) in tagGroups {
            guard wordsWithTags.count > 1 else { continue }
            
            for i in 0..<wordsWithTags.count {
                for j in (i+1)..<wordsWithTags.count {
                    let word1 = wordsWithTags[i]
                    let word2 = wordsWithTags[j]
                    
                    let sharedTags = Set(word1.tags.map { $0.type }).intersection(Set(word2.tags.map { $0.type }))
                    
                    if !sharedTags.isEmpty {
                        let weight = Double(sharedTags.count) / Double(max(word1.tags.count, word2.tags.count))
                        
                        let edge = NodeEdge(
                            from: word1.id,
                            to: word2.id,
                            type: .tagRelationship,
                            weight: weight,
                            metadata: [
                                "shared_tag_types": sharedTags.map { $0.rawValue },
                                "tag_overlap_ratio": weight
                            ]
                        )
                        graph.addEdge(edge)
                    }
                }
            }
        }
    }
    
    private func buildRootNodeEdges(in graph: inout NodeGraph, words: [Node]) async {
        let rootNodes = words.filter { word in
            word.tags.contains { tag in
                if case .custom(let key) = tag.type, key == "root" {
                    return true
                }
                return false
            }
        }
        
        let rootGroups = Dictionary(grouping: rootNodes) { word in
            word.tags.compactMap { tag in
                if case .custom(let key) = tag.type, key == "root" {
                    return tag.value
                }
                return nil
            }
        }
        
        for (rootValues, wordsWithRoot) in rootGroups {
            guard wordsWithRoot.count > 1 else { continue }
            
            for i in 0..<wordsWithRoot.count {
                for j in (i+1)..<wordsWithRoot.count {
                    let word1 = wordsWithRoot[i]
                    let word2 = wordsWithRoot[j]
                    
                    let edge = NodeEdge(
                        from: word1.id,
                        to: word2.id,
                        type: .rootNode,
                        weight: 0.9,
                        metadata: [
                            "shared_roots": rootValues,
                            "relationship_type": "root_word"
                        ]
                    )
                    graph.addEdge(edge)
                }
            }
        }
    }
    
    private func buildLocationProximityEdges(in graph: inout NodeGraph, words: [Node]) async {
        let locationNodes = words.filter { !$0.locationTags.isEmpty }
        
        for i in 0..<locationNodes.count {
            for j in (i+1)..<locationNodes.count {
                let word1 = locationNodes[i]
                let word2 = locationNodes[j]
                
                if let proximity = calculateLocationProximity(between: word1, and: word2) {
                    let edge = NodeEdge(
                        from: word1.id,
                        to: word2.id,
                        type: .locationProximity,
                        weight: proximity,
                        metadata: [
                            "proximity_score": proximity,
                            "relationship_type": "location_proximity"
                        ]
                    )
                    graph.addEdge(edge)
                }
            }
        }
    }
    
    // MARK: - Similarity Calculation
    
    private func calculateSimilarity(between word1: Node, and word2: Node) -> Double {
        var totalSimilarity: Double = 0
        var factors: Int = 0
        
        // Text similarity (highest weight)
        let textSimilarity = word1.text.similarity(to: word2.text)
        if textSimilarity > 0.3 {
            totalSimilarity += textSimilarity * 3.0
            factors += 3
        }
        
        // Meaning similarity
        if let meaning1 = word1.meaning, let meaning2 = word2.meaning {
            let meaningSimilarity = meaning1.similarity(to: meaning2)
            if meaningSimilarity > 0.3 {
                totalSimilarity += meaningSimilarity * 2.0
                factors += 2
            }
        }
        
        // Phonetic similarity
        if let phonetic1 = word1.phonetic, let phonetic2 = word2.phonetic {
            let phoneticSimilarity = phonetic1.similarity(to: phonetic2)
            if phoneticSimilarity > 0.3 {
                totalSimilarity += phoneticSimilarity * 1.5
                factors += 1
            }
        }
        
        return factors > 0 ? totalSimilarity / Double(factors) : 0
    }
    
    private func calculateLocationProximity(between word1: Node, and word2: Node) -> Double? {
        guard let coord1 = word1.locationTags.first?.coordinate,
              let coord2 = word2.locationTags.first?.coordinate else {
            return nil
        }
        
        let distance = coord1.distance(to: coord2)
        
        // Convert distance to proximity score (closer = higher score)
        // Max meaningful distance: 10000m (10km)
        let maxDistance: Double = 10000
        let normalizedDistance = min(distance, maxDistance) / maxDistance
        
        return 1.0 - normalizedDistance
    }
    
    // MARK: - Graph Query Methods
    
    public func neighbors(of wordId: UUID) -> [Node] {
        return graph.neighbors(of: wordId)
    }
    
    public func connectedNodes(to wordId: UUID, maxDepth: Int = 2) -> [Node] {
        return graph.connectedNodes(to: wordId, maxDepth: maxDepth)
    }
    
    public func findPath(from: UUID, to: UUID) -> [Node]? {
        return graph.findPath(from: from, to: to)
    }
    
    public func strongestConnections(for wordId: UUID, limit: Int = 5) -> [(Node, Double)] {
        return graph.strongestConnections(for: wordId, limit: limit)
    }
    
    public func clusterNodes(minClusterSize: Int = 3) -> [[Node]] {
        return graph.findClusters(minSize: minClusterSize)
    }
    
    // MARK: - Graph Statistics
    
    public var graphStats: GraphStatistics {
        return graph.statistics
    }
    
    // MARK: - Export for Visualization
    
    public func exportForVisualization(includeEdgeTypes: Set<EdgeType> = Set(EdgeType.allCases)) -> GraphVisualizationData {
        return graph.exportForVisualization(includeEdgeTypes: includeEdgeTypes)
    }
}

// MARK: - Graph Data Structures

public struct NodeGraph {
    private var nodes: [UUID: Node] = [:]
    private var edges: [UUID: [NodeEdge]] = [:]
    private var reverseEdges: [UUID: [NodeEdge]] = [:]
    
    public mutating func addNode(_ word: Node) {
        nodes[word.id] = word
        if edges[word.id] == nil {
            edges[word.id] = []
        }
        if reverseEdges[word.id] == nil {
            reverseEdges[word.id] = []
        }
    }
    
    public mutating func addEdge(_ edge: NodeEdge) {
        edges[edge.from, default: []].append(edge)
        reverseEdges[edge.to, default: []].append(edge)
    }
    
    public func neighbors(of wordId: UUID) -> [Node] {
        let outgoingEdges = edges[wordId, default: []]
        let incomingEdges = reverseEdges[wordId, default: []]
        
        var neighborIds = Set<UUID>()
        neighborIds.formUnion(outgoingEdges.map { $0.to })
        neighborIds.formUnion(incomingEdges.map { $0.from })
        
        return neighborIds.compactMap { nodes[$0] }
    }
    
    public func connectedNodes(to wordId: UUID, maxDepth: Int) -> [Node] {
        var visited = Set<UUID>()
        var result = [Node]()
        
        func dfs(_ currentId: UUID, depth: Int) {
            guard depth <= maxDepth, !visited.contains(currentId) else { return }
            
            visited.insert(currentId)
            
            if let word = nodes[currentId], depth > 0 {
                result.append(word)
            }
            
            for neighbor in neighbors(of: currentId) {
                dfs(neighbor.id, depth: depth + 1)
            }
        }
        
        dfs(wordId, depth: 0)
        return result
    }
    
    public func findPath(from: UUID, to: UUID) -> [Node]? {
        var visited = Set<UUID>()
        var path = [UUID]()
        
        func dfs(_ currentId: UUID) -> Bool {
            guard !visited.contains(currentId) else { return false }
            
            visited.insert(currentId)
            path.append(currentId)
            
            if currentId == to {
                return true
            }
            
            for neighbor in neighbors(of: currentId) {
                if dfs(neighbor.id) {
                    return true
                }
            }
            
            path.removeLast()
            return false
        }
        
        guard dfs(from) else { return nil }
        return path.compactMap { nodes[$0] }
    }
    
    public func strongestConnections(for wordId: UUID, limit: Int) -> [(Node, Double)] {
        let outgoingEdges = edges[wordId, default: []]
        let incomingEdges = reverseEdges[wordId, default: []]
        
        var connections: [(UUID, Double)] = []
        
        for edge in outgoingEdges {
            connections.append((edge.to, edge.weight))
        }
        
        for edge in incomingEdges {
            connections.append((edge.from, edge.weight))
        }
        
        return connections
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .compactMap { (id, weight) in
                guard let word = nodes[id] else { return nil }
                return (word, weight)
            }
    }
    
    public func findClusters(minSize: Int) -> [[Node]] {
        var visited = Set<UUID>()
        var clusters: [[Node]] = []
        
        for wordId in nodes.keys {
            guard !visited.contains(wordId) else { continue }
            
            var cluster = [Node]()
            var queue = [wordId]
            
            while !queue.isEmpty {
                let currentId = queue.removeFirst()
                guard !visited.contains(currentId) else { continue }
                
                visited.insert(currentId)
                
                if let word = nodes[currentId] {
                    cluster.append(word)
                }
                
                for neighbor in neighbors(of: currentId) {
                    if !visited.contains(neighbor.id) {
                        queue.append(neighbor.id)
                    }
                }
            }
            
            if cluster.count >= minSize {
                clusters.append(cluster)
            }
        }
        
        return clusters
    }
    
    public var statistics: GraphStatistics {
        let nodeCount = nodes.count
        let edgeCount = edges.values.flatMap { $0 }.count
        let avgDegree = nodeCount > 0 ? Double(edgeCount * 2) / Double(nodeCount) : 0
        
        let edgeTypeDistribution = edges.values
            .flatMap { $0 }
            .reduce(into: [EdgeType: Int]()) { result, edge in
                result[edge.type, default: 0] += 1
            }
        
        return GraphStatistics(
            nodeCount: nodeCount,
            edgeCount: edgeCount,
            averageDegree: avgDegree,
            edgeTypeDistribution: edgeTypeDistribution
        )
    }
    
    public func exportForVisualization(includeEdgeTypes: Set<EdgeType>) -> GraphVisualizationData {
        let nodeData = nodes.values.map { word in
            GraphNode(
                id: word.id.uuidString,
                label: word.text,
                group: word.tags.first?.type.rawValue ?? "unknown",
                metadata: [
                    "phonetic": word.phonetic ?? "",
                    "meaning": word.meaning ?? "",
                    "tagCount": word.tags.count
                ]
            )
        }
        
        let edgeData = edges.values
            .flatMap { $0 }
            .filter { includeEdgeTypes.contains($0.type) }
            .map { edge in
                GraphEdge(
                    from: edge.from.uuidString,
                    to: edge.to.uuidString,
                    weight: edge.weight,
                    type: edge.type.rawValue,
                    metadata: edge.metadata
                )
            }
        
        return GraphVisualizationData(nodes: nodeData, edges: edgeData)
    }
}

public struct NodeEdge {
    public let from: UUID
    public let to: UUID
    public let type: EdgeType
    public let weight: Double
    public let metadata: [String: Any]
    
    public init(from: UUID, to: UUID, type: EdgeType, weight: Double, metadata: [String: Any] = [:]) {
        self.from = from
        self.to = to
        self.type = type
        self.weight = weight
        self.metadata = metadata
    }
}

public enum EdgeType: String, CaseIterable {
    case similarity = "similarity"
    case tagRelationship = "tag_relationship"
    case rootNode = "root_word"
    case locationProximity = "location_proximity"
    case custom = "custom"
}

public struct GraphStatistics {
    public let nodeCount: Int
    public let edgeCount: Int
    public let averageDegree: Double
    public let edgeTypeDistribution: [EdgeType: Int]
    
    public init(nodeCount: Int, edgeCount: Int, averageDegree: Double, edgeTypeDistribution: [EdgeType: Int]) {
        self.nodeCount = nodeCount
        self.edgeCount = edgeCount
        self.averageDegree = averageDegree
        self.edgeTypeDistribution = edgeTypeDistribution
    }
}

public struct GraphVisualizationData: Codable {
    public let nodes: [GraphNode]
    public let edges: [GraphEdge]
    
    public init(nodes: [GraphNode], edges: [GraphEdge]) {
        self.nodes = nodes
        self.edges = edges
    }
}

public struct GraphNode: Codable {
    public let id: String
    public let label: String
    public let group: String
    public let metadata: [String: AnyCodable]
    
    public init(id: String, label: String, group: String, metadata: [String: Any]) {
        self.id = id
        self.label = label
        self.group = group
        self.metadata = metadata.mapValues { AnyCodable($0) }
    }
}

public struct GraphEdge: Codable {
    public let from: String
    public let to: String
    public let weight: Double
    public let type: String
    public let metadata: [String: AnyCodable]
    
    public init(from: String, to: String, weight: Double, type: String, metadata: [String: Any]) {
        self.from = from
        self.to = to
        self.weight = weight
        self.type = type
        self.metadata = metadata.mapValues { AnyCodable($0) }
    }
}

public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        default:
            try container.encode(String(describing: value))
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else {
            value = ""
        }
    }
}

// MARK: - Coordinate Extensions

extension Tag {
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
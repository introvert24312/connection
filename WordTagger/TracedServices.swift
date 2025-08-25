import Foundation
import Combine

// MARK: - Traced SearchService Extensions

extension SearchService {
    
    /// Perform advanced search with comprehensive tracing
    func searchTraced(
        query: String,
        in nodes: [Node],
        context: TraceContext? = nil
    ) async -> [Node] {
        return await TracingService.shared.traced(
            "SearchService.search",
            parentContext: context,
            tags: [
                "service": "SearchService",
                "operation_type": "advanced_search",
                "query": query,
                "query_length": String(query.count),
                "nodes_count": String(nodes.count)
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            logger.info("Starting advanced search", context: traceContext, fields: [
                "query": query,
                "search_scope_nodes": String(nodes.count)
            ])
            
            guard !query.isEmpty else {
                logger.debug("Empty query, returning empty results", context: traceContext)
                return []
            }
            
            let searchStartTime = Date()
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Tokenize query for better matching
            let queryContext = TracingService.shared.startSpan(
                "SearchService.queryAnalysis",
                parentContext: traceContext,
                tags: ["analysis_type": "tokenization"]
            )
            
            let queryTokens = tokenizeQuery(trimmedQuery)
            TracingService.shared.finishSpan(queryContext, outcome: .success, metrics: [
                "tokens_count": Double(queryTokens.count)
            ])
            
            logger.debug("Query tokenized", context: traceContext, fields: [
                "tokens": queryTokens.joined(separator: ", "),
                "tokens_count": String(queryTokens.count)
            ])
            
            // Perform search with different strategies
            let strategies: [(String, (String, [Node]) -> [SearchResult])] = [
                ("exact_match", exactMatchSearch),
                ("fuzzy_match", fuzzyMatchSearch),
                ("semantic_match", semanticMatchSearch),
                ("tag_match", tagMatchSearch)
            ]
            
            var allResults: [SearchResult] = []
            
            for (strategyName, strategy) in strategies {
                let strategyContext = TracingService.shared.startSpan(
                    "SearchService.\(strategyName)",
                    parentContext: traceContext,
                    tags: ["strategy": strategyName]
                )
                
                let strategyResults = strategy(trimmedQuery, nodes)
                allResults.append(contentsOf: strategyResults)
                
                TracingService.shared.finishSpan(strategyContext, outcome: .success, metrics: [
                    "results_found": Double(strategyResults.count)
                ])
                
                logger.debug("Search strategy completed", context: traceContext, fields: [
                    "strategy": strategyName,
                    "results_found": String(strategyResults.count)
                ])
            }
            
            // Deduplicate and rank results
            let rankingContext = TracingService.shared.startSpan(
                "SearchService.rankResults",
                parentContext: traceContext,
                tags: ["ranking_type": "relevance_scoring"]
            )
            
            let rankedResults = rankAndDeduplicateResults(allResults)
            let finalNodes = rankedResults.map { $0.node }
            
            TracingService.shared.finishSpan(rankingContext, outcome: .success, metrics: [
                "raw_results": Double(allResults.count),
                "final_results": Double(finalNodes.count)
            ])
            
            let searchDuration = Date().timeIntervalSince(searchStartTime)
            
            logger.info("Search completed", context: traceContext, fields: [
                "final_results_count": String(finalNodes.count),
                "search_duration_ms": String(format: "%.2f", searchDuration * 1000),
                "deduplication_rate": String(format: "%.1f%%", (1.0 - Double(finalNodes.count) / Double(max(allResults.count, 1))) * 100)
            ])
            
            // Record search performance metric
            TracingService.shared.recordMetric(
                PerformanceMetrics(
                    operationName: "SearchService.search",
                    duration: searchDuration,
                    success: true,
                    tags: [
                        "query_length": String(query.count),
                        "results_count": String(finalNodes.count),
                        "search_scope": String(nodes.count)
                    ]
                )
            )
            
            return finalNodes
        }
    }
    
    private func tokenizeQuery(_ query: String) -> [String] {
        return query.components(separatedBy: .whitespacesAndNewlines)
                   .filter { !$0.isEmpty }
                   .map { $0.lowercased() }
    }
    
    private func exactMatchSearch(_ query: String, _ nodes: [Node]) -> [SearchResult] {
        return nodes.compactMap { node in
            let score: Double
            if node.text.lowercased() == query.lowercased() {
                score = 1.0
            } else if node.text.lowercased().contains(query.lowercased()) {
                score = 0.8
            } else if node.meaning?.lowercased().contains(query.lowercased()) == true {
                score = 0.7
            } else if node.phonetic?.lowercased().contains(query.lowercased()) == true {
                score = 0.6
            } else {
                return nil
            }
            
            return SearchResult(node: node, score: score, matchType: "exact")
        }
    }
    
    private func fuzzyMatchSearch(_ query: String, _ nodes: [Node]) -> [SearchResult] {
        return nodes.compactMap { node in
            let textScore = calculateFuzzyScore(query, node.text)
            let meaningScore = node.meaning.map { calculateFuzzyScore(query, $0) } ?? 0.0
            let phoneticScore = node.phonetic.map { calculateFuzzyScore(query, $0) } ?? 0.0
            
            let maxScore = max(textScore, meaningScore, phoneticScore)
            
            guard maxScore > 0.3 else { return nil }
            
            return SearchResult(node: node, score: maxScore * 0.8, matchType: "fuzzy")
        }
    }
    
    private func semanticMatchSearch(_ query: String, _ nodes: [Node]) -> [SearchResult] {
        return nodes.compactMap { node in
            let semanticScore = calculateSemanticScore(query, node)
            
            guard semanticScore > 0.2 else { return nil }
            
            return SearchResult(node: node, score: semanticScore * 0.6, matchType: "semantic")
        }
    }
    
    private func tagMatchSearch(_ query: String, _ nodes: [Node]) -> [SearchResult] {
        return nodes.compactMap { node in
            let tagMatches = node.tags.compactMap { tag -> Double? in
                if tag.value.localizedCaseInsensitiveContains(query) {
                    return tag.value.lowercased() == query.lowercased() ? 0.9 : 0.7
                }
                return nil
            }
            
            guard let maxTagScore = tagMatches.max() else { return nil }
            
            return SearchResult(node: node, score: maxTagScore * 0.9, matchType: "tag")
        }
    }
    
    private func calculateFuzzyScore(_ query: String, _ text: String) -> Double {
        let queryLower = query.lowercased()
        let textLower = text.lowercased()
        
        if textLower.contains(queryLower) {
            return Double(queryLower.count) / Double(textLower.count)
        }
        
        return 0.0
    }
    
    private func calculateSemanticScore(_ query: String, _ node: Node) -> Double {
        let queryWords = query.lowercased().components(separatedBy: .whitespaces)
        let nodeWords = (node.text + " " + (node.meaning ?? "")).lowercased().components(separatedBy: .whitespaces)
        
        let matches = queryWords.filter { queryWord in
            nodeWords.contains { nodeWord in
                nodeWord.contains(queryWord) || queryWord.contains(nodeWord)
            }
        }
        
        return Double(matches.count) / Double(queryWords.count)
    }
    
    private func rankAndDeduplicateResults(_ results: [SearchResult]) -> [SearchResult] {
        var uniqueResults: [UUID: SearchResult] = [:]
        
        for result in results {
            let nodeId = result.node.id
            if let existing = uniqueResults[nodeId] {
                // Keep result with higher score
                if result.score > existing.score {
                    uniqueResults[nodeId] = result
                }
            } else {
                uniqueResults[nodeId] = result
            }
        }
        
        return uniqueResults.values.sorted { $0.score > $1.score }
    }
}

private struct SearchResult {
    let node: Node
    let score: Double
    let matchType: String
}

// MARK: - Traced GraphService Extensions

extension GraphService {
    
    /// Generate graph data with comprehensive tracing
    func generateGraphDataTraced(
        for nodes: [Node],
        context: TraceContext? = nil
    ) async -> GraphData {
        return await TracingService.shared.traced(
            "GraphService.generateGraphData",
            parentContext: context,
            tags: [
                "service": "GraphService",
                "operation_type": "graph_generation",
                "nodes_count": String(nodes.count)
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            logger.info("Starting graph data generation", context: traceContext, fields: [
                "input_nodes": String(nodes.count)
            ])
            
            let generationStartTime = Date()
            
            // Analyze node relationships
            let relationshipContext = TracingService.shared.startSpan(
                "GraphService.analyzeRelationships",
                parentContext: traceContext,
                tags: ["analysis_type": "node_relationships"]
            )
            
            let relationships = await analyzeNodeRelationships(nodes, context: relationshipContext)
            
            TracingService.shared.finishSpan(relationshipContext, outcome: .success, metrics: [
                "relationships_found": Double(relationships.count)
            ])
            
            logger.debug("Node relationships analyzed", context: traceContext, fields: [
                "relationships_count": String(relationships.count)
            ])
            
            // Generate graph nodes
            let nodeGenerationContext = TracingService.shared.startSpan(
                "GraphService.generateGraphNodes",
                parentContext: traceContext,
                tags: ["generation_type": "graph_nodes"]
            )
            
            let graphNodes = nodes.map { node in
                GraphNode(
                    id: node.id.uuidString,
                    label: node.text,
                    group: determineNodeGroup(node),
                    metadata: createNodeMetadata(node)
                )
            }
            
            TracingService.shared.finishSpan(nodeGenerationContext, outcome: .success, metrics: [
                "graph_nodes_generated": Double(graphNodes.count)
            ])
            
            // Generate graph edges
            let edgeGenerationContext = TracingService.shared.startSpan(
                "GraphService.generateGraphEdges",
                parentContext: traceContext,
                tags: ["generation_type": "graph_edges"]
            )
            
            let graphEdges = relationships.map { relationship in
                GraphEdge(
                    from: relationship.sourceNode.id.uuidString,
                    to: relationship.targetNode.id.uuidString,
                    label: relationship.type.rawValue,
                    weight: relationship.strength
                )
            }
            
            TracingService.shared.finishSpan(edgeGenerationContext, outcome: .success, metrics: [
                "graph_edges_generated": Double(graphEdges.count)
            ])
            
            let generationDuration = Date().timeIntervalSince(generationStartTime)
            
            let graphData = GraphData(
                nodes: graphNodes,
                edges: graphEdges,
                metadata: GraphMetadata(
                    totalNodes: graphNodes.count,
                    totalEdges: graphEdges.count,
                    generationTime: generationDuration,
                    traceId: traceContext.traceId
                )
            )
            
            logger.info("Graph data generation completed", context: traceContext, fields: [
                "graph_nodes": String(graphNodes.count),
                "graph_edges": String(graphEdges.count),
                "generation_duration_ms": String(format: "%.2f", generationDuration * 1000)
            ])
            
            // Record performance metric
            TracingService.shared.recordMetric(
                PerformanceMetrics(
                    operationName: "GraphService.generateGraphData",
                    duration: generationDuration,
                    success: true,
                    tags: [
                        "nodes_count": String(nodes.count),
                        "relationships_count": String(relationships.count)
                    ]
                )
            )
            
            return graphData
        }
    }
    
    private func analyzeNodeRelationships(
        _ nodes: [Node],
        context: TraceContext
    ) async -> [NodeRelationship] {
        let logger = StructuredLogger.shared
        var relationships: [NodeRelationship] = []
        
        logger.debug("Analyzing relationships between nodes", context: context, fields: [
            "nodes_to_analyze": String(nodes.count)
        ])
        
        // Tag-based relationships
        let tagRelationshipContext = TracingService.shared.startSpan(
            "GraphService.tagRelationships",
            parentContext: context,
            tags: ["relationship_type": "tag_based"]
        )
        
        for node in nodes {
            for otherNode in nodes where otherNode.id != node.id {
                let sharedTags = Set(node.tags).intersection(Set(otherNode.tags))
                if !sharedTags.isEmpty {
                    let strength = calculateRelationshipStrength(basedOnSharedTags: sharedTags.count)
                    relationships.append(
                        NodeRelationship(
                            sourceNode: node,
                            targetNode: otherNode,
                            type: .tagSimilarity,
                            strength: strength
                        )
                    )
                }
            }
        }
        
        TracingService.shared.finishSpan(tagRelationshipContext, outcome: .success, metrics: [
            "tag_relationships": Double(relationships.count)
        ])
        
        // Semantic relationships
        let semanticRelationshipContext = TracingService.shared.startSpan(
            "GraphService.semanticRelationships",
            parentContext: context,
            tags: ["relationship_type": "semantic_based"]
        )
        
        let semanticRelationships = await analyzeSemanticRelationships(nodes)
        relationships.append(contentsOf: semanticRelationships)
        
        TracingService.shared.finishSpan(semanticRelationshipContext, outcome: .success, metrics: [
            "semantic_relationships": Double(semanticRelationships.count)
        ])
        
        logger.debug("Relationship analysis completed", context: context, fields: [
            "total_relationships": String(relationships.count)
        ])
        
        return relationships
    }
    
    private func analyzeSemanticRelationships(_ nodes: [Node]) async -> [NodeRelationship] {
        var relationships: [NodeRelationship] = []
        
        for node in nodes {
            for otherNode in nodes where otherNode.id != node.id {
                let similarity = calculateSemanticSimilarity(node, otherNode)
                if similarity > 0.3 {
                    relationships.append(
                        NodeRelationship(
                            sourceNode: node,
                            targetNode: otherNode,
                            type: .semanticSimilarity,
                            strength: similarity
                        )
                    )
                }
            }
        }
        
        return relationships
    }
    
    private func calculateRelationshipStrength(basedOnSharedTags count: Int) -> Double {
        return min(Double(count) * 0.2, 1.0)
    }
    
    private func calculateSemanticSimilarity(_ node1: Node, _ node2: Node) -> Double {
        let text1 = (node1.text + " " + (node1.meaning ?? "")).lowercased()
        let text2 = (node2.text + " " + (node2.meaning ?? "")).lowercased()
        
        let words1 = Set(text1.components(separatedBy: .whitespacesAndNewlines))
        let words2 = Set(text2.components(separatedBy: .whitespacesAndNewlines))
        
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        
        guard !union.isEmpty else { return 0.0 }
        
        return Double(intersection.count) / Double(union.count)
    }
    
    private func determineNodeGroup(_ node: Node) -> String {
        // Simple grouping logic based on tags
        if node.tags.contains(where: { $0.hasCoordinates }) {
            return "location"
        } else if node.isCompound {
            return "compound"
        } else if node.tags.count > 3 {
            return "rich"
        } else {
            return "basic"
        }
    }
    
    private func createNodeMetadata(_ node: Node) -> [String: Any] {
        return [
            "text": node.text,
            "phonetic": node.phonetic ?? "",
            "meaning": node.meaning ?? "",
            "tags_count": node.tags.count,
            "is_compound": node.isCompound,
            "created_at": node.createdAt.timeIntervalSince1970,
            "updated_at": node.updatedAt.timeIntervalSince1970
        ]
    }
}

// MARK: - Supporting Types

struct GraphData {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let metadata: GraphMetadata
}

struct GraphNode {
    let id: String
    let label: String
    let group: String
    let metadata: [String: Any]
}

struct GraphEdge {
    let from: String
    let to: String
    let label: String
    let weight: Double
}

struct GraphMetadata {
    let totalNodes: Int
    let totalEdges: Int
    let generationTime: TimeInterval
    let traceId: String
}

struct NodeRelationship {
    let sourceNode: Node
    let targetNode: Node
    let type: RelationshipType
    let strength: Double
}

enum RelationshipType: String {
    case tagSimilarity = "tag_similarity"
    case semanticSimilarity = "semantic_similarity"
    case locationProximity = "location_proximity"
    case compoundReference = "compound_reference"
}

// MARK: - Traced DataManager Extensions

extension DataManager {
    
    /// Import data with comprehensive tracing
    func importDataTraced(
        from url: URL,
        context: TraceContext? = nil
    ) async throws -> ImportResult {
        return try await TracingService.shared.traced(
            "DataManager.importData",
            parentContext: context,
            tags: [
                "service": "DataManager",
                "operation_type": "import",
                "source_url": url.path,
                "file_extension": url.pathExtension
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            logger.info("Starting data import", context: traceContext, fields: [
                "source_file": url.lastPathComponent,
                "file_size": String(try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            ])
            
            let importStartTime = Date()
            
            // Validate file accessibility
            let validationContext = TracingService.shared.startSpan(
                "DataManager.validateFile",
                parentContext: traceContext,
                tags: ["validation_type": "file_accessibility"]
            )
            
            guard FileManager.default.fileExists(atPath: url.path) else {
                logger.error("Import file does not exist", context: validationContext, fields: [
                    "file_path": url.path
                ])
                TracingService.shared.finishSpan(validationContext, outcome: .error(DataError.fileNotFound))
                throw DataError.fileNotFound
            }
            
            TracingService.shared.finishSpan(validationContext, outcome: .success)
            
            // Read and parse file content
            let parseContext = TracingService.shared.startSpan(
                "DataManager.parseFile",
                parentContext: traceContext,
                tags: ["parse_type": url.pathExtension]
            )
            
            let fileData = try Data(contentsOf: url)
            let parseResult = try parseFileData(fileData, format: url.pathExtension, context: parseContext)
            
            TracingService.shared.finishSpan(parseContext, outcome: .success, metrics: [
                "parsed_nodes": Double(parseResult.nodes.count),
                "parsed_layers": Double(parseResult.layers.count)
            ])
            
            logger.info("File parsed successfully", context: traceContext, fields: [
                "nodes_found": String(parseResult.nodes.count),
                "layers_found": String(parseResult.layers.count)
            ])
            
            // Validate and merge data
            let mergeContext = TracingService.shared.startSpan(
                "DataManager.mergeData",
                parentContext: traceContext,
                tags: ["merge_type": "import_merge"]
            )
            
            let mergeResult = try await mergeImportedData(parseResult, context: mergeContext)
            
            TracingService.shared.finishSpan(mergeContext, outcome: .success, metrics: [
                "merged_nodes": Double(mergeResult.nodesAdded),
                "skipped_duplicates": Double(mergeResult.duplicatesSkipped)
            ])
            
            let importDuration = Date().timeIntervalSince(importStartTime)
            
            let importResult = ImportResult(
                nodesImported: mergeResult.nodesAdded,
                layersImported: mergeResult.layersAdded,
                duplicatesSkipped: mergeResult.duplicatesSkipped,
                duration: importDuration,
                traceId: traceContext.traceId
            )
            
            logger.info("Data import completed", context: traceContext, fields: [
                "nodes_imported": String(importResult.nodesImported),
                "layers_imported": String(importResult.layersImported),
                "duplicates_skipped": String(importResult.duplicatesSkipped),
                "import_duration_ms": String(format: "%.2f", importDuration * 1000)
            ])
            
            // Record performance metric
            TracingService.shared.recordMetric(
                PerformanceMetrics(
                    operationName: "DataManager.importData",
                    duration: importDuration,
                    success: true,
                    tags: [
                        "file_format": url.pathExtension,
                        "nodes_imported": String(importResult.nodesImported)
                    ]
                )
            )
            
            return importResult
        }
    }
    
    /// Export data with comprehensive tracing
    func exportDataTraced(
        to url: URL,
        format: ExportFormat,
        context: TraceContext? = nil
    ) async throws {
        try await TracingService.shared.traced(
            "DataManager.exportData",
            parentContext: context,
            tags: [
                "service": "DataManager",
                "operation_type": "export",
                "target_url": url.path,
                "export_format": format.rawValue
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            logger.info("Starting data export", context: traceContext, fields: [
                "target_file": url.lastPathComponent,
                "export_format": format.rawValue
            ])
            
            let exportStartTime = Date()
            
            // Gather data to export
            let gatherContext = TracingService.shared.startSpan(
                "DataManager.gatherExportData",
                parentContext: traceContext,
                tags: ["gather_type": "full_dataset"]
            )
            
            let exportData = try await gatherExportData(context: gatherContext)
            
            TracingService.shared.finishSpan(gatherContext, outcome: .success, metrics: [
                "nodes_to_export": Double(exportData.nodes.count),
                "layers_to_export": Double(exportData.layers.count)
            ])
            
            logger.debug("Export data gathered", context: traceContext, fields: [
                "nodes_count": String(exportData.nodes.count),
                "layers_count": String(exportData.layers.count)
            ])
            
            // Serialize data
            let serializeContext = TracingService.shared.startSpan(
                "DataManager.serializeData",
                parentContext: traceContext,
                tags: ["serialization_format": format.rawValue]
            )
            
            let serializedData = try serializeExportData(exportData, format: format, context: serializeContext)
            
            TracingService.shared.finishSpan(serializeContext, outcome: .success, metrics: [
                "serialized_size_bytes": Double(serializedData.count)
            ])
            
            // Write to file
            let writeContext = TracingService.shared.startSpan(
                "DataManager.writeFile",
                parentContext: traceContext,
                tags: ["write_type": "file_output"]
            )
            
            try serializedData.write(to: url)
            
            TracingService.shared.finishSpan(writeContext, outcome: .success)
            
            let exportDuration = Date().timeIntervalSince(exportStartTime)
            
            logger.info("Data export completed", context: traceContext, fields: [
                "export_duration_ms": String(format: "%.2f", exportDuration * 1000),
                "output_file_size": String(serializedData.count)
            ])
            
            // Record performance metric
            TracingService.shared.recordMetric(
                PerformanceMetrics(
                    operationName: "DataManager.exportData",
                    duration: exportDuration,
                    success: true,
                    tags: [
                        "export_format": format.rawValue,
                        "output_size_kb": String(serializedData.count / 1024)
                    ]
                )
            )
        }
    }
    
    // Placeholder implementations for helper methods
    private func parseFileData(_ data: Data, format: String, context: TraceContext) throws -> ParseResult {
        // Implementation would depend on actual file format parsing logic
        return ParseResult(nodes: [], layers: [])
    }
    
    private func mergeImportedData(_ parseResult: ParseResult, context: TraceContext) async throws -> MergeResult {
        // Implementation would depend on actual merge logic
        return MergeResult(nodesAdded: 0, layersAdded: 0, duplicatesSkipped: 0)
    }
    
    private func gatherExportData(context: TraceContext) async throws -> ExportData {
        // Implementation would gather data from NodeStore
        return ExportData(nodes: [], layers: [])
    }
    
    private func serializeExportData(_ data: ExportData, format: ExportFormat, context: TraceContext) throws -> Data {
        // Implementation would serialize based on format
        return Data()
    }
}

// MARK: - Supporting Types for DataManager

struct ImportResult {
    let nodesImported: Int
    let layersImported: Int
    let duplicatesSkipped: Int
    let duration: TimeInterval
    let traceId: String
}

struct ParseResult {
    let nodes: [Node]
    let layers: [Layer]
}

struct MergeResult {
    let nodesAdded: Int
    let layersAdded: Int
    let duplicatesSkipped: Int
}

struct ExportData {
    let nodes: [Node]
    let layers: [Layer]
}

enum ExportFormat: String {
    case json = "json"
    case csv = "csv"
    case xml = "xml"
}

enum DataError: Error {
    case fileNotFound
    case invalidFormat
    case corruptedData
}
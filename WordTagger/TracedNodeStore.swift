import Foundation
import Combine

// MARK: - Traced NodeStore Extensions

extension NodeStore {
    
    // MARK: - Traced Node Operations
    
    /// Add node with comprehensive tracing
    @MainActor
    public func addNodeTraced(_ node: Node, context: TraceContext? = nil) async -> Bool {
        return await TracingService.shared.traced(
            "NodeStore.addNode",
            parentContext: context,
            tags: [
                "service": "NodeStore",
                "operation_type": "create",
                "node_text": node.text,
                "layer_id": node.layerId.uuidString,
                "tags_count": String(node.tags.count)
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            logger.info("Starting node addition", context: traceContext, fields: [
                "node_id": node.id.uuidString,
                "node_text": node.text,
                "phonetic": node.phonetic ?? "",
                "meaning": node.meaning ?? "",
                "current_layer": currentLayer?.displayName ?? "none"
            ])
            
            // Check layer availability with tracing
            guard !layers.isEmpty else {
                logger.error("Cannot add node: no layers available", context: traceContext)
                duplicateNodeAlert = DuplicateNodeAlert(
                    message: "无法添加节点：请先创建至少一个层",
                    isDuplicate: false,
                    existingNode: nil,
                    newNode: node
                )
                return false
            }
            
            guard let currentLayer = currentLayer else {
                logger.error("Cannot add node: no current layer selected", context: traceContext)
                duplicateNodeAlert = DuplicateNodeAlert(
                    message: "无法添加节点：请先选择一个层",
                    isDuplicate: false,
                    existingNode: nil,
                    newNode: node
                )
                return false
            }
            
            // 复合层现在也支持创建节点
            if currentLayer.isCompound {
                logger.info("复合层支持节点创建", context: traceContext, fields: [
                    "layer_name": currentLayer.displayName,
                    "layer_type": "compound",
                    "action": "allow_node_creation"
                ])
            }
            
            // Duplicate detection with tracing
            let duplicateCheckContext = TracingService.shared.startSpan(
                "NodeStore.duplicateCheck",
                parentContext: traceContext,
                tags: ["check_type": "duplicate_detection"]
            )
            
            logger.debug("Checking for duplicate nodes", context: duplicateCheckContext, fields: [
                "existing_nodes_count": String(nodes.count),
                "search_text": node.text.lowercased()
            ])
            
            for (index, existingNode) in nodes.enumerated() {
                logger.trace("Comparing with existing node", context: duplicateCheckContext, fields: [
                    "index": String(index),
                    "existing_text": existingNode.text,
                    "existing_text_lower": existingNode.text.lowercased()
                ])
            }
            
            // 检查重复节点，考虑层级结构
            let layersToCheck: Set<UUID>
            if currentLayer.isCompound {
                // 复合层：检查所有子层和自身
                var allLayerIds = Set<UUID>([currentLayer.id])
                allLayerIds.formUnion(Set(currentLayer.childLayerIds))
                layersToCheck = allLayerIds
                logger.debug("复合层检测范围", context: duplicateCheckContext, fields: [
                    "layers_count": String(layersToCheck.count)
                ])
            } else {
                // 普通层：只检查自身
                layersToCheck = Set([currentLayer.id])
                logger.debug("普通层检测范围", context: duplicateCheckContext, fields: [
                    "layer_id": currentLayer.id.uuidString
                ])
            }
            
            if let existingNode = nodes.first(where: { 
                $0.text.lowercased() == node.text.lowercased() && 
                layersToCheck.contains($0.layerId)
            }) {
                logger.warn("Duplicate node detected", context: duplicateCheckContext, fields: [
                    "existing_node_id": existingNode.id.uuidString,
                    "existing_tags_count": String(existingNode.tags.count),
                    "new_tags_count": String(node.tags.count)
                ])
                
                // Tag comparison with detailed tracing
                let tagComparisonContext = TracingService.shared.startSpan(
                    "NodeStore.tagComparison",
                    parentContext: duplicateCheckContext,
                    tags: ["comparison_type": "tag_merge_analysis"]
                )
                
                logger.debug("Analyzing tag overlap", context: tagComparisonContext)
                for (i, tag) in existingNode.tags.enumerated() {
                    logger.trace("Existing tag", context: tagComparisonContext, fields: [
                        "index": String(i),
                        "type": tag.type.displayName,
                        "value": tag.value
                    ])
                }
                for (i, tag) in node.tags.enumerated() {
                    logger.trace("New tag", context: tagComparisonContext, fields: [
                        "index": String(i),
                        "type": tag.type.displayName,
                        "value": tag.value
                    ])
                }
                
                let duplicateTags = node.tags.filter { newTag in
                    let isDuplicate = existingNode.tags.contains { existingTag in
                        let typeMatch = existingTag.type == newTag.type
                        let valueMatch = existingTag.value.lowercased() == newTag.value.lowercased()
                        logger.trace("Tag comparison", context: tagComparisonContext, fields: [
                            "existing_type": existingTag.type.displayName,
                            "existing_value": existingTag.value,
                            "new_type": newTag.type.displayName,
                            "new_value": newTag.value,
                            "type_match": String(typeMatch),
                            "value_match": String(valueMatch)
                        ])
                        return typeMatch && valueMatch
                    }
                    return isDuplicate
                }
                
                TracingService.shared.finishSpan(tagComparisonContext, outcome: .success)
                
                if !duplicateTags.isEmpty {
                    // Complete duplicate - reject
                    let tagNames = duplicateTags.map { "\($0.type.displayName)-\($0.value)" }.joined(separator: ", ")
                    duplicateNodeAlert = DuplicateNodeAlert(
                        message: "节点 \"\(node.text)\" 已存在相同的标签: \(tagNames)",
                        isDuplicate: true,
                        existingNode: existingNode,
                        newNode: node
                    )
                    
                    TracingService.shared.finishSpan(duplicateCheckContext, outcome: .success, metrics: [
                        "duplicate_tags_found": Double(duplicateTags.count)
                    ])
                    
                    logger.error("Node rejected due to identical tags", context: traceContext, fields: [
                        "duplicate_tags": tagNames
                    ])
                    return false
                } else {
                    // Partial duplicate - merge tags
                    let mergeContext = TracingService.shared.startSpan(
                        "NodeStore.tagMerge",
                        parentContext: duplicateCheckContext,
                        tags: ["operation_type": "tag_merge"]
                    )
                    
                    let newTags = node.tags.filter { newTag in
                        !existingNode.tags.contains { existingTag in
                            existingTag.type == newTag.type && existingTag.value.lowercased() == newTag.value.lowercased()
                        }
                    }
                    
                    if !newTags.isEmpty {
                        logger.info("Merging tags into existing node", context: mergeContext, fields: [
                            "new_tags_count": String(newTags.count),
                            "tags_to_merge": newTags.map { "\($0.type.displayName)-\($0.value)" }.joined(separator: ", ")
                        ])
                        
                        for tag in newTags {
                            addTagTraced(to: existingNode.id, tag: tag, context: mergeContext)
                        }
                        
                        let tagNames = newTags.map { "\($0.type.displayName)-\($0.value)" }.joined(separator: ", ")
                        duplicateNodeAlert = DuplicateNodeAlert(
                            message: "已将新标签 \(tagNames) 合并到现有节点 \"\(node.text)\"",
                            isDuplicate: false,
                            existingNode: existingNode,
                            newNode: node
                        )
                        
                        TracingService.shared.finishSpan(mergeContext, outcome: .success, metrics: [
                            "merged_tags_count": Double(newTags.count)
                        ])
                        TracingService.shared.finishSpan(duplicateCheckContext, outcome: .success)
                        
                        logger.info("Tag merge completed successfully", context: traceContext, fields: [
                            "merged_tags_count": String(newTags.count)
                        ])
                        return true
                    } else {
                        // No new tags to merge
                        duplicateNodeAlert = DuplicateNodeAlert(
                            message: "节点 \"\(node.text)\" 已存在，且所有标签都相同",
                            isDuplicate: true,
                            existingNode: existingNode,
                            newNode: node
                        )
                        
                        TracingService.shared.finishSpan(mergeContext, outcome: .success, metrics: [
                            "merged_tags_count": 0.0
                        ])
                        TracingService.shared.finishSpan(duplicateCheckContext, outcome: .success)
                        
                        logger.warn("Node completely duplicate, no action taken", context: traceContext)
                        return false
                    }
                }
            } else {
                // New node - proceed with addition
                TracingService.shared.finishSpan(duplicateCheckContext, outcome: .success, metrics: [
                    "duplicates_found": 0.0
                ])
                
                logger.info("No duplicate found, proceeding with node addition", context: traceContext)
                
                var nodeWithLayer = node
                nodeWithLayer.layerId = currentLayer.id
                logger.debug("Associated node with layer", context: traceContext, fields: [
                    "layer_id": currentLayer.id.uuidString,
                    "layer_name": currentLayer.displayName
                ])
                
                nodes.append(nodeWithLayer)
                logger.info("Node added successfully", context: traceContext, fields: [
                    "total_nodes": String(nodes.count)
                ])
                
                // Trigger UI update
                objectWillChange.send()
                
                // Send traced notification
                NotificationCenter.default.post(
                    name: Notification.Name("nodeUpdated"),
                    object: nodeWithLayer,
                    context: traceContext
                )
                logger.debug("Posted nodeUpdated notification", context: traceContext)
                
                // Auto-save with tracing
                if !isLoadingFromExternal {
                    let saveContext = TracingService.shared.startSpan(
                        "NodeStore.autoSave",
                        parentContext: traceContext,
                        tags: ["save_type": "auto_save_after_add"]
                    )
                    
                    Task.traced(saveContext) { saveContext in
                        await forceSaveToExternalStorageTraced(context: saveContext)
                        logger.info("Auto-save completed after node addition", context: saveContext)
                    }
                }
                
                return true
            }
        }
    }
    
    /// Update node with tracing
    @MainActor
    public func updateNodeTraced(
        _ nodeId: UUID,
        text: String? = nil,
        phonetic: String? = nil,
        meaning: String? = nil,
        context: TraceContext? = nil
    ) async {
        await TracingService.shared.traced(
            "NodeStore.updateNode",
            parentContext: context,
            tags: [
                "service": "NodeStore",
                "operation_type": "update",
                "node_id": nodeId.uuidString,
                "text_changed": String(text != nil),
                "phonetic_changed": String(phonetic != nil),
                "meaning_changed": String(meaning != nil)
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            guard let index = nodes.firstIndex(where: { $0.id == nodeId }) else {
                logger.error("Node not found for update", context: traceContext, fields: [
                    "node_id": nodeId.uuidString
                ])
                return
            }
            
            let oldNode = nodes[index]
            var updatedNode = oldNode
            
            logger.info("Starting node update", context: traceContext, fields: [
                "old_text": oldNode.text,
                "old_phonetic": oldNode.phonetic ?? "",
                "old_meaning": oldNode.meaning ?? ""
            ])
            
            var changes: [String] = []
            
            if let text = text {
                updatedNode.text = text
                changes.append("text: '\(oldNode.text)' -> '\(text)'")
            }
            if let phonetic = phonetic {
                updatedNode.phonetic = phonetic
                changes.append("phonetic: '\(oldNode.phonetic ?? "")' -> '\(phonetic)'")
            }
            if let meaning = meaning {
                updatedNode.meaning = meaning
                changes.append("meaning: '\(oldNode.meaning ?? "")' -> '\(meaning)'")
            }
            
            if !changes.isEmpty {
                updatedNode.updatedAt = Date()
                nodes[index] = updatedNode
                
                logger.info("Node updated successfully", context: traceContext, fields: [
                    "changes": changes.joined(separator: "; ")
                ])
                
                // Handle compound node refresh if text changed
                if let newText = text, newText != oldNode.text {
                    logger.debug("Node text changed, refreshing compound nodes", context: traceContext, fields: [
                        "old_text": oldNode.text,
                        "new_text": newText
                    ])
                    
                    await refreshCompoundNodesReferencingNodeTraced(
                        oldNode.text,
                        context: traceContext
                    )
                    await refreshCompoundNodesReferencingNodeTraced(
                        newText,
                        context: traceContext
                    )
                } else {
                    await refreshCompoundNodesReferencingNodeTraced(
                        updatedNode.text,
                        context: traceContext
                    )
                }
                
                // Trigger UI update
                objectWillChange.send()
                
                // Send traced notification
                NotificationCenter.default.post(
                    name: Notification.Name("nodeUpdated"),
                    object: updatedNode,
                    context: traceContext
                )
                
                // Auto-save with tracing
                if !isLoadingFromExternal {
                    let saveContext = TracingService.shared.startSpan(
                        "NodeStore.autoSave",
                        parentContext: traceContext,
                        tags: ["save_type": "auto_save_after_update"]
                    )
                    
                    Task.traced(saveContext) { saveContext in
                        await forceSaveToExternalStorageTraced(context: saveContext)
                        logger.debug("Auto-save completed after node update", context: saveContext)
                    }
                }
            } else {
                logger.debug("No changes detected, node update skipped", context: traceContext)
            }
        }
    }
    
    /// Delete node with tracing
    @MainActor
    public func deleteNodeTraced(_ nodeId: UUID, context: TraceContext? = nil) async {
        await TracingService.shared.traced(
            "NodeStore.deleteNode",
            parentContext: context,
            tags: [
                "service": "NodeStore",
                "operation_type": "delete",
                "node_id": nodeId.uuidString
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            // Get node info before deletion
            let nodeToDelete = nodes.first { $0.id == nodeId }
            
            if let node = nodeToDelete {
                logger.info("Starting node deletion", context: traceContext, fields: [
                    "node_text": node.text,
                    "node_tags_count": String(node.tags.count),
                    "node_layer_id": node.layerId.uuidString
                ])
            } else {
                logger.warn("Node not found for deletion", context: traceContext, fields: [
                    "node_id": nodeId.uuidString
                ])
            }
            
            let beforeCount = nodes.count
            nodes.removeAll { $0.id == nodeId }
            let afterCount = nodes.count
            
            if beforeCount > afterCount {
                logger.info("Node deleted successfully", context: traceContext, fields: [
                    "nodes_before": String(beforeCount),
                    "nodes_after": String(afterCount)
                ])
            } else {
                logger.warn("No node was deleted (not found)", context: traceContext)
            }
            
            if selectedNode?.id == nodeId {
                selectedNode = nil
                logger.debug("Cleared selected node reference", context: traceContext)
            }
            
            // Trigger UI update
            objectWillChange.send()
            
            // Send traced notification
            if let deletedNode = nodeToDelete {
                NotificationCenter.default.post(
                    name: Notification.Name("nodeUpdated"),
                    object: deletedNode,
                    context: traceContext
                )
            } else {
                NotificationCenter.default.post(
                    name: Notification.Name("nodeUpdated"),
                    object: nil,
                    context: traceContext
                )
            }
            
            // Auto-save with tracing
            if !isLoadingFromExternal {
                let saveContext = TracingService.shared.startSpan(
                    "NodeStore.autoSave",
                    parentContext: traceContext,
                    tags: ["save_type": "auto_save_after_delete"]
                )
                
                Task.traced(saveContext) { saveContext in
                    await forceSaveToExternalStorageTraced(context: saveContext)
                    logger.debug("Auto-save completed after node deletion", context: saveContext)
                }
            }
        }
    }
    
    // MARK: - Traced Tag Operations
    
    /// Add tag to node with tracing
    @MainActor
    public func addTagTraced(to nodeId: UUID, tag: Tag, context: TraceContext? = nil) {
        let traceContext = TracingService.shared.startSpan(
            "NodeStore.addTag",
            parentContext: context,
            tags: [
                "service": "NodeStore",
                "operation_type": "add_tag",
                "node_id": nodeId.uuidString,
                "tag_type": tag.type.displayName,
                "tag_value": tag.value,
                "has_coordinates": String(tag.hasCoordinates)
            ]
        )
        
        defer { TracingService.shared.finishSpan(traceContext) }
        
        let logger = StructuredLogger.shared
        
        guard let index = nodes.firstIndex(where: { $0.id == nodeId }) else {
            logger.error("Node not found for tag addition", context: traceContext, fields: [
                "node_id": nodeId.uuidString
            ])
            TracingService.shared.finishSpan(traceContext, outcome: .error(NSError(domain: "NodeStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Node not found"])))
            return
        }
        
        logger.info("Adding tag to node", context: traceContext, fields: [
            "node_text": nodes[index].text,
            "existing_tags_count": String(nodes[index].tags.count)
        ])
        
        // Create updated node with new tag
        var updatedNode = nodes[index]
        updatedNode.tags.append(tag)
        updatedNode.updatedAt = Date()
        
        // Replace entire node to ensure @Published update
        nodes[index] = updatedNode
        
        logger.info("Tag added successfully", context: traceContext, fields: [
            "new_tags_count": String(updatedNode.tags.count)
        ])
        
        // Refresh compound nodes referencing this node
        refreshCompoundNodesReferencingNodeTraced(updatedNode.text, context: traceContext)
        
        // Trigger UI update
        objectWillChange.send()
        
        // Send notification to clear graph cache
        NotificationCenter.default.post(
            name: Notification.Name("nodeUpdated"),
            object: nil,
            userInfo: ["nodeId": nodeId],
            context: traceContext
        )
        
        // Update selected node reference if needed
        if selectedNode?.id == nodeId {
            selectedNode = updatedNode
            logger.debug("Updated selected node reference", context: traceContext)
        }
        
        // Update selected tag reference if needed
        if let currentSelectedTag = selectedTag,
           currentSelectedTag.type == tag.type && currentSelectedTag.value == tag.value {
            selectedTag = tag
            logger.debug("Updated selected tag reference", context: traceContext)
        }
        
        // Auto-save with tracing
        if !isLoadingFromExternal {
            let saveContext = TracingService.shared.startSpan(
                "NodeStore.autoSave",
                parentContext: traceContext,
                tags: ["save_type": "auto_save_after_add_tag"]
            )
            
            Task.traced(saveContext) { saveContext in
                await forceSaveToExternalStorageTraced(context: saveContext)
                logger.debug("Auto-save completed after tag addition", context: saveContext)
            }
        }
    }
    
    /// Remove tag from node with tracing
    @MainActor
    public func removeTagTraced(from nodeId: UUID, tagId: UUID, context: TraceContext? = nil) {
        let traceContext = TracingService.shared.startSpan(
            "NodeStore.removeTag",
            parentContext: context,
            tags: [
                "service": "NodeStore",
                "operation_type": "remove_tag",
                "node_id": nodeId.uuidString,
                "tag_id": tagId.uuidString
            ]
        )
        
        defer { TracingService.shared.finishSpan(traceContext) }
        
        let logger = StructuredLogger.shared
        
        guard let index = nodes.firstIndex(where: { $0.id == nodeId }) else {
            logger.error("Node not found for tag removal", context: traceContext, fields: [
                "node_id": nodeId.uuidString
            ])
            TracingService.shared.finishSpan(traceContext, outcome: .error(NSError(domain: "NodeStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Node not found"])))
            return
        }
        
        let removedTags = nodes[index].tags.filter { $0.id == tagId }
        let removedTag = removedTags.first
        
        logger.info("Removing tag from node", context: traceContext, fields: [
            "node_text": nodes[index].text,
            "tag_to_remove": removedTag?.value ?? "unknown",
            "existing_tags_count": String(nodes[index].tags.count)
        ])
        
        // Create updated node with tag removed
        var updatedNode = nodes[index]
        updatedNode.tags.removeAll { $0.id == tagId }
        updatedNode.updatedAt = Date()
        
        // Replace entire node to ensure @Published update
        nodes[index] = updatedNode
        
        logger.info("Tag removed successfully", context: traceContext, fields: [
            "remaining_tags_count": String(updatedNode.tags.count),
            "removed_tag": removedTag?.value ?? "unknown"
        ])
        
        // Refresh compound nodes referencing this node
        refreshCompoundNodesReferencingNodeTraced(updatedNode.text, context: traceContext)
        
        // Trigger UI update
        objectWillChange.send()
        
        // Send notification to clear graph cache
        NotificationCenter.default.post(
            name: Notification.Name("nodeUpdated"),
            object: nil,
            userInfo: ["nodeId": nodeId],
            context: traceContext
        )
        
        // Update selected node reference if needed
        if selectedNode?.id == nodeId {
            selectedNode = updatedNode
            logger.debug("Updated selected node reference", context: traceContext)
        }
        
        // Auto-save with tracing
        if !isLoadingFromExternal {
            let saveContext = TracingService.shared.startSpan(
                "NodeStore.autoSave",
                parentContext: traceContext,
                tags: ["save_type": "auto_save_after_remove_tag"]
            )
            
            Task.traced(saveContext) { saveContext in
                await forceSaveToExternalStorageTraced(context: saveContext)
                logger.debug("Auto-save completed after tag removal", context: saveContext)
            }
        }
    }
    
    // MARK: - Traced Search Operations
    
    /// Perform search with comprehensive tracing
    @MainActor
    public func performSearchTraced(query: String, context: TraceContext? = nil) async {
        await TracingService.shared.traced(
            "NodeStore.search",
            parentContext: context,
            tags: [
                "service": "NodeStore",
                "operation_type": "search",
                "query": query,
                "query_length": String(query.count),
                "current_layer": currentLayer?.displayName ?? "none"
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            logger.info("Starting search operation", context: traceContext, fields: [
                "query": query,
                "total_nodes": String(nodes.count)
            ])
            
            if query.isEmpty {
                logger.debug("Empty query, clearing search results", context: traceContext)
                searchResults = []
                return
            }
            
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuery.isEmpty else {
                logger.debug("Query only whitespace, clearing search results", context: traceContext)
                searchResults = []
                return
            }
            
            guard let currentLayer = currentLayer else {
                logger.warn("No current layer selected for search", context: traceContext)
                searchResults = []
                return
            }
            
            logger.debug("Searching in current layer", context: traceContext, fields: [
                "layer_name": currentLayer.displayName,
                "layer_id": currentLayer.id.uuidString
            ])
            
            let searchStartTime = Date()
            
            // Search nodes in current layer
            let nodeResults = nodes.filter { node in
                guard node.layerId == currentLayer.id else { return false }
                
                let textMatch = node.text.localizedCaseInsensitiveContains(trimmedQuery)
                let meaningMatch = node.meaning?.localizedCaseInsensitiveContains(trimmedQuery) ?? false
                let phoneticMatch = node.phonetic?.localizedCaseInsensitiveContains(trimmedQuery) ?? false
                let tagMatch = node.tags.contains { $0.value.localizedCaseInsensitiveContains(trimmedQuery) }
                
                return textMatch || meaningMatch || phoneticMatch || tagMatch
            }
            
            let searchDuration = Date().timeIntervalSince(searchStartTime)
            
            searchResults = Array(nodeResults.prefix(50)) // Limit results
            
            logger.info("Search completed", context: traceContext, fields: [
                "results_found": String(searchResults.count),
                "results_limited": String(nodeResults.count > 50),
                "search_duration_ms": String(format: "%.2f", searchDuration * 1000),
                "nodes_searched": String(nodes.filter { $0.layerId == currentLayer.id }.count)
            ])
            
            // Record search performance metric
            TracingService.shared.recordMetric(
                PerformanceMetrics(
                    operationName: "NodeStore.search",
                    duration: searchDuration,
                    success: true,
                    tags: [
                        "query_length": String(query.count),
                        "results_count": String(searchResults.count),
                        "layer": currentLayer.displayName
                    ]
                )
            )
        }
    }
    
    // MARK: - Traced Data Management
    
    /// Force save to external storage with tracing
    @MainActor
    public func forceSaveToExternalStorageTraced(context: TraceContext? = nil) async {
        await TracingService.shared.traced(
            "NodeStore.forceSave",
            parentContext: context,
            tags: [
                "service": "NodeStore",
                "operation_type": "save",
                "data_path_selected": String(externalDataManager.isDataPathSelected),
                "nodes_count": String(nodes.count),
                "layers_count": String(layers.count)
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            guard externalDataManager.isDataPathSelected else {
                logger.debug("No data path selected, skipping save", context: traceContext)
                return
            }
            
            logger.info("Starting force save to external storage", context: traceContext)
            
            do {
                try await externalDataService.saveAllData(store: self)
                logger.info("Force save completed successfully", context: traceContext)
                
                // Trigger data path change notification for auto-refresh
                NotificationCenter.default.post(
                    name: .dataPathChanged,
                    object: externalDataManager,
                    userInfo: ["newPath": externalDataManager.currentDataPath ?? URL(fileURLWithPath: "")],
                    context: traceContext
                )
                
            } catch {
                logger.error("Force save failed", context: traceContext, fields: [
                    "error": error.localizedDescription
                ])
            }
        }
    }
    
    // MARK: - Traced Compound Node Management
    
    /// Refresh compound nodes referencing a child node with tracing
    @MainActor
    private func refreshCompoundNodesReferencingNodeTraced(_ childNodeName: String, context: TraceContext? = nil) async {
        await TracingService.shared.traced(
            "NodeStore.refreshCompoundNodes",
            parentContext: context,
            tags: [
                "service": "NodeStore",
                "operation_type": "refresh_compound",
                "child_node_name": childNodeName
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            logger.debug("Starting compound node refresh", context: traceContext, fields: [
                "child_node_name": childNodeName
            ])
            
            // Find all compound nodes referencing this child node
            let referencingCompoundNodes = nodes.filter { node in
                guard node.isCompound else { return false }
                
                return node.tags.contains { tag in
                    if case .custom(let key) = tag.type, key == "child" {
                        return tag.value.lowercased() == childNodeName.lowercased()
                    }
                    return false
                }
            }
            
            if referencingCompoundNodes.isEmpty {
                logger.debug("No compound nodes reference this child", context: traceContext, fields: [
                    "child_node_name": childNodeName
                ])
                return
            }
            
            logger.info("Found compound nodes to refresh", context: traceContext, fields: [
                "compound_nodes_count": String(referencingCompoundNodes.count),
                "compound_nodes": referencingCompoundNodes.map { $0.text }.joined(separator: ", ")
            ])
            
            // Update each compound node's timestamp
            for compoundNode in referencingCompoundNodes {
                if let index = nodes.firstIndex(where: { $0.id == compoundNode.id }) {
                    var updatedCompoundNode = nodes[index]
                    updatedCompoundNode.updatedAt = Date()
                    nodes[index] = updatedCompoundNode
                    
                    logger.debug("Refreshed compound node", context: traceContext, fields: [
                        "compound_node_name": updatedCompoundNode.text,
                        "compound_node_id": updatedCompoundNode.id.uuidString
                    ])
                    
                    // Send compound node refresh notification
                    NotificationCenter.default.post(
                        name: Notification.Name("compoundNodeRefreshed"),
                        object: nil,
                        userInfo: [
                            "compoundNodeId": updatedCompoundNode.id,
                            "compoundNodeName": updatedCompoundNode.text,
                            "childNodeName": childNodeName
                        ],
                        context: traceContext
                    )
                }
            }
            
            logger.info("Compound node refresh completed", context: traceContext, fields: [
                "refreshed_count": String(referencingCompoundNodes.count)
            ])
        }
    }
}
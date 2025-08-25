import SwiftUI
import Foundation

// MARK: - Complete Integration Examples

/// Example demonstrating comprehensive trace integration in WordTagger
struct TracingIntegrationExample {
    
    // MARK: - Service Integration Examples
    
    /// Example: Traced node creation workflow
    static func exampleNodeCreationWorkflow() async {
        // Start root trace
        let rootContext = TracingService.shared.startSpan(
            "User.createNode",
            tags: [
                "user_action": "create_node",
                "interface": "ui"
            ]
        )
        
        // Example node creation with full trace propagation
        await NodeStore.shared.addNodeTraced(
            Node(
                text: "example",
                phonetic: "/ɪɡˈzæmpəl/",
                meaning: "a thing characteristic of its kind or illustrating a general rule",
                layerId: UUID(),
                tags: [
                    Tag(type: .custom("category"), value: "linguistics"),
                    Tag(type: .location, value: "dictionary", latitude: 40.7589, longitude: -73.9851)
                ]
            ),
            context: rootContext
        )
        
        TracingService.shared.finishSpan(rootContext, outcome: .success)
    }
    
    /// Example: Traced Git sync operation with retry correlation
    static func exampleGitSyncWithRetries() async {
        let rootContext = TracingService.shared.startSpan(
            "User.syncToGit",
            tags: [
                "user_action": "sync_data",
                "sync_type": "manual"
            ]
        )
        
        do {
            // Commit changes with retry logic
            try await GitService().commitChangesTraced(
                message: "Update node definitions",
                context: rootContext
            )
            
            // Push to remote with retry correlation
            try await GitService().pushToRemoteTraced(context: rootContext)
            
            TracingService.shared.finishSpan(rootContext, outcome: .success)
            
        } catch {
            TracingService.shared.finishSpan(rootContext, outcome: .error(error))
        }
    }
    
    /// Example: Traced search operation across services
    static func exampleCrossServiceSearch() async {
        let rootContext = TracingService.shared.startSpan(
            "User.searchNodes",
            tags: [
                "user_action": "search",
                "search_type": "cross_service"
            ]
        )
        
        // Search in NodeStore
        await NodeStore.shared.performSearchTraced(
            query: "example",
            context: rootContext
        )
        
        // Enhanced search through SearchService
        let nodes = NodeStore.shared.nodes
        let searchResults = await SearchService().searchTraced(
            query: "example linguistic",
            in: nodes,
            context: rootContext
        )
        
        // Generate graph for search results
        let graphData = await GraphService().generateGraphDataTraced(
            for: searchResults,
            context: rootContext
        )
        
        TracingService.shared.finishSpan(rootContext, outcome: .success)
    }
    
    // MARK: - UI Integration Examples
    
    /// Example SwiftUI view with trace integration
    struct TracedNodeEditorView: View {
        @EnvironmentObject private var tracedEnv: TracedEnvironment
        @State private var nodeText = ""
        @State private var isLoading = false
        
        var body: some View {
            VStack {
                TextField("Node text", text: $nodeText)
                    .textFieldStyle(.roundedBorder)
                
                Button("Save Node") {
                    Task {
                        await saveNodeWithTracing()
                    }
                }
                .disabled(isLoading)
            }
            .traced(
                "NodeEditor",
                tags: ["ui_component": "node_editor"]
            )
        }
        
        private func saveNodeWithTracing() async {
            isLoading = true
            defer { isLoading = false }
            
            await TracedTaskManager.shared.executeTask(
                name: "NodeEditor.saveNode",
                parentContext: tracedEnv.context,
                tags: ["action": "save_node"]
            ) { context in
                
                let node = Node(
                    text: nodeText,
                    layerId: UUID(),
                    tags: []
                )
                
                await NodeStore.shared.addNodeTraced(node, context: context)
                
                // Clear form after successful save
                await MainActor.run {
                    nodeText = ""
                }
            }
        }
    }
    
    // MARK: - Notification Integration Examples
    
    /// Example: Traced notification handling
    static func setupTracedNotifications() {
        let notificationCenter = TracedNotificationCenter.shared
        
        // Add observer with automatic trace context extraction
        notificationCenter.addObserver(
            forName: Notification.Name("nodeUpdated"),
            using: { notification, context in
                // Handle notification with trace context
                handleNodeUpdateNotification(notification, context: context)
            }
        )
        
        // Add observer for Git sync events
        notificationCenter.addObserver(
            forName: .gitOperationSucceeded,
            using: { notification, context in
                handleGitSyncSuccess(notification, context: context)
            }
        )
    }
    
    private static func handleNodeUpdateNotification(
        _ notification: Notification,
        context: TraceContext?
    ) {
        let handlerContext = TracingService.shared.startSpan(
            "NotificationHandler.nodeUpdated",
            parentContext: context,
            tags: ["handler_type": "node_update"]
        )
        
        StructuredLogger.shared.info(
            "Handling node update notification",
            context: handlerContext,
            fields: [
                "notification_object": String(describing: notification.object),
                "has_trace_context": String(context != nil)
            ]
        )
        
        // Perform notification handling logic here
        // For example: refresh UI, update caches, etc.
        
        TracingService.shared.finishSpan(handlerContext, outcome: .success)
    }
    
    private static func handleGitSyncSuccess(
        _ notification: Notification,
        context: TraceContext?
    ) {
        let handlerContext = TracingService.shared.startSpan(
            "NotificationHandler.gitSyncSuccess",
            parentContext: context,
            tags: ["handler_type": "git_sync"]
        )
        
        StructuredLogger.shared.info(
            "Git sync succeeded",
            context: handlerContext,
            fields: [
                "sync_timestamp": DateFormatter.iso8601WithMilliseconds.string(from: Date())
            ]
        )
        
        TracingService.shared.finishSpan(handlerContext, outcome: .success)
    }
    
    // MARK: - Concurrent Operations Example
    
    /// Example: Traced concurrent operations with correlation
    static func exampleConcurrentDataProcessing() async throws {
        let rootContext = TracingService.shared.startSpan(
            "DataProcessing.batchOperation",
            tags: [
                "operation_type": "batch_processing",
                "processing_mode": "concurrent"
            ]
        )
        
        let concurrentTasks: [(String, (TraceContext) async throws -> String)] = [
            ("validateNodes", validateNodesOperation),
            ("generateReports", generateReportsOperation),
            ("syncExternalData", syncExternalDataOperation),
            ("updateSearchIndex", updateSearchIndexOperation)
        ]
        
        let results = try await TracedTaskManager.shared.executeConcurrentTasks(
            name: "DataProcessing.concurrentBatch",
            parentContext: rootContext,
            tasks: concurrentTasks
        )
        
        TracingService.shared.finishSpan(rootContext, outcome: .success, metrics: [
            "processed_operations": Double(results.count)
        ])
        
        StructuredLogger.shared.info(
            "Concurrent data processing completed",
            context: rootContext,
            fields: [
                "operations_completed": String(results.count),
                "results": results.joined(separator: ", ")
            ]
        )
    }
    
    private static func validateNodesOperation(context: TraceContext) async throws -> String {
        // Simulate node validation
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        StructuredLogger.shared.info(
            "Node validation completed",
            context: context,
            fields: ["validated_nodes": "150"]
        )
        
        return "validation_success"
    }
    
    private static func generateReportsOperation(context: TraceContext) async throws -> String {
        // Simulate report generation
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        StructuredLogger.shared.info(
            "Report generation completed",
            context: context,
            fields: ["reports_generated": "3"]
        )
        
        return "reports_generated"
    }
    
    private static func syncExternalDataOperation(context: TraceContext) async throws -> String {
        // Simulate external data sync
        try await Task.sleep(nanoseconds: 750_000_000) // 0.75 seconds
        
        StructuredLogger.shared.info(
            "External data sync completed",
            context: context,
            fields: ["synced_records": "500"]
        )
        
        return "sync_completed"
    }
    
    private static func updateSearchIndexOperation(context: TraceContext) async throws -> String {
        // Simulate search index update
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        StructuredLogger.shared.info(
            "Search index update completed",
            context: context,
            fields: ["indexed_items": "1200"]
        )
        
        return "index_updated"
    }
    
    // MARK: - Error Handling and Recovery Examples
    
    /// Example: Traced error handling with recovery
    static func exampleErrorHandlingWithRecovery() async {
        let rootContext = TracingService.shared.startSpan(
            "DataOperation.withRecovery",
            tags: [
                "operation_type": "error_recovery_demo",
                "retry_enabled": "true"
            ]
        )
        
        do {
            // Attempt operation that might fail
            try await attemptRiskyOperation(context: rootContext)
            
            TracingService.shared.finishSpan(rootContext, outcome: .success)
            
        } catch {
            StructuredLogger.shared.error(
                "Primary operation failed, attempting recovery",
                context: rootContext,
                fields: [
                    "error_type": String(describing: type(of: error)),
                    "error_message": error.localizedDescription
                ]
            )
            
            // Attempt recovery operation
            let recoveryContext = TracingService.shared.startSpan(
                "DataOperation.recovery",
                parentContext: rootContext,
                tags: ["recovery_type": "fallback"]
            )
            
            do {
                try await performRecoveryOperation(context: recoveryContext)
                TracingService.shared.finishSpan(recoveryContext, outcome: .success)
                TracingService.shared.finishSpan(rootContext, outcome: .success)
                
            } catch recoveryError {
                TracingService.shared.finishSpan(recoveryContext, outcome: .error(recoveryError))
                TracingService.shared.finishSpan(rootContext, outcome: .error(recoveryError))
                
                StructuredLogger.shared.error(
                    "Recovery operation also failed",
                    context: rootContext,
                    fields: [
                        "recovery_error": recoveryError.localizedDescription
                    ]
                )
            }
        }
    }
    
    private static func attemptRiskyOperation(context: TraceContext) async throws {
        // Simulate an operation that might fail
        if Bool.random() {
            throw NSError(domain: "ExampleError", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Simulated failure"
            ])
        }
        
        StructuredLogger.shared.info("Risky operation succeeded", context: context)
    }
    
    private static func performRecoveryOperation(context: TraceContext) async throws {
        // Simulate recovery operation
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        StructuredLogger.shared.info("Recovery operation completed", context: context)
    }
    
    // MARK: - Performance Monitoring Examples
    
    /// Example: Performance monitoring with custom metrics
    static func examplePerformanceMonitoring() async {
        let context = TracingService.shared.startSpan(
            "Performance.monitoring",
            tags: ["monitoring_type": "custom_metrics"]
        )
        
        // Simulate CPU-intensive operation
        let cpuStart = ProcessInfo.processInfo.systemUptime
        
        // Perform some work
        var result = 0
        for i in 0..<1_000_000 {
            result += i
        }
        
        let cpuEnd = ProcessInfo.processInfo.systemUptime
        let cpuTime = cpuEnd - cpuStart
        
        // Record custom performance metrics
        let memoryUsage = getMemoryUsage()
        
        TracingService.shared.finishSpan(
            context,
            outcome: .success,
            metrics: [
                "cpu_time_ms": cpuTime * 1000,
                "memory_usage_mb": memoryUsage,
                "computation_result": Double(result)
            ]
        )
        
        // Also record as standalone performance metric
        TracingService.shared.recordMetric(
            PerformanceMetrics(
                operationName: "Performance.cpuIntensive",
                duration: cpuTime,
                success: true,
                tags: [
                    "operation_size": "1M_iterations",
                    "result_value": String(result)
                ],
                memoryUsageMB: memoryUsage,
                cpuUsage: cpuTime
            )
        )
        
        StructuredLogger.shared.info(
            "Performance monitoring completed",
            context: context,
            fields: [
                "cpu_time_ms": String(format: "%.2f", cpuTime * 1000),
                "memory_usage_mb": String(format: "%.1f", memoryUsage),
                "computation_iterations": "1000000"
            ]
        )
    }
    
    private static func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024 * 1024) // Convert to MB
        } else {
            return 0.0
        }
    }
}

// MARK: - Integration Testing Examples

/// Test utilities for validating trace integration
struct TracingTestUtilities {
    
    /// Validate that trace context is properly propagated
    static func validateTraceContextPropagation() async {
        let rootContext = TracingService.shared.startSpan(
            "Test.traceContextPropagation",
            tags: ["test_type": "integration"]
        )
        
        // Test notification-based propagation
        let notificationContext = TracingService.shared.startSpan(
            "Test.notificationPropagation",
            parentContext: rootContext,
            tags: ["propagation_type": "notification"]
        )
        
        TracedNotificationCenter.shared.post(
            name: Notification.Name("testNotification"),
            context: notificationContext
        )
        
        TracingService.shared.finishSpan(notificationContext, outcome: .success)
        
        // Test async task propagation
        await TracedTaskManager.shared.executeTask(
            name: "Test.asyncPropagation",
            parentContext: rootContext,
            tags: ["propagation_type": "async_task"]
        ) { taskContext in
            
            StructuredLogger.shared.info(
                "Async task trace context validated",
                context: taskContext,
                fields: [
                    "parent_trace_id": rootContext.traceId,
                    "task_trace_id": taskContext.traceId,
                    "trace_id_match": String(rootContext.traceId == taskContext.traceId)
                ]
            )
        }
        
        TracingService.shared.finishSpan(rootContext, outcome: .success)
        
        // Validate trace tree structure
        let traceTree = TracingService.shared.getTraceTree(traceId: rootContext.traceId)
        assert(traceTree.count >= 2, "Trace tree should contain at least root and child spans")
        
        StructuredLogger.shared.info(
            "Trace context propagation test completed",
            context: rootContext,
            fields: [
                "trace_spans_count": String(traceTree.count),
                "test_result": "passed"
            ]
        )
    }
    
    /// Benchmark tracing overhead
    static func benchmarkTracingOverhead() async {
        let iterations = 10000
        
        // Benchmark without tracing
        let startWithoutTracing = Date()
        for _ in 0..<iterations {
            // Simulate lightweight operation
            _ = UUID().uuidString
        }
        let durationWithoutTracing = Date().timeIntervalSince(startWithoutTracing)
        
        // Benchmark with tracing
        let startWithTracing = Date()
        for i in 0..<iterations {
            let context = TracingService.shared.startSpan(
                "Benchmark.operation",
                tags: ["iteration": String(i)]
            )
            
            // Same lightweight operation
            _ = UUID().uuidString
            
            TracingService.shared.finishSpan(context, outcome: .success)
        }
        let durationWithTracing = Date().timeIntervalSince(startWithTracing)
        
        let overhead = durationWithTracing - durationWithoutTracing
        let overheadPerOperation = overhead / Double(iterations)
        let overheadPercentage = (overhead / durationWithoutTracing) * 100
        
        StructuredLogger.shared.info(
            "Tracing overhead benchmark completed",
            fields: [
                "iterations": String(iterations),
                "duration_without_tracing_ms": String(format: "%.2f", durationWithoutTracing * 1000),
                "duration_with_tracing_ms": String(format: "%.2f", durationWithTracing * 1000),
                "total_overhead_ms": String(format: "%.2f", overhead * 1000),
                "overhead_per_operation_μs": String(format: "%.2f", overheadPerOperation * 1_000_000),
                "overhead_percentage": String(format: "%.1f%%", overheadPercentage)
            ]
        )
    }
}

// MARK: - Usage Documentation

/// Documentation and best practices for using the tracing system
struct TracingUsageGuide {
    
    /// Best practices for trace integration
    static let bestPractices = """
    # WordTagger Tracing System - Best Practices
    
    ## When to Use Tracing
    
    1. **Service Boundaries**: Always trace operations that cross service boundaries
    2. **User Actions**: Trace all user-initiated operations from UI to completion
    3. **External Dependencies**: Trace calls to external services (Git, file system, network)
    4. **Performance Critical Paths**: Trace operations that are performance sensitive
    5. **Error-Prone Operations**: Trace operations with high failure potential
    
    ## Trace Context Propagation
    
    1. **Always propagate context** through async operations using TracedTaskManager
    2. **Use notification-based propagation** for loosely coupled components
    3. **Enrich context with relevant tags** at each service boundary
    4. **Maintain trace correlation** across retry operations
    
    ## Performance Considerations
    
    1. **Minimize trace overhead** by avoiding excessive span creation in tight loops
    2. **Use appropriate log levels** - trace/debug for detailed info, info/warn/error for important events
    3. **Limit tag values** to avoid memory bloat
    4. **Consider sampling** for high-volume operations
    
    ## Error Handling
    
    1. **Always finish spans** even in error conditions
    2. **Record error information** in span outcomes
    3. **Use structured logging** with trace context for detailed error analysis
    4. **Correlate retry attempts** using parent trace context
    
    ## Testing
    
    1. **Validate trace propagation** in integration tests
    2. **Benchmark tracing overhead** to ensure performance impact is acceptable
    3. **Test error scenarios** to ensure proper trace completion
    4. **Verify trace tree structure** for complex operations
    """
    
    /// Integration checklist
    static let integrationChecklist = """
    # Integration Checklist
    
    ## Service Integration
    - [ ] Add traced methods for all public service operations
    - [ ] Propagate trace context through all async operations
    - [ ] Add performance metrics collection
    - [ ] Implement proper error handling with trace context
    
    ## UI Integration
    - [ ] Add trace context to view lifecycle
    - [ ] Use TracedTaskManager for async UI operations
    - [ ] Implement traced notification handling
    - [ ] Add performance monitoring for UI operations
    
    ## Testing
    - [ ] Validate trace context propagation
    - [ ] Test error scenarios with tracing
    - [ ] Benchmark tracing overhead
    - [ ] Verify observability dashboard functionality
    
    ## Deployment
    - [ ] Configure appropriate log levels for production
    - [ ] Set up trace data retention policies
    - [ ] Monitor system performance impact
    - [ ] Establish alerting based on trace data
    """
}
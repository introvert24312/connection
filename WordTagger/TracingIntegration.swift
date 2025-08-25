import Foundation
import SwiftUI
import Combine

// MARK: - Notification-based Trace Propagation

/// Enhanced notification center with automatic trace context propagation
class TracedNotificationCenter: ObservableObject {
    static let shared = TracedNotificationCenter()
    private let notificationCenter = NotificationCenter.default
    private let logger = StructuredLogger.shared
    
    private init() {}
    
    /// Post notification with automatic trace context propagation
    func post(
        name: NSNotification.Name,
        object: Any? = nil,
        userInfo: [AnyHashable: Any]? = nil,
        context: TraceContext? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        var enrichedUserInfo = userInfo ?? [:]
        
        if let context = context {
            enrichedUserInfo["trace_id"] = context.traceId
            enrichedUserInfo["span_id"] = context.spanId
            enrichedUserInfo["parent_span_id"] = context.parentSpanId
            enrichedUserInfo["operation"] = context.operationName
            enrichedUserInfo["trace_timestamp"] = context.startTime.timeIntervalSince1970
            
            logger.debug("Posting notification with trace context", context: context, fields: [
                "notification_name": name.rawValue,
                "object_type": object != nil ? String(describing: type(of: object!)) : "nil",
                "userInfo_keys": enrichedUserInfo.keys.map { String(describing: $0) }.joined(separator: ", "),
                "source_file": URL(fileURLWithPath: file).lastPathComponent,
                "source_function": function,
                "source_line": String(line)
            ])
        }
        
        notificationCenter.post(name: name, object: object, userInfo: enrichedUserInfo)
    }
    
    /// Extract trace context from notification
    func extractTraceContext(from notification: Notification) -> TraceContext? {
        guard let userInfo = notification.userInfo,
              let traceId = userInfo["trace_id"] as? String,
              let spanId = userInfo["span_id"] as? String,
              let operationName = userInfo["operation"] as? String else {
            return nil
        }
        
        let parentSpanId = userInfo["parent_span_id"] as? String
        let timestamp = userInfo["trace_timestamp"] as? TimeInterval
        
        logger.trace("Extracted trace context from notification", fields: [
            "notification_name": notification.name.rawValue,
            "trace_id": traceId,
            "span_id": spanId,
            "parent_span_id": parentSpanId ?? "none",
            "operation": operationName
        ])
        
        return TraceContext(
            traceId: traceId,
            spanId: spanId,
            parentSpanId: parentSpanId,
            operationName: operationName,
            startTime: timestamp != nil ? Date(timeIntervalSince1970: timestamp!) : Date(),
            tags: [:],
            baggage: [:]
        )
    }
    
    /// Add observer with automatic trace context extraction
    func addObserver(
        forName name: NSNotification.Name?,
        object: Any? = nil,
        queue: OperationQueue? = nil,
        using block: @escaping (Notification, TraceContext?) -> Void
    ) -> NSObjectProtocol {
        return notificationCenter.addObserver(
            forName: name,
            object: object,
            queue: queue
        ) { [weak self] notification in
            let context = self?.extractTraceContext(from: notification)
            block(notification, context)
        }
    }
}

// MARK: - Async Operation Trace Context Helpers

/// Task wrapper with automatic trace context propagation
@MainActor
class TracedTaskManager: ObservableObject {
    static let shared = TracedTaskManager()
    
    @Published private(set) var activeTasks: [TracedTask] = []
    private let logger = StructuredLogger.shared
    
    private init() {}
    
    /// Execute a throwing task with trace context propagation
    @discardableResult
    func executeTask<T>(
        name: String,
        parentContext: TraceContext? = nil,
        tags: [String: String] = [:],
        operation: @escaping (TraceContext) async throws -> T
    ) async throws -> T {
        let context = TracingService.shared.startSpan(
            name,
            parentContext: parentContext,
            tags: tags.merging(["task_type": "async_throwing"]) { _, new in new }
        )
        
        let task = TracedTask(
            id: UUID(),
            name: name,
            context: context,
            startTime: Date()
        )
        
        activeTasks.append(task)
        
        logger.info("Starting traced task", context: context, fields: [
            "task_name": name,
            "task_id": task.id.uuidString,
            "active_tasks_count": String(activeTasks.count)
        ])
        
        defer {
            activeTasks.removeAll { $0.id == task.id }
            logger.debug("Completed traced task", context: context, fields: [
                "task_duration_ms": String(format: "%.2f", Date().timeIntervalSince(task.startTime) * 1000),
                "remaining_active_tasks": String(activeTasks.count)
            ])
        }
        
        do {
            let result = try await operation(context)
            TracingService.shared.finishSpan(context, outcome: .success)
            return result
        } catch {
            TracingService.shared.finishSpan(context, outcome: .error(error))
            throw error
        }
    }
    
    /// Execute a non-throwing task with trace context propagation
    @discardableResult
    func executeTask<T>(
        name: String,
        parentContext: TraceContext? = nil,
        tags: [String: String] = [:],
        operation: @escaping (TraceContext) async -> T
    ) async -> T {
        let context = TracingService.shared.startSpan(
            name,
            parentContext: parentContext,
            tags: tags.merging(["task_type": "async_non_throwing"]) { _, new in new }
        )
        
        let task = TracedTask(
            id: UUID(),
            name: name,
            context: context,
            startTime: Date()
        )
        
        activeTasks.append(task)
        
        logger.info("Starting traced task (non-throwing)", context: context, fields: [
            "task_name": name,
            "task_id": task.id.uuidString,
            "active_tasks_count": String(activeTasks.count)
        ])
        
        defer {
            activeTasks.removeAll { $0.id == task.id }
            TracingService.shared.finishSpan(context, outcome: .success)
            logger.debug("Completed traced task (non-throwing)", context: context, fields: [
                "task_duration_ms": String(format: "%.2f", Date().timeIntervalSince(task.startTime) * 1000),
                "remaining_active_tasks": String(activeTasks.count)
            ])
        }
        
        let result = await operation(context)
        return result
    }
    
    /// Execute multiple concurrent tasks with trace correlation
    func executeConcurrentTasks<T>(
        name: String,
        parentContext: TraceContext? = nil,
        tasks: [(String, (TraceContext) async throws -> T)]
    ) async throws -> [T] {
        let parentSpan = TracingService.shared.startSpan(
            name,
            parentContext: parentContext,
            tags: [
                "task_type": "concurrent_batch",
                "subtasks_count": String(tasks.count)
            ]
        )
        
        logger.info("Starting concurrent traced tasks", context: parentSpan, fields: [
            "batch_name": name,
            "subtasks_count": String(tasks.count),
            "subtask_names": tasks.map { $0.0 }.joined(separator: ", ")
        ])
        
        do {
            let results = try await withThrowingTaskGroup(of: T.self) { group in
                for (taskName, taskOperation) in tasks {
                    group.addTask {
                        try await self.executeTask(
                            name: "\(name).\(taskName)",
                            parentContext: parentSpan,
                            operation: taskOperation
                        )
                    }
                }
                
                var results: [T] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }
            
            TracingService.shared.finishSpan(parentSpan, outcome: .success, metrics: [
                "completed_subtasks": Double(results.count)
            ])
            
            logger.info("Concurrent traced tasks completed successfully", context: parentSpan, fields: [
                "completed_count": String(results.count)
            ])
            
            return results
            
        } catch {
            TracingService.shared.finishSpan(parentSpan, outcome: .error(error))
            logger.error("Concurrent traced tasks failed", context: parentSpan, fields: [
                "error": error.localizedDescription
            ])
            throw error
        }
    }
    
    /// Cancel all active tasks
    func cancelAllTasks() {
        logger.info("Cancelling all active tasks", fields: [
            "active_tasks_count": String(activeTasks.count)
        ])
        
        activeTasks.removeAll()
    }
}

struct TracedTask {
    let id: UUID
    let name: String
    let context: TraceContext
    let startTime: Date
}

// MARK: - SwiftUI Integration

/// View modifier that adds trace context to view hierarchy
struct TracedViewModifier: ViewModifier {
    let operationName: String
    let parentContext: TraceContext?
    let tags: [String: String]
    
    @State private var viewContext: TraceContext?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                viewContext = TracingService.shared.startSpan(
                    "View.\(operationName).appear",
                    parentContext: parentContext,
                    tags: tags.merging(["view_lifecycle": "appear"]) { _, new in new }
                )
                
                StructuredLogger.shared.debug("View appeared with trace context", context: viewContext, fields: [
                    "view_operation": operationName
                ])
            }
            .onDisappear {
                if let context = viewContext {
                    TracingService.shared.finishSpan(context, outcome: .success)
                    
                    StructuredLogger.shared.debug("View disappeared, span finished", context: context, fields: [
                        "view_operation": operationName
                    ])
                }
                viewContext = nil
            }
            .environmentObject(TracedEnvironment(context: viewContext))
    }
}

extension View {
    /// Add trace context to view
    func traced(
        _ operationName: String,
        parentContext: TraceContext? = nil,
        tags: [String: String] = [:]
    ) -> some View {
        modifier(TracedViewModifier(
            operationName: operationName,
            parentContext: parentContext,
            tags: tags
        ))
    }
}

/// Environment object that carries trace context through view hierarchy
class TracedEnvironment: ObservableObject {
    let context: TraceContext?
    
    init(context: TraceContext?) {
        self.context = context
    }
}

// MARK: - Database Operations Tracing

/// Wrapper for Core Data/SwiftData operations with tracing
class TracedPersistenceManager: ObservableObject {
    static let shared = TracedPersistenceManager()
    private let logger = StructuredLogger.shared
    
    private init() {}
    
    /// Execute a database operation with tracing
    func executeOperation<T>(
        name: String,
        context: TraceContext? = nil,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        return try await TracingService.shared.traced(
            "Persistence.\(name)",
            parentContext: context,
            tags: [
                "service": "PersistenceManager",
                "operation_type": "database"
            ]
        ) { traceContext in
            
            logger.info("Starting database operation", context: traceContext, fields: [
                "operation_name": name
            ])
            
            let startTime = Date()
            
            do {
                let result = try await operation()
                let duration = Date().timeIntervalSince(startTime)
                
                logger.info("Database operation completed", context: traceContext, fields: [
                    "operation_duration_ms": String(format: "%.2f", duration * 1000)
                ])
                
                // Record performance metric
                TracingService.shared.recordMetric(
                    PerformanceMetrics(
                        operationName: "Persistence.\(name)",
                        duration: duration,
                        success: true
                    )
                )
                
                return result
                
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                
                logger.error("Database operation failed", context: traceContext, fields: [
                    "error": error.localizedDescription,
                    "operation_duration_ms": String(format: "%.2f", duration * 1000)
                ])
                
                // Record failure metric
                TracingService.shared.recordMetric(
                    PerformanceMetrics(
                        operationName: "Persistence.\(name)",
                        duration: duration,
                        success: false
                    )
                )
                
                throw error
            }
        }
    }
}

// MARK: - Network Operations Tracing

/// Wrapper for network operations with tracing
class TracedNetworkManager: ObservableObject {
    static let shared = TracedNetworkManager()
    private let logger = StructuredLogger.shared
    private let session = URLSession.shared
    
    private init() {}
    
    /// Execute a network request with comprehensive tracing
    func executeRequest(
        _ request: URLRequest,
        context: TraceContext? = nil
    ) async throws -> (Data, URLResponse) {
        return try await TracingService.shared.traced(
            "Network.request",
            parentContext: context,
            tags: [
                "service": "NetworkManager",
                "operation_type": "http_request",
                "method": request.httpMethod ?? "GET",
                "url": request.url?.absoluteString ?? "unknown",
                "host": request.url?.host ?? "unknown"
            ]
        ) { traceContext in
            
            logger.info("Starting network request", context: traceContext, fields: [
                "method": request.httpMethod ?? "GET",
                "url": request.url?.absoluteString ?? "unknown",
                "headers_count": String(request.allHTTPHeaderFields?.count ?? 0)
            ])
            
            let startTime = Date()
            
            do {
                let (data, response) = try await session.data(for: request)
                let duration = Date().timeIntervalSince(startTime)
                
                var statusCode = 0
                var responseSize = data.count
                
                if let httpResponse = response as? HTTPURLResponse {
                    statusCode = httpResponse.statusCode
                }
                
                logger.info("Network request completed", context: traceContext, fields: [
                    "status_code": String(statusCode),
                    "response_size_bytes": String(responseSize),
                    "request_duration_ms": String(format: "%.2f", duration * 1000)
                ])
                
                // Record performance metric
                TracingService.shared.recordMetric(
                    PerformanceMetrics(
                        operationName: "Network.request",
                        duration: duration,
                        success: statusCode < 400,
                        tags: [
                            "method": request.httpMethod ?? "GET",
                            "status_code": String(statusCode),
                            "host": request.url?.host ?? "unknown"
                        ]
                    )
                )
                
                return (data, response)
                
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                
                logger.error("Network request failed", context: traceContext, fields: [
                    "error": error.localizedDescription,
                    "request_duration_ms": String(format: "%.2f", duration * 1000)
                ])
                
                // Record failure metric
                TracingService.shared.recordMetric(
                    PerformanceMetrics(
                        operationName: "Network.request",
                        duration: duration,
                        success: false,
                        tags: [
                            "method": request.httpMethod ?? "GET",
                            "error_type": String(describing: type(of: error)),
                            "host": request.url?.host ?? "unknown"
                        ]
                    )
                )
                
                throw error
            }
        }
    }
}

// MARK: - File System Operations Tracing

/// Wrapper for file system operations with tracing
class TracedFileManager: ObservableObject {
    static let shared = TracedFileManager()
    private let fileManager = FileManager.default
    private let logger = StructuredLogger.shared
    
    private init() {}
    
    /// Read file with tracing
    func readFile(
        at url: URL,
        context: TraceContext? = nil
    ) async throws -> Data {
        return try await TracingService.shared.traced(
            "FileSystem.readFile",
            parentContext: context,
            tags: [
                "service": "FileManager",
                "operation_type": "read",
                "file_path": url.path,
                "file_name": url.lastPathComponent,
                "file_extension": url.pathExtension
            ]
        ) { traceContext in
            
            logger.info("Reading file", context: traceContext, fields: [
                "file_path": url.path,
                "file_exists": String(fileManager.fileExists(atPath: url.path))
            ])
            
            let startTime = Date()
            
            do {
                let data = try Data(contentsOf: url)
                let duration = Date().timeIntervalSince(startTime)
                
                logger.info("File read completed", context: traceContext, fields: [
                    "file_size_bytes": String(data.count),
                    "read_duration_ms": String(format: "%.2f", duration * 1000)
                ])
                
                // Record performance metric
                TracingService.shared.recordMetric(
                    PerformanceMetrics(
                        operationName: "FileSystem.readFile",
                        duration: duration,
                        success: true,
                        tags: [
                            "file_size_kb": String(data.count / 1024),
                            "file_extension": url.pathExtension
                        ]
                    )
                )
                
                return data
                
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                
                logger.error("File read failed", context: traceContext, fields: [
                    "error": error.localizedDescription,
                    "read_duration_ms": String(format: "%.2f", duration * 1000)
                ])
                
                // Record failure metric
                TracingService.shared.recordMetric(
                    PerformanceMetrics(
                        operationName: "FileSystem.readFile",
                        duration: duration,
                        success: false,
                        tags: [
                            "error_type": String(describing: type(of: error)),
                            "file_extension": url.pathExtension
                        ]
                    )
                )
                
                throw error
            }
        }
    }
    
    /// Write file with tracing
    func writeFile(
        _ data: Data,
        to url: URL,
        context: TraceContext? = nil
    ) async throws {
        try await TracingService.shared.traced(
            "FileSystem.writeFile",
            parentContext: context,
            tags: [
                "service": "FileManager",
                "operation_type": "write",
                "file_path": url.path,
                "file_name": url.lastPathComponent,
                "file_extension": url.pathExtension,
                "data_size_bytes": String(data.count)
            ]
        ) { traceContext in
            
            logger.info("Writing file", context: traceContext, fields: [
                "file_path": url.path,
                "data_size_bytes": String(data.count)
            ])
            
            let startTime = Date()
            
            do {
                try data.write(to: url)
                let duration = Date().timeIntervalSince(startTime)
                
                logger.info("File write completed", context: traceContext, fields: [
                    "write_duration_ms": String(format: "%.2f", duration * 1000)
                ])
                
                // Record performance metric
                TracingService.shared.recordMetric(
                    PerformanceMetrics(
                        operationName: "FileSystem.writeFile",
                        duration: duration,
                        success: true,
                        tags: [
                            "file_size_kb": String(data.count / 1024),
                            "file_extension": url.pathExtension
                        ]
                    )
                )
                
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                
                logger.error("File write failed", context: traceContext, fields: [
                    "error": error.localizedDescription,
                    "write_duration_ms": String(format: "%.2f", duration * 1000)
                ])
                
                // Record failure metric
                TracingService.shared.recordMetric(
                    PerformanceMetrics(
                        operationName: "FileSystem.writeFile",
                        duration: duration,
                        success: false,
                        tags: [
                            "error_type": String(describing: type(of: error)),
                            "file_size_kb": String(data.count / 1024),
                            "file_extension": url.pathExtension
                        ]
                    )
                )
                
                throw error
            }
        }
    }
}
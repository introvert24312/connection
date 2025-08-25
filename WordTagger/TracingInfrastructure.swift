import Foundation
import Combine
import SwiftUI

// MARK: - Core Trace Infrastructure

/// Distributed trace context that propagates across all service boundaries
public struct TraceContext {
    public let traceId: String
    public let spanId: String
    public let parentSpanId: String?
    public let operationName: String
    public let startTime: Date
    public let tags: [String: String]
    public let baggage: [String: String]
    
    public init(
        operationName: String,
        parentContext: TraceContext? = nil,
        tags: [String: String] = [:],
        baggage: [String: String] = [:]
    ) {
        if let parent = parentContext {
            self.traceId = parent.traceId
            self.parentSpanId = parent.spanId
        } else {
            self.traceId = Self.generateTraceId()
            self.parentSpanId = nil
        }
        
        self.spanId = Self.generateSpanId()
        self.operationName = operationName
        self.startTime = Date()
        self.tags = tags
        self.baggage = baggage
    }
    
    private static func generateTraceId() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
    }
    
    private static func generateSpanId() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
    }
    
    public func withTags(_ newTags: [String: String]) -> TraceContext {
        return TraceContext(
            traceId: traceId,
            spanId: spanId,
            parentSpanId: parentSpanId,
            operationName: operationName,
            startTime: startTime,
            tags: tags.merging(newTags) { _, new in new },
            baggage: baggage
        )
    }
    
    public func withBaggage(_ newBaggage: [String: String]) -> TraceContext {
        return TraceContext(
            traceId: traceId,
            spanId: spanId,
            parentSpanId: parentSpanId,
            operationName: operationName,
            startTime: startTime,
            tags: tags,
            baggage: baggage.merging(newBaggage) { _, new in new }
        )
    }
    
    private init(
        traceId: String,
        spanId: String,
        parentSpanId: String?,
        operationName: String,
        startTime: Date,
        tags: [String: String],
        baggage: [String: String]
    ) {
        self.traceId = traceId
        self.spanId = spanId
        self.parentSpanId = parentSpanId
        self.operationName = operationName
        self.startTime = startTime
        self.tags = tags
        self.baggage = baggage
    }
}

/// Completed trace span with timing and outcome information
public struct Span: Identifiable {
    public let id = UUID()
    public let context: TraceContext
    public let endTime: Date
    public let duration: TimeInterval
    public let outcome: SpanOutcome
    public let logs: [SpanLog]
    public let metrics: [String: Double]
    
    public init(
        context: TraceContext,
        outcome: SpanOutcome,
        logs: [SpanLog] = [],
        metrics: [String: Double] = [:]
    ) {
        self.context = context
        self.endTime = Date()
        self.duration = endTime.timeIntervalSince(context.startTime)
        self.outcome = outcome
        self.logs = logs
        self.metrics = metrics
    }
}

public enum SpanOutcome {
    case success
    case error(Error)
    case cancelled
    
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    
    public var errorMessage: String? {
        if case .error(let error) = self {
            return error.localizedDescription
        }
        return nil
    }
}

public struct SpanLog {
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    public let fields: [String: String]
    
    public init(level: LogLevel, message: String, fields: [String: String] = [:]) {
        self.timestamp = Date()
        self.level = level
        self.message = message
        self.fields = fields
    }
}

public enum LogLevel: String, CaseIterable {
    case trace = "TRACE"
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    
    public var priority: Int {
        switch self {
        case .trace: return 0
        case .debug: return 1
        case .info: return 2
        case .warn: return 3
        case .error: return 4
        }
    }
}

// MARK: - Performance Metrics

public struct PerformanceMetrics {
    public let operationName: String
    public let duration: TimeInterval
    public let success: Bool
    public let tags: [String: String]
    public let timestamp: Date
    public let memoryUsageMB: Double?
    public let cpuUsage: Double?
    
    public init(
        operationName: String,
        duration: TimeInterval,
        success: Bool,
        tags: [String: String] = [:],
        memoryUsageMB: Double? = nil,
        cpuUsage: Double? = nil
    ) {
        self.operationName = operationName
        self.duration = duration
        self.success = success
        self.tags = tags
        self.timestamp = Date()
        self.memoryUsageMB = memoryUsageMB
        self.cpuUsage = cpuUsage
    }
}

// MARK: - Structured Logger

@MainActor
public class StructuredLogger: ObservableObject {
    public static let shared = StructuredLogger()
    
    @Published public private(set) var recentLogs: [SpanLog] = []
    @Published public private(set) var logCounts: [LogLevel: Int] = [:]
    
    private let maxRecentLogs = 1000
    private let logQueue = DispatchQueue(label: "com.wordtagger.logging", qos: .utility)
    
    private init() {
        // Initialize log counts
        for level in LogLevel.allCases {
            logCounts[level] = 0
        }
    }
    
    public func log(
        _ level: LogLevel,
        _ message: String,
        context: TraceContext? = nil,
        fields: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        var enrichedFields = fields
        enrichedFields["file"] = URL(fileURLWithPath: file).lastPathComponent
        enrichedFields["function"] = function
        enrichedFields["line"] = String(line)
        
        if let context = context {
            enrichedFields["trace_id"] = context.traceId
            enrichedFields["span_id"] = context.spanId
            enrichedFields["operation"] = context.operationName
            
            if let parentSpanId = context.parentSpanId {
                enrichedFields["parent_span_id"] = parentSpanId
            }
        }
        
        let logEntry = SpanLog(level: level, message: message, fields: enrichedFields)
        
        logQueue.async { [weak self] in
            // Write to console with structured format
            self?.writeToConsole(logEntry)
            
            // Update in-memory state on main actor
            Task { @MainActor in
                self?.addToRecentLogs(logEntry)
                self?.updateLogCounts(level)
            }
        }
    }
    
    private func writeToConsole(_ log: SpanLog) {
        let timestamp = DateFormatter.iso8601WithMilliseconds.string(from: log.timestamp)
        let level = log.level.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0)
        
        var output = "[\(timestamp)] \(level) \(log.message)"
        
        if !log.fields.isEmpty {
            let fieldsStr = log.fields
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            output += " | \(fieldsStr)"
        }
        
        print(output)
    }
    
    private func addToRecentLogs(_ log: SpanLog) {
        recentLogs.append(log)
        if recentLogs.count > maxRecentLogs {
            recentLogs.removeFirst(recentLogs.count - maxRecentLogs)
        }
    }
    
    private func updateLogCounts(_ level: LogLevel) {
        logCounts[level, default: 0] += 1
    }
    
    // Convenience methods
    public func trace(_ message: String, context: TraceContext? = nil, fields: [String: String] = [:]) {
        log(.trace, message, context: context, fields: fields)
    }
    
    public func debug(_ message: String, context: TraceContext? = nil, fields: [String: String] = [:]) {
        log(.debug, message, context: context, fields: fields)
    }
    
    public func info(_ message: String, context: TraceContext? = nil, fields: [String: String] = [:]) {
        log(.info, message, context: context, fields: fields)
    }
    
    public func warn(_ message: String, context: TraceContext? = nil, fields: [String: String] = [:]) {
        log(.warn, message, context: context, fields: fields)
    }
    
    public func error(_ message: String, context: TraceContext? = nil, fields: [String: String] = [:]) {
        log(.error, message, context: context, fields: fields)
    }
}

// MARK: - Tracing Service

@MainActor
public class TracingService: ObservableObject {
    public static let shared = TracingService()
    
    @Published public private(set) var activeSpans: [String: TraceContext] = [:]
    @Published public private(set) var completedSpans: [Span] = []
    @Published public private(set) var metrics: [PerformanceMetrics] = []
    
    private let logger = StructuredLogger.shared
    private let maxCompletedSpans = 10000
    private let maxMetrics = 5000
    
    private init() {}
    
    /// Start a new trace span
    public func startSpan(
        _ operationName: String,
        parentContext: TraceContext? = nil,
        tags: [String: String] = [:]
    ) -> TraceContext {
        let context = TraceContext(
            operationName: operationName,
            parentContext: parentContext,
            tags: tags
        )
        
        activeSpans[context.spanId] = context
        
        logger.debug("Started span", context: context, fields: [
            "parent_span": parentContext?.spanId ?? "none",
            "tags_count": String(tags.count)
        ])
        
        return context
    }
    
    /// Finish a trace span
    public func finishSpan(
        _ context: TraceContext,
        outcome: SpanOutcome = .success,
        logs: [SpanLog] = [],
        metrics: [String: Double] = [:]
    ) {
        activeSpans.removeValue(forKey: context.spanId)
        
        let span = Span(context: context, outcome: outcome, logs: logs, metrics: metrics)
        completedSpans.append(span)
        
        // Trim completed spans if needed
        if completedSpans.count > maxCompletedSpans {
            completedSpans.removeFirst(completedSpans.count - maxCompletedSpans)
        }
        
        // Record performance metric
        let perfMetric = PerformanceMetrics(
            operationName: context.operationName,
            duration: span.duration,
            success: span.outcome.isSuccess,
            tags: context.tags
        )
        recordMetric(perfMetric)
        
        let level: LogLevel = span.outcome.isSuccess ? .debug : .error
        let message = span.outcome.isSuccess ? "Finished span" : "Span failed"
        
        logger.log(level, message, context: context, fields: [
            "duration_ms": String(format: "%.2f", span.duration * 1000),
            "success": String(span.outcome.isSuccess),
            "error": span.outcome.errorMessage ?? ""
        ])
    }
    
    /// Execute an operation with automatic span lifecycle
    public func traced<T>(
        _ operationName: String,
        parentContext: TraceContext? = nil,
        tags: [String: String] = [:],
        operation: @escaping (TraceContext) async throws -> T
    ) async throws -> T {
        let context = startSpan(operationName, parentContext: parentContext, tags: tags)
        
        do {
            let result = try await operation(context)
            finishSpan(context, outcome: .success)
            return result
        } catch {
            finishSpan(context, outcome: .error(error))
            throw error
        }
    }
    
    /// Execute an operation with automatic span lifecycle (non-throwing version)
    public func traced<T>(
        _ operationName: String,
        parentContext: TraceContext? = nil,
        tags: [String: String] = [:],
        operation: @escaping (TraceContext) async -> T
    ) async -> T {
        let context = startSpan(operationName, parentContext: parentContext, tags: tags)
        
        let result = await operation(context)
        finishSpan(context, outcome: .success)
        return result
    }
    
    /// Record a performance metric
    public func recordMetric(_ metric: PerformanceMetrics) {
        metrics.append(metric)
        
        // Trim metrics if needed
        if metrics.count > maxMetrics {
            metrics.removeFirst(metrics.count - maxMetrics)
        }
        
        logger.debug("Recorded metric", fields: [
            "operation": metric.operationName,
            "duration_ms": String(format: "%.2f", metric.duration * 1000),
            "success": String(metric.success)
        ])
    }
    
    /// Get trace tree for a specific trace ID
    public func getTraceTree(traceId: String) -> [Span] {
        return completedSpans.filter { $0.context.traceId == traceId }
    }
    
    /// Get metrics summary for an operation
    public func getMetricsSummary(operationName: String) -> OperationMetricsSummary {
        let operationMetrics = metrics.filter { $0.operationName == operationName }
        
        guard !operationMetrics.isEmpty else {
            return OperationMetricsSummary(
                operationName: operationName,
                totalCalls: 0,
                successRate: 0.0,
                avgDuration: 0.0,
                p50Duration: 0.0,
                p95Duration: 0.0,
                p99Duration: 0.0
            )
        }
        
        let durations = operationMetrics.map { $0.duration }.sorted()
        let successCount = operationMetrics.filter { $0.success }.count
        
        return OperationMetricsSummary(
            operationName: operationName,
            totalCalls: operationMetrics.count,
            successRate: Double(successCount) / Double(operationMetrics.count),
            avgDuration: durations.reduce(0, +) / Double(durations.count),
            p50Duration: percentile(durations, 0.5),
            p95Duration: percentile(durations, 0.95),
            p99Duration: percentile(durations, 0.99)
        )
    }
    
    private func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0.0 }
        let index = Int(Double(values.count - 1) * p)
        return values[index]
    }
}

public struct OperationMetricsSummary {
    public let operationName: String
    public let totalCalls: Int
    public let successRate: Double
    public let avgDuration: TimeInterval
    public let p50Duration: TimeInterval
    public let p95Duration: TimeInterval
    public let p99Duration: TimeInterval
}

// MARK: - Extensions and Utilities

extension DateFormatter {
    static let iso8601WithMilliseconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter
    }()
}

// MARK: - NotificationCenter Integration

extension NotificationCenter {
    /// Post notification with trace context
    public func post(
        name: NSNotification.Name,
        object: Any?,
        userInfo: [AnyHashable: Any]? = nil,
        context: TraceContext
    ) {
        var enrichedUserInfo = userInfo ?? [:]
        enrichedUserInfo["trace_id"] = context.traceId
        enrichedUserInfo["span_id"] = context.spanId
        enrichedUserInfo["operation"] = context.operationName
        
        post(name: name, object: object, userInfo: enrichedUserInfo)
        
        StructuredLogger.shared.trace("Posted notification with trace context", context: context, fields: [
            "notification": name.rawValue,
            "object_type": String(describing: type(of: object))
        ])
    }
    
    /// Extract trace context from notification
    public func extractTraceContext(from notification: Notification) -> TraceContext? {
        guard let userInfo = notification.userInfo,
              let traceId = userInfo["trace_id"] as? String,
              let spanId = userInfo["span_id"] as? String,
              let operationName = userInfo["operation"] as? String else {
            return nil
        }
        
        return TraceContext(operationName: operationName)
    }
}

// MARK: - Task Extensions for Trace Propagation

extension Task where Success == Void, Failure == Never {
    /// Create a task with trace context propagation
    public static func traced(
        _ context: TraceContext,
        priority: TaskPriority? = nil,
        operation: @escaping (TraceContext) async -> Void
    ) -> Task {
        return Task(priority: priority) {
            await operation(context)
        }
    }
}

extension Task where Failure == Never {
    /// Create a task with trace context propagation and return value
    public static func traced<T>(
        _ context: TraceContext,
        priority: TaskPriority? = nil,
        operation: @escaping (TraceContext) async -> T
    ) -> Task<T, Never> {
        return Task<T, Never>(priority: priority) {
            await operation(context)
        }
    }
}

extension Task where Failure == Error {
    /// Create a throwing task with trace context propagation
    public static func traced<T>(
        _ context: TraceContext,
        priority: TaskPriority? = nil,
        operation: @escaping (TraceContext) async throws -> T
    ) -> Task<T, Error> {
        return Task<T, Error>(priority: priority) {
            try await operation(context)
        }
    }
}
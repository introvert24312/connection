//
//  PerformanceOptimizations.swift
//  WordTagger
//
//  Created by Kiro on 2025/8/19.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Context Menu Performance Optimizations

/// Optimized context menu manager that handles creation and disposal efficiently
class ContextMenuManager: ObservableObject {
    static let shared = ContextMenuManager()
    
    @Published private var activeMenus: [String: WeakContextMenuReference] = [:]
    @Published private var menuPool: [NodeContextMenuView] = []
    
    private let maxPoolSize = 5
    private let cleanupInterval: TimeInterval = 30.0
    private var cleanupTimer: Timer?
    
    private init() {
        setupCleanupTimer()
    }
    
    deinit {
        cleanupTimer?.invalidate()
    }
    
    /// Creates or reuses a context menu for optimal performance
    func getContextMenu(for node: Node, onEditCommand: @escaping () -> Void, onEditName: @escaping () -> Void, onDelete: @escaping () -> Void) -> NodeContextMenuView {
        let menuId = "menu-\(node.id)"
        
        // Check if we have an active menu for this node
        if let existingRef = activeMenus[menuId],
           let existingMenu = existingRef.menu {
            return existingMenu
        }
        
        // Try to reuse from pool
        let menu: NodeContextMenuView
        if !menuPool.isEmpty {
            menu = menuPool.removeFirst()
            menu.updateNode(node, onEditCommand: onEditCommand, onEditName: onEditName, onDelete: onDelete)
        } else {
            menu = NodeContextMenuView(node: node, onEditCommand: onEditCommand, onEditName: onEditName, onDelete: onDelete)
        }
        
        // Track the active menu
        activeMenus[menuId] = WeakContextMenuReference(menu: menu)
        
        return menu
    }
    
    /// Returns a context menu to the pool for reuse
    func returnContextMenu(_ menu: NodeContextMenuView, for node: Node) {
        let menuId = "menu-\(node.id)"
        activeMenus.removeValue(forKey: menuId)
        
        // Add to pool if there's space
        if menuPool.count < maxPoolSize {
            menu.reset() // Clear any state
            menuPool.append(menu)
        }
        // If pool is full, let the menu be deallocated
    }
    
    /// Forces cleanup of all cached menus
    func clearCache() {
        activeMenus.removeAll()
        menuPool.removeAll()
    }
    
    private func setupCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            self?.performCleanup()
        }
    }
    
    private func performCleanup() {
        // Remove dead references
        activeMenus = activeMenus.compactMapValues { ref in
            ref.menu != nil ? ref : nil
        }
        
        // Limit pool size
        if menuPool.count > maxPoolSize {
            menuPool = Array(menuPool.prefix(maxPoolSize))
        }
    }
}

/// Weak reference wrapper for context menus
private class WeakContextMenuReference {
    weak var menu: NodeContextMenuView?
    
    init(menu: NodeContextMenuView) {
        self.menu = menu
    }
}

// MARK: - NodeContextMenuView Performance Extensions

extension NodeContextMenuView {
    /// Updates the menu with new node data for reuse
    func updateNode(_ node: Node, onEditCommand: @escaping () -> Void, onEditName: @escaping () -> Void, onDelete: @escaping () -> Void) {
        // This would update the internal state of the menu
        // Implementation depends on the actual NodeContextMenuView structure
    }
    
    /// Resets the menu state for pool reuse
    func reset() {
        // Clear any cached state or animations
        // Implementation depends on the actual NodeContextMenuView structure
    }
}

// MARK: - Git Operations Performance Optimizations

/// Optimized Git operations manager with background processing and caching
class OptimizedGitOperations: ObservableObject {
    @Published var isOperationInProgress: Bool = false
    @Published var operationQueue: [GitOperation] = []
    
    private let operationQueue_internal = DispatchQueue(label: "com.wordtagger.git.operations", qos: .userInitiated)
    private let backgroundQueue = DispatchQueue(label: "com.wordtagger.git.background", qos: .background)
    
    // Operation caching
    private var operationCache: [String: GitOperationResult] = [:]
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutes
    private var cacheTimestamps: [String: Date] = [:]
    
    // Batch operation support
    private var pendingOperations: [GitOperation] = []
    private var batchTimer: Timer?
    private let batchDelay: TimeInterval = 2.0 // Wait 2 seconds before executing batch
    
    /// Executes Git operations on background thread to avoid blocking UI
    func executeOperation(_ operation: GitOperation, completion: @escaping (Result<GitOperationResult, Error>) -> Void) {
        // Check cache first
        let cacheKey = operation.cacheKey
        if let cachedResult = getCachedResult(for: cacheKey) {
            DispatchQueue.main.async {
                completion(.success(cachedResult))
            }
            return
        }
        
        // Execute on background thread
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isOperationInProgress = true
            }
            
            do {
                let result = try self.performGitOperation(operation)
                
                // Cache the result
                self.cacheResult(result, for: cacheKey)
                
                DispatchQueue.main.async {
                    self.isOperationInProgress = false
                    completion(.success(result))
                }
            } catch {
                DispatchQueue.main.async {
                    self.isOperationInProgress = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Batches multiple operations for efficient execution
    func batchOperation(_ operation: GitOperation) {
        pendingOperations.append(operation)
        
        // Reset batch timer
        batchTimer?.invalidate()
        batchTimer = Timer.scheduledTimer(withTimeInterval: batchDelay, repeats: false) { [weak self] _ in
            self?.executeBatchOperations()
        }
    }
    
    private func executeBatchOperations() {
        guard !pendingOperations.isEmpty else { return }
        
        let operations = pendingOperations
        pendingOperations.removeAll()
        
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isOperationInProgress = true
            }
            
            // Execute operations in batch
            for operation in operations {
                do {
                    let result = try self.performGitOperation(operation)
                    self.cacheResult(result, for: operation.cacheKey)
                } catch {
                    print("Batch operation failed: \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.isOperationInProgress = false
            }
        }
    }
    
    private func getCachedResult(for key: String) -> GitOperationResult? {
        guard let result = operationCache[key],
              let timestamp = cacheTimestamps[key],
              Date().timeIntervalSince(timestamp) < cacheExpirationTime else {
            // Cache expired or doesn't exist
            operationCache.removeValue(forKey: key)
            cacheTimestamps.removeValue(forKey: key)
            return nil
        }
        
        return result
    }
    
    private func cacheResult(_ result: GitOperationResult, for key: String) {
        operationCache[key] = result
        cacheTimestamps[key] = Date()
        
        // Cleanup old cache entries
        cleanupExpiredCache()
    }
    
    private func cleanupExpiredCache() {
        let now = Date()
        let expiredKeys = cacheTimestamps.compactMap { (key, timestamp) in
            now.timeIntervalSince(timestamp) > cacheExpirationTime ? key : nil
        }
        
        for key in expiredKeys {
            operationCache.removeValue(forKey: key)
            cacheTimestamps.removeValue(forKey: key)
        }
    }
    
    private func performGitOperation(_ operation: GitOperation) throws -> GitOperationResult {
        // Simulate Git operation execution
        // In real implementation, this would call actual Git commands
        switch operation.type {
        case .commit:
            return GitOperationResult(type: .commit, success: true, message: "Commit successful")
        case .push:
            return GitOperationResult(type: .push, success: true, message: "Push successful")
        case .status:
            return GitOperationResult(type: .status, success: true, message: "Status retrieved")
        case .pull:
            return GitOperationResult(type: .pull, success: true, message: "Pull successful")
        }
    }
}

// MARK: - Git Operation Types

struct GitOperation {
    enum OperationType {
        case commit(message: String)
        case push
        case status
        case pull
    }
    
    let type: OperationType
    let timestamp: Date
    
    var cacheKey: String {
        switch type {
        case .commit(let message):
            return "commit-\(message.hashValue)"
        case .push:
            return "push-\(timestamp.timeIntervalSince1970)"
        case .status:
            return "status"
        case .pull:
            return "pull-\(timestamp.timeIntervalSince1970)"
        }
    }
    
    init(type: OperationType) {
        self.type = type
        self.timestamp = Date()
    }
}

struct GitOperationResult {
    let type: GitOperation.OperationType
    let success: Bool
    let message: String
    let timestamp: Date
    
    init(type: GitOperation.OperationType, success: Bool, message: String) {
        self.type = type
        self.success = success
        self.message = message
        self.timestamp = Date()
    }
}

// MARK: - Memory Management Optimizations

/// Memory manager for tracking and optimizing memory usage
class MemoryManager: ObservableObject {
    static let shared = MemoryManager()
    
    @Published var memoryUsage: MemoryUsage = MemoryUsage()
    @Published var isMemoryPressureHigh: Bool = false
    
    private let memoryPressureThreshold: Int64 = 500 * 1024 * 1024 // 500MB
    private let cleanupThreshold: Int64 = 750 * 1024 * 1024 // 750MB
    
    private var memoryTimer: Timer?
    private var weakReferences: [WeakReference] = []
    
    private init() {
        startMemoryMonitoring()
        setupMemoryPressureNotifications()
    }
    
    deinit {
        memoryTimer?.invalidate()
    }
    
    /// Registers an object for memory management
    func register<T: AnyObject>(_ object: T) {
        weakReferences.append(WeakReference(object))
        cleanupDeadReferences()
    }
    
    /// Forces memory cleanup
    func performMemoryCleanup() {
        // Clean up dead references
        cleanupDeadReferences()
        
        // Clear caches
        ContextMenuManager.shared.clearCache()
        
        // Force garbage collection
        autoreleasepool {
            // Trigger memory cleanup
        }
        
        // Update memory usage
        updateMemoryUsage()
    }
    
    private func startMemoryMonitoring() {
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateMemoryUsage()
            self?.checkMemoryPressure()
        }
    }
    
    private func updateMemoryUsage() {
        let usage = getCurrentMemoryUsage()
        DispatchQueue.main.async {
            self.memoryUsage = usage
        }
    }
    
    private func checkMemoryPressure() {
        let currentUsage = getCurrentMemoryUsage().resident
        let wasHighPressure = isMemoryPressureHigh
        
        DispatchQueue.main.async {
            self.isMemoryPressureHigh = currentUsage > self.memoryPressureThreshold
            
            // If memory pressure is high and wasn't before, trigger cleanup
            if self.isMemoryPressureHigh && !wasHighPressure {
                self.performMemoryCleanup()
            }
            
            // If memory usage is critically high, force aggressive cleanup
            if currentUsage > self.cleanupThreshold {
                self.performAggressiveCleanup()
            }
        }
    }
    
    private func performAggressiveCleanup() {
        // More aggressive cleanup measures
        ContextMenuManager.shared.clearCache()
        
        // Clear any other caches
        URLCache.shared.removeAllCachedResponses()
        
        // Notify other components to clean up
        NotificationCenter.default.post(name: .memoryPressureHigh, object: nil)
    }
    
    private func setupMemoryPressureNotifications() {
        // Listen for system memory pressure notifications
        NotificationCenter.default.addObserver(
            forName: NSApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.performMemoryCleanup()
        }
    }
    
    private func cleanupDeadReferences() {
        weakReferences = weakReferences.filter { $0.object != nil }
    }
    
    private func getCurrentMemoryUsage() -> MemoryUsage {
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
            return MemoryUsage(
                resident: Int64(info.resident_size),
                virtual: Int64(info.virtual_size)
            )
        } else {
            return MemoryUsage()
        }
    }
}

// MARK: - Memory Management Types

struct MemoryUsage {
    let resident: Int64
    let virtual: Int64
    
    init(resident: Int64 = 0, virtual: Int64 = 0) {
        self.resident = resident
        self.virtual = virtual
    }
    
    var residentMB: Double {
        return Double(resident) / (1024 * 1024)
    }
    
    var virtualMB: Double {
        return Double(virtual) / (1024 * 1024)
    }
}

private class WeakReference {
    weak var object: AnyObject?
    
    init(_ object: AnyObject) {
        self.object = object
    }
}

// MARK: - Performance Monitoring

/// Performance monitor for tracking operation times and identifying bottlenecks
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    @Published var metrics: [PerformanceMetric] = []
    @Published var averageOperationTimes: [String: TimeInterval] = [:]
    
    private let maxMetricsCount = 1000
    private var operationStartTimes: [String: Date] = [:]
    
    private init() {}
    
    /// Starts timing an operation
    func startOperation(_ operationName: String, id: String = UUID().uuidString) -> String {
        let operationId = "\(operationName)-\(id)"
        operationStartTimes[operationId] = Date()
        return operationId
    }
    
    /// Ends timing an operation and records the metric
    func endOperation(_ operationId: String) {
        guard let startTime = operationStartTimes.removeValue(forKey: operationId) else {
            return
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        let metric = PerformanceMetric(
            operationName: String(operationId.split(separator: "-").first ?? "unknown"),
            duration: duration,
            timestamp: endTime
        )
        
        DispatchQueue.main.async {
            self.metrics.append(metric)
            
            // Keep metrics count manageable
            if self.metrics.count > self.maxMetricsCount {
                self.metrics.removeFirst(self.metrics.count - self.maxMetricsCount)
            }
            
            self.updateAverages()
        }
    }
    
    /// Records a metric directly
    func recordMetric(_ operationName: String, duration: TimeInterval) {
        let metric = PerformanceMetric(
            operationName: operationName,
            duration: duration,
            timestamp: Date()
        )
        
        DispatchQueue.main.async {
            self.metrics.append(metric)
            
            if self.metrics.count > self.maxMetricsCount {
                self.metrics.removeFirst(self.metrics.count - self.maxMetricsCount)
            }
            
            self.updateAverages()
        }
    }
    
    /// Gets performance statistics for an operation
    func getStatistics(for operationName: String) -> PerformanceStatistics? {
        let operationMetrics = metrics.filter { $0.operationName == operationName }
        guard !operationMetrics.isEmpty else { return nil }
        
        let durations = operationMetrics.map { $0.duration }
        let average = durations.reduce(0, +) / Double(durations.count)
        let min = durations.min() ?? 0
        let max = durations.max() ?? 0
        
        return PerformanceStatistics(
            operationName: operationName,
            count: operationMetrics.count,
            averageDuration: average,
            minDuration: min,
            maxDuration: max
        )
    }
    
    private func updateAverages() {
        let grouped = Dictionary(grouping: metrics) { $0.operationName }
        
        averageOperationTimes = grouped.mapValues { metrics in
            let total = metrics.reduce(0) { $0 + $1.duration }
            return total / Double(metrics.count)
        }
    }
}

// MARK: - Performance Types

struct PerformanceMetric {
    let operationName: String
    let duration: TimeInterval
    let timestamp: Date
}

struct PerformanceStatistics {
    let operationName: String
    let count: Int
    let averageDuration: TimeInterval
    let minDuration: TimeInterval
    let maxDuration: TimeInterval
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let memoryPressureHigh = Notification.Name("memoryPressureHigh")
    static let performanceThresholdExceeded = Notification.Name("performanceThresholdExceeded")
}

// MARK: - Performance Measurement Utilities

/// Utility for measuring performance of code blocks
func measurePerformance<T>(operation: String, block: () throws -> T) rethrows -> T {
    let operationId = PerformanceMonitor.shared.startOperation(operation)
    defer {
        PerformanceMonitor.shared.endOperation(operationId)
    }
    
    return try block()
}

/// Async version of performance measurement
func measurePerformanceAsync<T>(operation: String, block: () async throws -> T) async rethrows -> T {
    let operationId = PerformanceMonitor.shared.startOperation(operation)
    defer {
        PerformanceMonitor.shared.endOperation(operationId)
    }
    
    return try await block()
}
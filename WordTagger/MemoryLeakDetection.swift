//
//  MemoryLeakDetection.swift
//  WordTagger
//
//  Created by Kiro on 2025/8/19.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Memory Leak Detection

/// Memory leak detector that tracks object lifecycles
class MemoryLeakDetector: ObservableObject {
    static let shared = MemoryLeakDetector()
    
    @Published var trackedObjects: [TrackedObject] = []
    @Published var potentialLeaks: [PotentialLeak] = []
    @Published var isEnabled: Bool = false
    
    private var objectRegistry: [ObjectIdentifier: TrackedObject] = [:]
    private var detectionTimer: Timer?
    private let detectionInterval: TimeInterval = 30.0 // Check every 30 seconds
    
    private init() {
        #if DEBUG
        isEnabled = true
        startLeakDetection()
        #endif
    }
    
    deinit {
        detectionTimer?.invalidate()
    }
    
    /// Registers an object for leak detection
    func track<T: AnyObject>(_ object: T, name: String? = nil) {
        guard isEnabled else { return }
        
        let identifier = ObjectIdentifier(object)
        let objectName = name ?? String(describing: type(of: object))
        
        let trackedObject = TrackedObject(
            identifier: identifier,
            name: objectName,
            creationTime: Date(),
            weakReference: WeakObjectReference(object)
        )
        
        DispatchQueue.main.async {
            self.objectRegistry[identifier] = trackedObject
            self.trackedObjects.append(trackedObject)
        }
    }
    
    /// Manually marks an object as released (for debugging)
    func markReleased<T: AnyObject>(_ object: T) {
        guard isEnabled else { return }
        
        let identifier = ObjectIdentifier(object)
        
        DispatchQueue.main.async {
            if let trackedObject = self.objectRegistry.removeValue(forKey: identifier) {
                self.trackedObjects.removeAll { $0.identifier == identifier }
                print("✅ Object released: \(trackedObject.name)")
            }
        }
    }
    
    /// Forces leak detection check
    func checkForLeaks() {
        guard isEnabled else { return }
        
        let now = Date()
        let leakThreshold: TimeInterval = 300 // 5 minutes
        var newLeaks: [PotentialLeak] = []
        
        // Check for objects that should have been released
        for trackedObject in trackedObjects {
            if trackedObject.weakReference.object == nil {
                // Object was properly released
                continue
            }
            
            let age = now.timeIntervalSince(trackedObject.creationTime)
            if age > leakThreshold {
                let leak = PotentialLeak(
                    objectName: trackedObject.name,
                    age: age,
                    detectionTime: now
                )
                newLeaks.append(leak)
            }
        }
        
        DispatchQueue.main.async {
            // Remove objects that were properly released
            self.trackedObjects = self.trackedObjects.filter { trackedObject in
                if trackedObject.weakReference.object == nil {
                    self.objectRegistry.removeValue(forKey: trackedObject.identifier)
                    return false
                }
                return true
            }
            
            // Add new potential leaks
            for leak in newLeaks {
                if !self.potentialLeaks.contains(where: { $0.objectName == leak.objectName }) {
                    self.potentialLeaks.append(leak)
                    print("⚠️ Potential memory leak detected: \(leak.objectName) (age: \(leak.age)s)")
                }
            }
        }
    }
    
    /// Clears all tracking data
    func clearTracking() {
        DispatchQueue.main.async {
            self.trackedObjects.removeAll()
            self.potentialLeaks.removeAll()
            self.objectRegistry.removeAll()
        }
    }
    
    private func startLeakDetection() {
        detectionTimer = Timer.scheduledTimer(withTimeInterval: detectionInterval, repeats: true) { [weak self] _ in
            self?.checkForLeaks()
        }
    }
}

// MARK: - Tracked Object Types

struct TrackedObject: Identifiable {
    let id = UUID()
    let identifier: ObjectIdentifier
    let name: String
    let creationTime: Date
    let weakReference: WeakObjectReference
}

struct PotentialLeak: Identifiable {
    let id = UUID()
    let objectName: String
    let age: TimeInterval
    let detectionTime: Date
}

private class WeakObjectReference {
    weak var object: AnyObject?
    
    init(_ object: AnyObject) {
        self.object = object
    }
}

// MARK: - Memory Leak Prevention Extensions

extension KeyboardEventManager {
    /// Optimized cleanup that prevents memory leaks
    func performOptimizedCleanup() {
        // Track this cleanup operation
        MemoryLeakDetector.shared.track(self, name: "KeyboardEventManager")
        
        // Clear all state efficiently
        commandQueue.async { [weak self] in
            DispatchQueue.main.async {
                self?.activeCommands.removeAll()
                self?.commandExecutionState.removeAll()
                self?.executionHistory.removeAll()
                
                // Force cleanup of any retained closures
                self?.cleanupTimer?.invalidate()
                self?.errorRecoveryTimer?.invalidate()
                self?.stateResetTimer?.invalidate()
            }
        }
    }
}

extension GitService {
    /// Optimized cleanup for Git service
    func performOptimizedCleanup() {
        // Track this cleanup operation
        MemoryLeakDetector.shared.track(self, name: "GitService")
        
        // Clear all cached data
        repositoryURL = nil
        credentials = nil
        configuration = nil
        lastError = nil
        
        // Reset published properties
        connectionStatus = .disconnected
        lastSyncDate = nil
        pendingChanges = 0
        isOperationInProgress = false
        operationProgress = nil
        retryCount = 0
        isRetrying = false
    }
}

// MARK: - Performance Optimization Extensions

extension NodeContextMenuView {
    /// Optimized initialization with memory tracking
    static func createOptimized(for node: Node, onEditCommand: @escaping () -> Void, onEditName: @escaping () -> Void, onDelete: @escaping () -> Void) -> NodeContextMenuView {
        let menu = ContextMenuManager.shared.getContextMenu(
            for: node,
            onEditCommand: onEditCommand,
            onEditName: onEditName,
            onDelete: onDelete
        )
        
        // Track for memory leaks
        MemoryLeakDetector.shared.track(menu, name: "NodeContextMenuView-\(node.id)")
        
        return menu
    }
    
    /// Optimized disposal
    func disposeOptimized(for node: Node) {
        ContextMenuManager.shared.returnContextMenu(self, for: node)
        MemoryLeakDetector.shared.markReleased(self)
    }
}

// MARK: - SwiftUI Performance Optimizations

/// Optimized view modifier for performance monitoring
struct PerformanceMonitoringModifier: ViewModifier {
    let operationName: String
    @State private var operationId: String?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                operationId = PerformanceMonitor.shared.startOperation(operationName)
            }
            .onDisappear {
                if let operationId = operationId {
                    PerformanceMonitor.shared.endOperation(operationId)
                }
            }
    }
}

extension View {
    /// Adds performance monitoring to a view
    func monitorPerformance(_ operationName: String) -> some View {
        self.modifier(PerformanceMonitoringModifier(operationName: operationName))
    }
}

// MARK: - Batch Processing Optimizations

/// Batch processor for handling multiple operations efficiently
class BatchProcessor<T>: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var queueSize: Int = 0
    
    private var queue: [T] = []
    private var processor: ([T]) async throws -> Void
    private var batchSize: Int
    private var batchDelay: TimeInterval
    private var processingTimer: Timer?
    
    init(batchSize: Int = 10, batchDelay: TimeInterval = 1.0, processor: @escaping ([T]) async throws -> Void) {
        self.batchSize = batchSize
        self.batchDelay = batchDelay
        self.processor = processor
    }
    
    deinit {
        processingTimer?.invalidate()
    }
    
    /// Adds an item to the batch queue
    func add(_ item: T) {
        queue.append(item)
        queueSize = queue.count
        
        // Process immediately if batch is full
        if queue.count >= batchSize {
            processBatch()
        } else {
            // Schedule delayed processing
            processingTimer?.invalidate()
            processingTimer = Timer.scheduledTimer(withTimeInterval: batchDelay, repeats: false) { [weak self] _ in
                self?.processBatch()
            }
        }
    }
    
    /// Forces immediate processing of the current batch
    func processBatch() {
        guard !queue.isEmpty && !isProcessing else { return }
        
        let batch = queue
        queue.removeAll()
        queueSize = 0
        isProcessing = true
        
        Task {
            do {
                try await processor(batch)
            } catch {
                print("Batch processing error: \(error)")
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
            }
        }
    }
}

// MARK: - Resource Pool

/// Generic resource pool for object reuse
class ResourcePool<T: AnyObject> {
    private var pool: [T] = []
    private let maxSize: Int
    private let factory: () -> T
    private let reset: (T) -> Void
    private let queue = DispatchQueue(label: "com.wordtagger.resourcepool", attributes: .concurrent)
    
    init(maxSize: Int = 10, factory: @escaping () -> T, reset: @escaping (T) -> Void = { _ in }) {
        self.maxSize = maxSize
        self.factory = factory
        self.reset = reset
    }
    
    /// Gets a resource from the pool or creates a new one
    func acquire() -> T {
        return queue.sync {
            if let resource = pool.popLast() {
                return resource
            } else {
                return factory()
            }
        }
    }
    
    /// Returns a resource to the pool
    func release(_ resource: T) {
        queue.async(flags: .barrier) {
            guard self.pool.count < self.maxSize else {
                // Pool is full, let the resource be deallocated
                return
            }
            
            self.reset(resource)
            self.pool.append(resource)
        }
    }
    
    /// Clears the entire pool
    func clear() {
        queue.async(flags: .barrier) {
            self.pool.removeAll()
        }
    }
}
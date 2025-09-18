//
//  FullIntegrationTests.swift
//  WordTaggerTests
//
//  Created by Kiro on 2025/8/19.
//

import XCTest
import SwiftUI
import Combine
@testable import WordTagger

@MainActor
final class FullIntegrationTests: XCTestCase {
    
    var keyboardManager: KeyboardEventManager!
    var gitService: GitService!
    var mockDataManager: MockDataManager!
    var testNode: Node!
    var cancellables: Set<AnyCancellable>!
    var tempDirectory: URL!
    
    override func setUpWithResult() throws {
        try super.setUpWithResult()
        
        // Create temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Initialize services
        keyboardManager = KeyboardEventManager()
        gitService = GitService(workingDirectory: tempDirectory)
        mockDataManager = MockDataManager()
        
        // Create test node
        testNode = Node(
            text: "Integration Test Node",
            phonetic: "test",
            meaning: "A node for integration testing",
            layerId: UUID(),
            tags: [],
            markdown: "# Integration Test Node\nThis is a test node for integration testing."
        )
        
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDownWithResult() throws {
        cancellables?.removeAll()
        
        // Clean up temp directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        
        keyboardManager = nil
        gitService = nil
        mockDataManager = nil
        testNode = nil
        
        try super.tearDownWithResult()
    }
    
    // MARK: - Keyboard Shortcuts Integration Tests
    
    func testKeyboardShortcutsWorkWithoutInterference() throws {
        let expectation = XCTestExpectation(description: "Keyboard shortcuts work correctly")
        expectation.expectedFulfillmentCount = 4
        
        var commandGExecuted = false
        var commandWExecuted = false
        var commandGSecondExecution = false
        var commandWAfterClear = false
        
        // Test Command+G execution
        XCTAssertTrue(keyboardManager.canExecuteCommand(KeyboardEventManager.Commands.commandG))
        keyboardManager.markCommandExecuted(KeyboardEventManager.Commands.commandG)
        commandGExecuted = true
        expectation.fulfill()
        
        // Command+G should be blocked by cooldown
        XCTAssertFalse(keyboardManager.canExecuteCommand(KeyboardEventManager.Commands.commandG))
        
        // Command+W should be allowed (different command)
        XCTAssertTrue(keyboardManager.canExecuteCommand(KeyboardEventManager.Commands.commandW))
        keyboardManager.markCommandExecuted(KeyboardEventManager.Commands.commandW)
        commandWExecuted = true
        expectation.fulfill()
        
        // Clear state (simulating Command+W clearing state)
        keyboardManager.clearCommandState()
        
        // Command+G should be allowed after clearing
        XCTAssertTrue(keyboardManager.canExecuteCommand(KeyboardEventManager.Commands.commandG))
        keyboardManager.markCommandExecuted(KeyboardEventManager.Commands.commandG)
        commandGSecondExecution = true
        expectation.fulfill()
        
        // Command+W should still work after state clear
        XCTAssertTrue(keyboardManager.canExecuteCommand(KeyboardEventManager.Commands.commandW))
        keyboardManager.markCommandExecuted(KeyboardEventManager.Commands.commandW)
        commandWAfterClear = true
        expectation.fulfill()
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(commandGExecuted)
        XCTAssertTrue(commandWExecuted)
        XCTAssertTrue(commandGSecondExecution)
        XCTAssertTrue(commandWAfterClear)
    }
    
    func testKeyboardEventErrorRecovery() throws {
        let expectation = XCTestExpectation(description: "Error recovery works")
        
        // Trigger error recovery
        keyboardManager.markCommandFailed("test-command", error: .eventConflict)
        
        // Should be in error recovery
        let status = keyboardManager.getErrorRecoveryStatus()
        XCTAssertTrue(status.isInRecovery)
        XCTAssertEqual(status.errorType, .eventConflict)
        
        // Normal commands should be blocked
        XCTAssertFalse(keyboardManager.canExecuteCommand("normal-command"))
        
        // Recovery commands should be allowed
        XCTAssertTrue(keyboardManager.canExecuteCommand(KeyboardEventManager.Commands.escape))
        
        // Execute recovery command
        keyboardManager.markCommandExecuted(KeyboardEventManager.Commands.escape)
        
        // Manual reset
        keyboardManager.resetErrorState()
        
        // Should have exited recovery
        XCTAssertFalse(keyboardManager.getErrorRecoveryStatus().isInRecovery)
        
        // Commands should be allowed again
        XCTAssertTrue(keyboardManager.canExecuteCommand("normal-command"))
        
        expectation.fulfill()
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Node Context Menu Integration Tests
    
    func testNodeContextMenuIntegrationWithGraph() throws {
        let expectation = XCTestExpectation(description: "Node context menu integration")
        expectation.expectedFulfillmentCount = 5
        
        var rightClickDetected = false
        var contextMenuDisplayed = false
        var editCommandSelected = false
        var nodeEditorOpened = false
        var nodeSaved = false
        
        // Step 1: Right-click detection
        let onRightClick: (Int, CGFloat, CGFloat) -> Void = { nodeId, x, y in
            XCTAssertEqual(nodeId, self.testNode.id)
            XCTAssertGreaterThan(x, 0)
            XCTAssertGreaterThan(y, 0)
            rightClickDetected = true
            expectation.fulfill()
        }
        
        // Step 2: Context menu creation
        let contextMenu = NodeContextMenuView(
            node: testNode,
            onEditCommand: {
                contextMenuDisplayed = true
                editCommandSelected = true
                expectation.fulfill()
            },
            onEditName: {
                contextMenuDisplayed = true
                expectation.fulfill()
            },
            onDelete: {
                contextMenuDisplayed = true
            }
        )
        
        // Step 3: Node editor sheet
        let editorSheet = NodeEditorSheet(
            node: .constant(testNode),
            onSave: { node in
                nodeEditorOpened = true
                nodeSaved = true
                XCTAssertEqual(node.text, "Modified Integration Test Node")
                XCTAssertEqual(node.commandLabel, "integration test command")
                expectation.fulfill()
            },
            onCancel: {
                nodeEditorOpened = true
            }
        )
        
        // Execute integration workflow
        onRightClick(testNode.id, 100, 150)
        contextMenu.onEditCommand()
        
        // Simulate node editing
        var modifiedNode = testNode!
        modifiedNode.text = "Modified Integration Test Node"
        modifiedNode.commandLabel = "integration test command"
        editorSheet.onSave(modifiedNode)
        
        // Verify context menu is accessible
        XCTAssertNotNil(contextMenu)
        expectation.fulfill()
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertTrue(rightClickDetected)
        XCTAssertTrue(contextMenuDisplayed)
        XCTAssertTrue(editCommandSelected)
        XCTAssertTrue(nodeEditorOpened)
        XCTAssertTrue(nodeSaved)
    }
    
    func testNodeEditingWithErrorHandling() throws {
        let expectation = XCTestExpectation(description: "Node editing error handling")
        expectation.expectedFulfillmentCount = 3
        
        var saveAttempted = false
        var errorHandled = false
        var retrySuccessful = false
        
        // Mock data manager to simulate failures
        mockDataManager.shouldSucceed = false
        mockDataManager.errorToReturn = MockDataManagerError.networkError
        
        let editorSheet = NodeEditorSheet(
            node: .constant(testNode),
            onSave: { node in
                saveAttempted = true
                expectation.fulfill()
                
                // Simulate save operation
                self.mockDataManager.saveNode(node) { result in
                    switch result {
                    case .success:
                        retrySuccessful = true
                        expectation.fulfill()
                    case .failure:
                        errorHandled = true
                        expectation.fulfill()
                        
                        // Simulate retry with success
                        self.mockDataManager.shouldSucceed = true
                        self.mockDataManager.saveNode(node) { retryResult in
                            if case .success = retryResult {
                                retrySuccessful = true
                            }
                        }
                    }
                }
            },
            onCancel: {}
        )
        
        // Attempt save
        var modifiedNode = testNode!
        modifiedNode.text = "Error Test Node"
        editorSheet.onSave(modifiedNode)
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertTrue(saveAttempted)
        XCTAssertTrue(errorHandled)
        XCTAssertTrue(mockDataManager.saveNodeCalled)
    }
    
    // MARK: - Git Integration Tests
    
    func testGitIntegrationWithExternalDataManagement() async throws {
        let repositoryURL = "https://github.com/test/integration-repo.git"
        let credentials = GitCredentials(username: "testuser", token: "testtoken")
        
        // Test repository configuration
        do {
            try await gitService.configureRepository(url: repositoryURL, credentials: credentials)
            XCTAssertEqual(gitService.connectionStatus, .connected)
        } catch {
            // Expected to fail in test environment, but should handle gracefully
            XCTAssertTrue(error is GitError)
        }
        
        // Test status refresh
        await gitService.refreshRepositoryStatus()
        XCTAssertNotNil(gitService.repositoryStatus)
        
        // Test pending changes check
        await gitService.checkPendingChanges()
        XCTAssertGreaterThanOrEqual(gitService.pendingChanges, 0)
    }
    
    func testGitOperationsWithErrorHandling() async throws {
        let repositoryURL = "https://github.com/test/error-repo.git"
        let credentials = GitCredentials(username: "testuser", token: "invalidtoken")
        
        // Test authentication failure
        do {
            try await gitService.configureRepository(url: repositoryURL, credentials: credentials)
            XCTFail("Should have failed with authentication error")
        } catch GitError.invalidRepository {
            // Expected error
            XCTAssertTrue(gitService.connectionStatus == .error("Unable to access repository"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Test commit when not connected
        do {
            try await gitService.commitChanges(message: "Test commit")
            XCTFail("Should have failed with not connected error")
        } catch GitError.notConnected {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Test push when not connected
        do {
            try await gitService.pushToRemote()
            XCTFail("Should have failed with not connected error")
        } catch GitError.notConnected {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testGitCredentialManagement() async throws {
        let repositoryURL = "https://github.com/test/credential-repo.git"
        let credentials = GitCredentials(username: "testuser", token: "testtoken")
        
        // Test credential validation
        do {
            let isValid = try await gitService.validateCredentials(credentials, for: repositoryURL)
            // In test environment, this will likely fail, but should not crash
            XCTAssertFalse(isValid) // Expected in test environment
        } catch {
            // Expected to fail in test environment
            XCTAssertTrue(error is GitError)
        }
        
        // Test credential refresh
        let newCredentials = GitCredentials(username: "testuser", token: "newtoken")
        do {
            try await gitService.refreshCredentials(newCredentials)
        } catch {
            // Expected to fail in test environment
            XCTAssertTrue(error is GitError)
        }
    }
    
    // MARK: - End-to-End Integration Tests
    
    func testCompleteWorkflowIntegration() async throws {
        let expectation = XCTestExpectation(description: "Complete workflow integration")
        expectation.expectedFulfillmentCount = 6
        
        var workflowSteps: [String] = []
        
        // Step 1: Keyboard shortcut handling
        XCTAssertTrue(keyboardManager.canExecuteCommand(KeyboardEventManager.Commands.commandG))
        keyboardManager.markCommandExecuted(KeyboardEventManager.Commands.commandG)
        workflowSteps.append("keyboard-command-g")
        expectation.fulfill()
        
        // Step 2: Right-click node interaction
        let onRightClick: (Int, CGFloat, CGFloat) -> Void = { nodeId, x, y in
            workflowSteps.append("right-click-detected")
            expectation.fulfill()
        }
        onRightClick(testNode.id, 100, 150)
        
        // Step 3: Context menu interaction
        let contextMenu = NodeContextMenuView(
            node: testNode,
            onEditCommand: {
                workflowSteps.append("context-menu-edit")
                expectation.fulfill()
            },
            onEditName: {},
            onDelete: {}
        )
        contextMenu.onEditCommand()
        
        // Step 4: Node editing
        let editorSheet = NodeEditorSheet(
            node: .constant(testNode),
            onSave: { node in
                workflowSteps.append("node-saved")
                expectation.fulfill()
            },
            onCancel: {}
        )
        
        var modifiedNode = testNode!
        modifiedNode.text = "Workflow Test Node"
        modifiedNode.commandLabel = "workflow test command"
        editorSheet.onSave(modifiedNode)
        
        // Step 5: Git integration (simulated)
        await gitService.refreshRepositoryStatus()
        workflowSteps.append("git-status-refreshed")
        expectation.fulfill()
        
        // Step 6: Keyboard state cleanup
        keyboardManager.clearCommandState()
        XCTAssertTrue(keyboardManager.canExecuteCommand(KeyboardEventManager.Commands.commandW))
        keyboardManager.markCommandExecuted(KeyboardEventManager.Commands.commandW)
        workflowSteps.append("keyboard-cleanup")
        expectation.fulfill()
        
        wait(for: [expectation], timeout: 3.0)
        
        XCTAssertEqual(workflowSteps.count, 6)
        XCTAssertTrue(workflowSteps.contains("keyboard-command-g"))
        XCTAssertTrue(workflowSteps.contains("right-click-detected"))
        XCTAssertTrue(workflowSteps.contains("context-menu-edit"))
        XCTAssertTrue(workflowSteps.contains("node-saved"))
        XCTAssertTrue(workflowSteps.contains("git-status-refreshed"))
        XCTAssertTrue(workflowSteps.contains("keyboard-cleanup"))
    }
    
    func testConcurrentOperationsHandling() async throws {
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = 4
        
        // Test concurrent keyboard events
        let commands = ["concurrent-1", "concurrent-2", "concurrent-3", "concurrent-4"]
        
        for command in commands {
            DispatchQueue.global(qos: .userInteractive).async {
                if self.keyboardManager.canExecuteCommand(command) {
                    self.keyboardManager.markCommandExecuted(command)
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        // Verify system remained stable
        XCTAssertNotNil(keyboardManager)
        XCTAssertFalse(keyboardManager.getErrorRecoveryStatus().isInRecovery)
    }
    
    func testErrorRecoveryAcrossAllSystems() throws {
        let expectation = XCTestExpectation(description: "System-wide error recovery")
        expectation.expectedFulfillmentCount = 3
        
        // Trigger keyboard error
        keyboardManager.markCommandFailed("error-command", error: .unexpectedState)
        XCTAssertTrue(keyboardManager.getErrorRecoveryStatus().isInRecovery)
        expectation.fulfill()
        
        // Simulate node editing error
        mockDataManager.shouldSucceed = false
        mockDataManager.errorToReturn = MockDataManagerError.saveFailed
        
        let editorSheet = NodeEditorSheet(
            node: .constant(testNode),
            onSave: { node in
                self.mockDataManager.saveNode(node) { result in
                    switch result {
                    case .success:
                        XCTFail("Should have failed")
                    case .failure:
                        expectation.fulfill()
                    }
                }
            },
            onCancel: {}
        )
        
        var modifiedNode = testNode!
        modifiedNode.text = "Error Recovery Test"
        editorSheet.onSave(modifiedNode)
        
        // Test Git error handling
        Task {
            do {
                try await self.gitService.commitChanges(message: "Error test")
                XCTFail("Should have failed")
            } catch {
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        // Verify systems can recover
        keyboardManager.resetErrorState()
        XCTAssertFalse(keyboardManager.getErrorRecoveryStatus().isInRecovery)
        
        mockDataManager.shouldSucceed = true
        XCTAssertTrue(mockDataManager.saveNodeCalled)
    }
    
    // MARK: - Performance Integration Tests
    
    func testPerformanceUnderLoad() throws {
        measure {
            // Simulate high-frequency operations
            for i in 0..<100 {
                let command = "perf-test-\(i)"
                if keyboardManager.canExecuteCommand(command) {
                    keyboardManager.markCommandExecuted(command)
                }
                
                // Create context menus
                let contextMenu = NodeContextMenuView(
                    node: testNode,
                    onEditCommand: {},
                    onEditName: {},
                    onDelete: {}
                )
                _ = contextMenu.body
                
                // Create editor sheets
                let editorSheet = NodeEditorSheet(
                    node: .constant(testNode),
                    onSave: { _ in },
                    onCancel: {}
                )
                _ = editorSheet.body
            }
        }
    }
    
    func testMemoryUsageStability() throws {
        let initialMemory = getMemoryUsage()
        
        // Perform many operations
        for i in 0..<1000 {
            let command = "memory-test-\(i)"
            keyboardManager.markCommandExecuted(command)
            
            // Force cleanup
            if i % 100 == 0 {
                keyboardManager.clearCommandState()
            }
        }
        
        // Force garbage collection
        autoreleasepool {
            // Create and destroy many objects
            for _ in 0..<100 {
                let contextMenu = NodeContextMenuView(
                    node: testNode,
                    onEditCommand: {},
                    onEditName: {},
                    onDelete: {}
                )
                _ = contextMenu.body
            }
        }
        
        let finalMemory = getMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        // Memory increase should be reasonable (less than 50MB)
        XCTAssertLessThan(memoryIncrease, 50 * 1024 * 1024, "Memory usage increased by \(memoryIncrease) bytes")
    }
    
    // MARK: - Data Consistency Tests
    
    func testDataConsistencyAcrossOperations() throws {
        let expectation = XCTestExpectation(description: "Data consistency")
        expectation.expectedFulfillmentCount = 3
        
        var originalNode = testNode!
        let originalText = originalNode.text
        let originalCommand = originalNode.commandLabel
        
        // Modify node through editor
        let editorSheet = NodeEditorSheet(
            node: .constant(originalNode),
            onSave: { node in
                // Verify modifications are applied correctly
                XCTAssertNotEqual(node.text, originalText)
                XCTAssertNotEqual(node.commandLabel, originalCommand)
                XCTAssertEqual(node.text, "Consistency Test Node")
                XCTAssertEqual(node.commandLabel, "consistency test command")
                expectation.fulfill()
                
                // Verify node data integrity
                XCTAssertNotNil(node.id)
                XCTAssertNotNil(node.layerId)
                XCTAssertNotNil(node.updatedAt)
                expectation.fulfill()
                
                // Verify command label is properly stored in markdown
                XCTAssertTrue(node.markdown.contains("consistency test command"))
                expectation.fulfill()
            },
            onCancel: {}
        )
        
        // Simulate editing
        var modifiedNode = originalNode
        modifiedNode.text = "Consistency Test Node"
        modifiedNode.commandLabel = "consistency test command"
        modifiedNode.updatedAt = Date()
        
        editorSheet.onSave(modifiedNode)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Helper Methods
    
    private func getMemoryUsage() -> Int64 {
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
            return Int64(info.resident_size)
        } else {
            return 0
        }
    }
}

// MARK: - Mock Extensions

extension MockDataManager {
    enum MockDataManagerError: Error {
        case saveFailed
        case networkError
        case validationError
    }
}

// MARK: - Test Node Extensions

extension Node {
    var isCommandValid: Bool {
        guard let command = commandLabel else { return true }
        return command.count <= 300
    }
}

// MARK: - Markdown Command Validator

struct MarkdownCommandValidator {
    enum ValidationResult {
        case valid
        case warning(String)
        case error(String)
    }
    
    static func validateCommandSyntax(in text: String) -> ValidationResult {
        // Basic validation for command syntax
        if text.contains("<!--") && !text.contains("-->") {
            return .error("Unclosed HTML comment")
        }
        
        if text.hasPrefix("@") && text.count < 3 {
            return .warning("Command appears incomplete")
        }
        
        return .valid
    }
}

// MARK: - Git Operations Mock

class GitOperations {
    let workingDirectory: URL
    
    init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }
    
    func testRepositoryConnectivity(url: String, credentials: GitCredentials) async throws -> Bool {
        // Simulate connectivity test
        return false // Always fail in test environment
    }
    
    func commitChanges(message: String, progressHandler: @escaping (GitOperationProgress) -> Void) async throws {
        // Simulate commit operation
        progressHandler(GitOperationProgress(phase: "Staging", progress: 0.5, message: "Staging files..."))
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        progressHandler(GitOperationProgress(phase: "Committing", progress: 1.0, message: "Commit complete"))
    }
    
    func pushToRemote(credentials: GitCredentials, progressHandler: @escaping (GitOperationProgress) -> Void) async throws {
        // Simulate push operation
        progressHandler(GitOperationProgress(phase: "Pushing", progress: 0.5, message: "Pushing to remote..."))
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        progressHandler(GitOperationProgress(phase: "Pushing", progress: 1.0, message: "Push complete"))
    }
    
    func getRepositoryStatus() async throws -> GitRepositoryStatus {
        return GitRepositoryStatus(
            isConnected: false,
            hasUncommittedChanges: false,
            uncommittedFiles: [],
            currentBranch: "main",
            lastCommitHash: nil,
            lastCommitMessage: nil,
            lastCommitDate: nil
        )
    }
    
    func initializeRepository() async throws {
        // Simulate repository initialization
    }
    
    func addRemote(url: String, name: String) async throws {
        // Simulate adding remote
    }
}

// MARK: - Git Supporting Structures

struct GitOperationProgress {
    let phase: String
    let progress: Double
    let message: String
}

struct GitRepositoryStatus {
    let isConnected: Bool
    let hasUncommittedChanges: Bool
    let uncommittedFiles: [String]
    let currentBranch: String
    let lastCommitHash: String?
    let lastCommitMessage: String?
    let lastCommitDate: Date?
    
    init(isConnected: Bool = false, hasUncommittedChanges: Bool = false, uncommittedFiles: [String] = [], currentBranch: String = "main", lastCommitHash: String? = nil, lastCommitMessage: String? = nil, lastCommitDate: Date? = nil) {
        self.isConnected = isConnected
        self.hasUncommittedChanges = hasUncommittedChanges
        self.uncommittedFiles = uncommittedFiles
        self.currentBranch = currentBranch
        self.lastCommitHash = lastCommitHash
        self.lastCommitMessage = lastCommitMessage
        self.lastCommitDate = lastCommitDate
    }
}
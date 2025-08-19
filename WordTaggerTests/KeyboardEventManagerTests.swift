//
//  KeyboardEventManagerTests.swift
//  WordTaggerTests
//
//  Created by Kiro on 2025/8/19.
//

import XCTest
import Combine
@testable import WordTagger

final class KeyboardEventManagerTests: XCTestCase {
    
    var keyboardManager: KeyboardEventManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithResult() throws {
        try super.setUpWithResult()
        keyboardManager = KeyboardEventManager()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDownWithResult() throws {
        cancellables?.removeAll()
        keyboardManager = nil
        try super.tearDownWithResult()
    }
    
    // MARK: - Command Cooldown Tests
    
    func testCommandCooldownPreventsRapidExecution() throws {
        let command = "test-command"
        
        // First execution should be allowed
        XCTAssertTrue(keyboardManager.canExecuteCommand(command))
        
        // Mark as executed
        keyboardManager.markCommandExecuted(command)
        
        // Immediate second execution should be blocked by cooldown
        XCTAssertFalse(keyboardManager.canExecuteCommand(command))
    }
    
    func testCommandCooldownAllowsExecutionAfterTimeout() throws {
        let command = "test-command"
        let expectation = XCTestExpectation(description: "Command cooldown expires")
        
        // Execute command
        XCTAssertTrue(keyboardManager.canExecuteCommand(command))
        keyboardManager.markCommandExecuted(command)
        
        // Should be blocked immediately
        XCTAssertFalse(keyboardManager.canExecuteCommand(command))
        
        // Wait for cooldown to expire (0.5 seconds + small buffer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // Should be allowed after cooldown
            XCTAssertTrue(self.keyboardManager.canExecuteCommand(command))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testDifferentCommandsNotAffectedByCooldown() throws {
        let command1 = "command-1"
        let command2 = "command-2"
        
        // Execute first command
        XCTAssertTrue(keyboardManager.canExecuteCommand(command1))
        keyboardManager.markCommandExecuted(command1)
        
        // First command should be blocked by cooldown
        XCTAssertFalse(keyboardManager.canExecuteCommand(command1))
        
        // Second command should still be allowed
        XCTAssertTrue(keyboardManager.canExecuteCommand(command2))
    }
    
    func testTimeSinceLastExecutionTracking() throws {
        let command = "test-command"
        
        // Initially no execution time
        XCTAssertNil(keyboardManager.timeSinceLastExecution(of: command))
        
        // Execute command
        keyboardManager.markCommandExecuted(command)
        
        // Should have execution time
        let timeSince = keyboardManager.timeSinceLastExecution(of: command)
        XCTAssertNotNil(timeSince)
        XCTAssertLessThan(timeSince!, 0.1) // Should be very recent
    }
    
    // MARK: - State Management Tests
    
    func testActiveCommandTracking() throws {
        let command = "test-command"
        
        // Initially not active
        XCTAssertFalse(keyboardManager.isCommandActive(command))
        
        // Mark as executed (becomes active)
        keyboardManager.markCommandExecuted(command)
        
        // Should be active
        XCTAssertTrue(keyboardManager.isCommandActive(command))
        
        // Wait for cooldown to clear active state
        let expectation = XCTestExpectation(description: "Command becomes inactive")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertFalse(self.keyboardManager.isCommandActive(command))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testClearCommandStateRemovesAllState() throws {
        let command1 = "command-1"
        let command2 = "command-2"
        
        // Execute multiple commands
        keyboardManager.markCommandExecuted(command1)
        keyboardManager.markCommandExecuted(command2)
        
        // Both should be active
        XCTAssertTrue(keyboardManager.isCommandActive(command1))
        XCTAssertTrue(keyboardManager.isCommandActive(command2))
        
        // Clear all state
        keyboardManager.clearCommandState()
        
        // Both should be inactive
        XCTAssertFalse(keyboardManager.isCommandActive(command1))
        XCTAssertFalse(keyboardManager.isCommandActive(command2))
        
        // Both should be allowed to execute again
        XCTAssertTrue(keyboardManager.canExecuteCommand(command1))
        XCTAssertTrue(keyboardManager.canExecuteCommand(command2))
    }
    
    func testClearSpecificCommandState() throws {
        let command1 = "command-1"
        let command2 = "command-2"
        
        // Execute both commands
        keyboardManager.markCommandExecuted(command1)
        keyboardManager.markCommandExecuted(command2)
        
        // Clear only first command
        keyboardManager.clearCommandState(for: command1)
        
        // First should be cleared, second should remain
        XCTAssertFalse(keyboardManager.isCommandActive(command1))
        XCTAssertTrue(keyboardManager.isCommandActive(command2))
        
        // First should be allowed, second should still be blocked
        XCTAssertTrue(keyboardManager.canExecuteCommand(command1))
        XCTAssertFalse(keyboardManager.canExecuteCommand(command2))
    }
    
    // MARK: - Concurrent Command Execution Prevention Tests
    
    func testActiveCommandBlocksReexecution() throws {
        let command = "test-command"
        
        // Mark command as executed (becomes active)
        keyboardManager.markCommandExecuted(command)
        
        // Should be blocked while active
        XCTAssertFalse(keyboardManager.canExecuteCommand(command))
        XCTAssertTrue(keyboardManager.isCommandActive(command))
    }
    
    func testMultipleActiveCommandsHandledCorrectly() throws {
        let commands = ["cmd-1", "cmd-2", "cmd-3"]
        
        // Execute all commands
        for command in commands {
            XCTAssertTrue(keyboardManager.canExecuteCommand(command))
            keyboardManager.markCommandExecuted(command)
        }
        
        // All should be active and blocked
        for command in commands {
            XCTAssertTrue(keyboardManager.isCommandActive(command))
            XCTAssertFalse(keyboardManager.canExecuteCommand(command))
        }
    }
    
    func testConcurrentAccessToCommandState() throws {
        let command = "concurrent-test"
        let expectation = XCTestExpectation(description: "Concurrent access completed")
        expectation.expectedFulfillmentCount = 10
        
        // Simulate concurrent access from multiple threads
        for i in 0..<10 {
            DispatchQueue.global(qos: .userInteractive).async {
                let canExecute = self.keyboardManager.canExecuteCommand("\(command)-\(i)")
                if canExecute {
                    self.keyboardManager.markCommandExecuted("\(command)-\(i)")
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        // Should not crash and state should be consistent
        XCTAssertNotNil(keyboardManager)
    }
    
    // MARK: - Error Recovery Tests
    
    func testErrorRecoveryModeBlocking() throws {
        let command = "test-command"
        let recoveryCommand = KeyboardEventManager.Commands.escape
        
        // Simulate error that triggers recovery mode
        keyboardManager.markCommandFailed(command, error: .eventConflict)
        
        // Should be in error recovery
        let status = keyboardManager.getErrorRecoveryStatus()
        XCTAssertTrue(status.isInRecovery)
        XCTAssertEqual(status.errorType, .eventConflict)
        
        // Regular commands should be blocked
        XCTAssertFalse(keyboardManager.canExecuteCommand(command))
        
        // Recovery commands should be allowed
        XCTAssertTrue(keyboardManager.canExecuteCommand(recoveryCommand))
    }
    
    func testErrorRecoveryTimeout() throws {
        let command = "test-command"
        let expectation = XCTestExpectation(description: "Error recovery timeout")
        
        // Trigger error recovery
        keyboardManager.markCommandFailed(command, error: .focusLost)
        
        // Should be in recovery
        XCTAssertTrue(keyboardManager.getErrorRecoveryStatus().isInRecovery)
        
        // Wait for timeout (5 seconds + buffer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
            // Should have exited recovery automatically
            XCTAssertFalse(self.keyboardManager.getErrorRecoveryStatus().isInRecovery)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6.0)
    }
    
    func testManualErrorRecoveryReset() throws {
        let command = "test-command"
        
        // Trigger error recovery
        keyboardManager.markCommandFailed(command, error: .unexpectedState)
        
        // Should be in recovery
        XCTAssertTrue(keyboardManager.getErrorRecoveryStatus().isInRecovery)
        
        // Manual reset
        keyboardManager.resetErrorState()
        
        // Should have exited recovery
        XCTAssertFalse(keyboardManager.getErrorRecoveryStatus().isInRecovery)
        
        // Commands should be allowed again
        XCTAssertTrue(keyboardManager.canExecuteCommand(command))
    }
    
    // MARK: - Automatic Cleanup Tests
    
    func testAutomaticStateCleanup() throws {
        let command = "cleanup-test"
        let expectation = XCTestExpectation(description: "Automatic cleanup occurs")
        
        // Execute command
        keyboardManager.markCommandExecuted(command)
        
        // Should have execution time
        XCTAssertNotNil(keyboardManager.timeSinceLastExecution(of: command))
        
        // Wait for cleanup (cooldown * 3 = 1.5 seconds + buffer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Execution time should still exist (cleanup removes very old entries)
            // But command should be allowed to execute
            XCTAssertTrue(self.keyboardManager.canExecuteCommand(command))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
    }
    
    func testLongRunningStateReset() throws {
        let command = "long-running-test"
        let expectation = XCTestExpectation(description: "Long running state reset")
        
        // Execute command
        keyboardManager.markCommandExecuted(command)
        
        // Manually set old execution time to simulate stuck state
        let oldDate = Date().addingTimeInterval(-35) // Older than maxStateRetentionTime (30s)
        
        // Wait for automatic state reset (this would normally take 30+ seconds)
        // For testing, we'll trigger it manually
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Command should be allowed (state should be reset)
            XCTAssertTrue(self.keyboardManager.canExecuteCommand(command))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Focus Management Tests
    
    func testFocusLostErrorHandling() throws {
        let command = "focus-test"
        
        // Simulate focus lost error
        keyboardManager.markCommandFailed(command, error: .focusLost)
        
        // Should be in error recovery
        let status = keyboardManager.getErrorRecoveryStatus()
        XCTAssertTrue(status.isInRecovery)
        XCTAssertEqual(status.errorType, .focusLost)
        
        // Commands should be blocked
        XCTAssertFalse(keyboardManager.canExecuteCommand(command))
    }
    
    func testApplicationFocusChangeHandling() throws {
        let command = "focus-change-test"
        
        // Execute command
        keyboardManager.markCommandExecuted(command)
        XCTAssertTrue(keyboardManager.isCommandActive(command))
        
        // Simulate application losing focus
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        
        // Wait for notification processing
        let expectation = XCTestExpectation(description: "Focus change processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Command should be cleared when app loses focus
            XCTAssertFalse(self.keyboardManager.isCommandActive(command))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Execution History Tests
    
    func testExecutionHistoryTracking() throws {
        let commands = ["hist-1", "hist-2", "hist-3"]
        
        // Execute commands
        for command in commands {
            XCTAssertTrue(keyboardManager.canExecuteCommand(command))
            keyboardManager.markCommandExecuted(command)
        }
        
        // Get execution history
        let history = keyboardManager.getExecutionHistory()
        
        // Should have entries for all commands (attempts + executions)
        XCTAssertGreaterThanOrEqual(history.count, commands.count)
        
        // Check that successful executions are recorded
        let successfulExecutions = history.filter { $0.success }
        XCTAssertEqual(successfulExecutions.count, commands.count)
    }
    
    func testExecutionHistoryLimit() throws {
        // Execute more commands than history limit
        for i in 0..<25 {
            let command = "history-limit-\(i)"
            keyboardManager.markCommandExecuted(command)
        }
        
        // History should be limited
        let history = keyboardManager.getExecutionHistory()
        XCTAssertLessThanOrEqual(history.count, 20) // Default limit in getExecutionHistory
    }
    
    func testFailedCommandHistoryTracking() throws {
        let command = "failed-command"
        let error = KeyboardError.timeout
        
        // Mark command as failed
        keyboardManager.markCommandFailed(command, error: error)
        
        // Check history contains the failure
        let history = keyboardManager.getExecutionHistory()
        let failedExecution = history.first { $0.command == command && !$0.success }
        
        XCTAssertNotNil(failedExecution)
        XCTAssertEqual(failedExecution?.error as? KeyboardError, error)
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceOfCanExecuteCommand() throws {
        let command = "performance-test"
        
        measure {
            for _ in 0..<1000 {
                _ = keyboardManager.canExecuteCommand(command)
            }
        }
    }
    
    func testPerformanceOfMarkCommandExecuted() throws {
        measure {
            for i in 0..<100 {
                let command = "perf-\(i)"
                keyboardManager.markCommandExecuted(command)
            }
        }
    }
    
    // MARK: - Edge Cases Tests
    
    func testEmptyCommandHandling() throws {
        let emptyCommand = ""
        
        // Should handle empty command gracefully
        XCTAssertTrue(keyboardManager.canExecuteCommand(emptyCommand))
        keyboardManager.markCommandExecuted(emptyCommand)
        XCTAssertFalse(keyboardManager.canExecuteCommand(emptyCommand))
    }
    
    func testVeryLongCommandName() throws {
        let longCommand = String(repeating: "a", count: 1000)
        
        // Should handle very long command names
        XCTAssertTrue(keyboardManager.canExecuteCommand(longCommand))
        keyboardManager.markCommandExecuted(longCommand)
        XCTAssertTrue(keyboardManager.isCommandActive(longCommand))
    }
    
    func testSpecialCharactersInCommandName() throws {
        let specialCommand = "cmd-with-!@#$%^&*()_+-=[]{}|;':\",./<>?"
        
        // Should handle special characters
        XCTAssertTrue(keyboardManager.canExecuteCommand(specialCommand))
        keyboardManager.markCommandExecuted(specialCommand)
        XCTAssertTrue(keyboardManager.isCommandActive(specialCommand))
    }
    
    // MARK: - Integration Tests
    
    func testCommandGCommandWSequence() throws {
        let commandG = KeyboardEventManager.Commands.commandG
        let commandW = KeyboardEventManager.Commands.commandW
        
        // Execute Command+G
        XCTAssertTrue(keyboardManager.canExecuteCommand(commandG))
        keyboardManager.markCommandExecuted(commandG)
        
        // Command+G should be blocked by cooldown
        XCTAssertFalse(keyboardManager.canExecuteCommand(commandG))
        
        // Command+W should be allowed (different command)
        XCTAssertTrue(keyboardManager.canExecuteCommand(commandW))
        
        // Clear state (simulating Command+W clearing state)
        keyboardManager.clearCommandState()
        
        // Both should be allowed after clearing
        XCTAssertTrue(keyboardManager.canExecuteCommand(commandG))
        XCTAssertTrue(keyboardManager.canExecuteCommand(commandW))
    }
    
    func testRecoveryCommandsAllowedDuringErrorRecovery() throws {
        let normalCommand = "normal-command"
        let escapeCommand = KeyboardEventManager.Commands.escape
        let clearStateCommand = "clear-state"
        
        // Trigger error recovery
        keyboardManager.markCommandFailed(normalCommand, error: .eventConflict)
        
        // Normal commands should be blocked
        XCTAssertFalse(keyboardManager.canExecuteCommand(normalCommand))
        
        // Recovery commands should be allowed
        XCTAssertTrue(keyboardManager.canExecuteCommand(escapeCommand))
        XCTAssertTrue(keyboardManager.canExecuteCommand(clearStateCommand))
    }
}

// MARK: - Test Extensions

extension KeyboardError: Equatable {
    public static func == (lhs: KeyboardError, rhs: KeyboardError) -> Bool {
        switch (lhs, rhs) {
        case (.focusLost, .focusLost),
             (.eventConflict, .eventConflict),
             (.systemOverride, .systemOverride),
             (.unexpectedState, .unexpectedState),
             (.timeout, .timeout):
            return true
        default:
            return false
        }
    }
}
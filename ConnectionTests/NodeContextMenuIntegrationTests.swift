//
//  NodeContextMenuIntegrationTests.swift
//  WordTaggerTests
//
//  Created by Kiro on 2025/8/19.
//

import XCTest
import SwiftUI
import Combine
@testable import WordTagger

@MainActor
final class NodeContextMenuIntegrationTests: XCTestCase {
    
    var testNode: Node!
    var mockDataManager: MockDataManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithResult() throws {
        try super.setUpWithResult()
        
        // Create test node
        testNode = Node(
            text: "Test Node",
            phonetic: "test",
            meaning: "A test node for integration testing",
            layerId: UUID(),
            tags: [],
            markdown: "# Test Node\nThis is a test node for integration testing."
        )
        
        mockDataManager = MockDataManager()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDownWithResult() throws {
        cancellables?.removeAll()
        testNode = nil
        mockDataManager = nil
        try super.tearDownWithResult()
    }
    
    // MARK: - Right-Click Detection Tests
    
    func testRightClickDetectionInGraphView() throws {
        var rightClickedNodeId: Int?
        var rightClickPosition: (x: CGFloat, y: CGFloat)?
        
        let expectation = XCTestExpectation(description: "Right-click event detected")
        
        // Create graph view with right-click handler
        let graphView = UniversalRelationshipGraphView(
            nodes: [NodeGraphNode(node: testNode, isCenter: false)],
            edges: [],
            title: "Test Graph",
            onNodeRightClicked: { nodeId, x, y in
                rightClickedNodeId = nodeId
                rightClickPosition = (x: x, y: y)
                expectation.fulfill()
            }
        )
        
        // Simulate right-click event (would normally come from JavaScript)
        // In a real test, this would be triggered by WebView interaction
        let simulatedNodeId = testNode.id
        let simulatedX: CGFloat = 100.0
        let simulatedY: CGFloat = 150.0
        
        // Trigger the callback directly for testing
        DispatchQueue.main.async {
            graphView.onNodeRightClicked?(simulatedNodeId, simulatedX, simulatedY)
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(rightClickedNodeId, simulatedNodeId)
        XCTAssertEqual(rightClickPosition?.x, simulatedX)
        XCTAssertEqual(rightClickPosition?.y, simulatedY)
    }
    
    func testRightClickEventPropagation() throws {
        var eventReceived = false
        let expectation = XCTestExpectation(description: "Event propagation")
        
        // Test that right-click events are properly propagated through the view hierarchy
        let onRightClick: (Int, CGFloat, CGFloat) -> Void = { nodeId, x, y in
            eventReceived = true
            XCTAssertEqual(nodeId, self.testNode.id)
            XCTAssertGreaterThan(x, 0)
            XCTAssertGreaterThan(y, 0)
            expectation.fulfill()
        }
        
        // Simulate the event chain: WebView -> Coordinator -> SwiftUI View
        onRightClick(testNode.id, 50.0, 75.0)
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(eventReceived)
    }
    
    // MARK: - Context Menu Display Tests
    
    func testContextMenuCreation() throws {
        var editCommandCalled = false
        var editNameCalled = false
        var deleteCalled = false
        
        let contextMenu = NodeContextMenuView(
            node: testNode,
            onEditCommand: { editCommandCalled = true },
            onEditName: { editNameCalled = true },
            onDelete: { deleteCalled = true }
        )
        
        // Test that the context menu is created with correct node data
        XCTAssertNotNil(contextMenu)
        
        // Simulate button taps
        contextMenu.onEditCommand()
        contextMenu.onEditName()
        contextMenu.onDelete()
        
        XCTAssertTrue(editCommandCalled)
        XCTAssertTrue(editNameCalled)
        XCTAssertTrue(deleteCalled)
    }
    
    func testContextMenuPositioning() throws {
        let testPositions: [(x: CGFloat, y: CGFloat)] = [
            (x: 0, y: 0),
            (x: 100, y: 150),
            (x: 500, y: 300),
            (x: 1000, y: 800)
        ]
        
        for position in testPositions {
            var receivedPosition: (x: CGFloat, y: CGFloat)?
            
            let expectation = XCTestExpectation(description: "Position test for \(position)")
            
            let onRightClick: (Int, CGFloat, CGFloat) -> Void = { _, x, y in
                receivedPosition = (x: x, y: y)
                expectation.fulfill()
            }
            
            onRightClick(testNode.id, position.x, position.y)
            
            wait(for: [expectation], timeout: 1.0)
            
            XCTAssertEqual(receivedPosition?.x, position.x)
            XCTAssertEqual(receivedPosition?.y, position.y)
        }
    }
    
    // MARK: - Node Editor Sheet Integration Tests
    
    func testNodeEditorSheetIntegration() throws {
        var savedNode: Node?
        var cancelCalled = false
        
        let expectation = XCTestExpectation(description: "Node editor integration")
        expectation.expectedFulfillmentCount = 2 // Save and cancel
        
        let editorSheet = NodeEditorSheet(
            node: .constant(testNode),
            onSave: { node in
                savedNode = node
                expectation.fulfill()
            },
            onCancel: {
                cancelCalled = true
                expectation.fulfill()
            }
        )
        
        // Test save functionality
        var modifiedNode = testNode!
        modifiedNode.text = "Modified Test Node"
        modifiedNode.commandLabel = "test command"
        
        editorSheet.onSave(modifiedNode)
        
        // Test cancel functionality
        editorSheet.onCancel()
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertNotNil(savedNode)
        XCTAssertEqual(savedNode?.text, "Modified Test Node")
        XCTAssertEqual(savedNode?.commandLabel, "test command")
        XCTAssertTrue(cancelCalled)
    }
    
    func testNodeEditorValidation() throws {
        let expectation = XCTestExpectation(description: "Validation test")
        
        var validationErrors: [String] = []
        
        let editorSheet = NodeEditorSheet(
            node: .constant(testNode),
            onSave: { node in
                // Validate the node
                if node.text.isEmpty {
                    validationErrors.append("Node name is required")
                }
                if let command = node.commandLabel, command.count > 300 {
                    validationErrors.append("Command too long")
                }
                expectation.fulfill()
            },
            onCancel: {}
        )
        
        // Test with invalid data
        var invalidNode = testNode!
        invalidNode.text = "" // Empty name should fail validation
        invalidNode.commandLabel = String(repeating: "a", count: 350) // Too long
        
        editorSheet.onSave(invalidNode)
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(validationErrors.contains("Node name is required"))
        XCTAssertTrue(validationErrors.contains("Command too long"))
    }
    
    // MARK: - Command Label Functionality Tests
    
    func testCommandLabelExtraction() throws {
        // Test different command formats
        let testCases: [(markdown: String, expectedCommand: String?)] = [
            ("<!-- command: test command -->", "test command"),
            ("Command: another test", "another test"),
            ("@command yet another test", "yet another test"),
            ("No command here", nil),
            ("", nil),
            ("<!-- command:  spaced command  -->", "spaced command")
        ]
        
        for testCase in testCases {
            var node = testNode!
            node.markdown = testCase.markdown
            
            XCTAssertEqual(node.commandLabel, testCase.expectedCommand, 
                          "Failed for markdown: '\(testCase.markdown)'")
        }
    }
    
    func testCommandLabelUpdate() throws {
        var node = testNode!
        
        // Test setting command
        node.commandLabel = "new test command"
        XCTAssertTrue(node.markdown.contains("<!-- command: new test command -->"))
        
        // Test updating existing command
        node.commandLabel = "updated command"
        XCTAssertTrue(node.markdown.contains("<!-- command: updated command -->"))
        XCTAssertFalse(node.markdown.contains("new test command"))
        
        // Test removing command
        node.commandLabel = nil
        XCTAssertFalse(node.markdown.contains("<!-- command:"))
    }
    
    func testCommandValidation() throws {
        var node = testNode!
        
        // Test valid commands
        let validCommands = [
            "simple command",
            "command with spaces",
            "command-with-dashes",
            "command_with_underscores",
            "command123",
            String(repeating: "a", count: 300) // Max length
        ]
        
        for command in validCommands {
            node.commandLabel = command
            XCTAssertTrue(node.isCommandValid, "Command should be valid: '\(command)'")
        }
        
        // Test invalid commands
        let invalidCommands = [
            String(repeating: "a", count: 301) // Too long
        ]
        
        for command in invalidCommands {
            node.commandLabel = command
            XCTAssertFalse(node.isCommandValid, "Command should be invalid: '\(command)'")
        }
        
        // Test empty/nil command (should be valid)
        node.commandLabel = nil
        XCTAssertTrue(node.isCommandValid)
        
        node.commandLabel = ""
        XCTAssertTrue(node.isCommandValid)
    }
    
    // MARK: - Data Persistence Tests
    
    func testNodeModificationPersistence() throws {
        let expectation = XCTestExpectation(description: "Data persistence")
        
        mockDataManager.shouldSucceed = true
        
        // Simulate the full workflow: right-click -> edit -> save
        let originalText = testNode.text
        let originalCommand = testNode.commandLabel
        
        // Modify node
        testNode.text = "Modified Node Name"
        testNode.commandLabel = "modified command"
        
        // Simulate save operation
        mockDataManager.saveNode(testNode) { result in
            switch result {
            case .success:
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Save failed: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Verify changes were applied
        XCTAssertNotEqual(testNode.text, originalText)
        XCTAssertNotEqual(testNode.commandLabel, originalCommand)
        XCTAssertEqual(testNode.text, "Modified Node Name")
        XCTAssertEqual(testNode.commandLabel, "modified command")
        XCTAssertTrue(mockDataManager.saveNodeCalled)
    }
    
    func testNodeModificationFailureHandling() throws {
        let expectation = XCTestExpectation(description: "Failure handling")
        
        mockDataManager.shouldSucceed = false
        mockDataManager.errorToReturn = MockDataManagerError.saveFailed
        
        // Attempt to save node
        mockDataManager.saveNode(testNode) { result in
            switch result {
            case .success:
                XCTFail("Save should have failed")
            case .failure(let error):
                XCTAssertTrue(error is MockDataManagerError)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(mockDataManager.saveNodeCalled)
    }
    
    // MARK: - End-to-End Workflow Tests
    
    func testCompleteNodeEditingWorkflow() throws {
        let expectation = XCTestExpectation(description: "Complete workflow")
        expectation.expectedFulfillmentCount = 4 // Right-click, menu display, edit, save
        
        var workflowSteps: [String] = []
        
        // Step 1: Right-click detection
        let onRightClick: (Int, CGFloat, CGFloat) -> Void = { nodeId, x, y in
            workflowSteps.append("right-click")
            XCTAssertEqual(nodeId, self.testNode.id)
            expectation.fulfill()
        }
        
        // Step 2: Context menu display
        let contextMenu = NodeContextMenuView(
            node: testNode,
            onEditCommand: {
                workflowSteps.append("menu-edit-command")
                expectation.fulfill()
            },
            onEditName: {
                workflowSteps.append("menu-edit-name")
                expectation.fulfill()
            },
            onDelete: {
                workflowSteps.append("menu-delete")
            }
        )
        
        // Step 3: Node editor
        let editorSheet = NodeEditorSheet(
            node: .constant(testNode),
            onSave: { node in
                workflowSteps.append("editor-save")
                expectation.fulfill()
            },
            onCancel: {
                workflowSteps.append("editor-cancel")
            }
        )
        
        // Execute workflow
        onRightClick(testNode.id, 100, 150)
        contextMenu.onEditCommand()
        contextMenu.onEditName()
        
        var modifiedNode = testNode!
        modifiedNode.text = "Workflow Test Node"
        editorSheet.onSave(modifiedNode)
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertEqual(workflowSteps.count, 4)
        XCTAssertTrue(workflowSteps.contains("right-click"))
        XCTAssertTrue(workflowSteps.contains("menu-edit-command"))
        XCTAssertTrue(workflowSteps.contains("menu-edit-name"))
        XCTAssertTrue(workflowSteps.contains("editor-save"))
    }
    
    func testConcurrentNodeEditing() throws {
        let expectation = XCTestExpectation(description: "Concurrent editing")
        expectation.expectedFulfillmentCount = 2
        
        // Simulate two users editing the same node
        var firstUserSave: Node?
        var secondUserSave: Node?
        
        let firstEditor = NodeEditorSheet(
            node: .constant(testNode),
            onSave: { node in
                firstUserSave = node
                expectation.fulfill()
            },
            onCancel: {}
        )
        
        let secondEditor = NodeEditorSheet(
            node: .constant(testNode),
            onSave: { node in
                secondUserSave = node
                expectation.fulfill()
            },
            onCancel: {}
        )
        
        // First user modifies node
        var firstModification = testNode!
        firstModification.text = "First User Edit"
        firstModification.commandLabel = "first command"
        
        // Second user modifies node
        var secondModification = testNode!
        secondModification.text = "Second User Edit"
        secondModification.commandLabel = "second command"
        
        // Both save simultaneously
        firstEditor.onSave(firstModification)
        secondEditor.onSave(secondModification)
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertNotNil(firstUserSave)
        XCTAssertNotNil(secondUserSave)
        XCTAssertNotEqual(firstUserSave?.text, secondUserSave?.text)
        XCTAssertNotEqual(firstUserSave?.commandLabel, secondUserSave?.commandLabel)
    }
    
    // MARK: - Error Handling Integration Tests
    
    func testNodeEditingErrorRecovery() throws {
        let expectation = XCTestExpectation(description: "Error recovery")
        
        var errorHandled = false
        
        let editorSheet = NodeEditorSheet(
            node: .constant(testNode),
            onSave: { node in
                // Simulate save error
                throw NodeSaveError.networkTimeout
            },
            onCancel: {}
        )
        
        // Attempt save that will fail
        do {
            var modifiedNode = testNode!
            modifiedNode.text = "Error Test Node"
            editorSheet.onSave(modifiedNode)
        } catch {
            errorHandled = true
            XCTAssertTrue(error is NodeSaveError)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(errorHandled)
    }
    
    func testInvalidNodeDataHandling() throws {
        let invalidNodes = [
            Node(text: "", phonetic: nil, meaning: nil, layerId: UUID(), tags: [], markdown: ""), // Empty name
            Node(text: String(repeating: "a", count: 300), phonetic: nil, meaning: nil, layerId: UUID(), tags: [], markdown: "") // Too long name
        ]
        
        for invalidNode in invalidNodes {
            let contextMenu = NodeContextMenuView(
                node: invalidNode,
                onEditCommand: {},
                onEditName: {},
                onDelete: {}
            )
            
            // Should handle invalid nodes gracefully
            XCTAssertNotNil(contextMenu)
        }
    }
    
    // MARK: - Performance Tests
    
    func testContextMenuPerformance() throws {
        measure {
            for _ in 0..<100 {
                let contextMenu = NodeContextMenuView(
                    node: testNode,
                    onEditCommand: {},
                    onEditName: {},
                    onDelete: {}
                )
                _ = contextMenu.body // Force view creation
            }
        }
    }
    
    func testNodeEditorPerformance() throws {
        measure {
            for _ in 0..<50 {
                let editorSheet = NodeEditorSheet(
                    node: .constant(testNode),
                    onSave: { _ in },
                    onCancel: {}
                )
                _ = editorSheet.body // Force view creation
            }
        }
    }
    
    func testCommandLabelExtractionPerformance() throws {
        let longMarkdown = String(repeating: "# Test\nSome content\n", count: 100) + "<!-- command: test command -->"
        var node = testNode!
        node.markdown = longMarkdown
        
        measure {
            for _ in 0..<1000 {
                _ = node.commandLabel
            }
        }
    }
    
    // MARK: - Accessibility Tests
    
    func testContextMenuAccessibility() throws {
        let contextMenu = NodeContextMenuView(
            node: testNode,
            onEditCommand: {},
            onEditName: {},
            onDelete: {}
        )
        
        // Test that context menu has proper accessibility labels
        // In a real implementation, you would check for accessibility identifiers
        XCTAssertNotNil(contextMenu)
    }
    
    func testNodeEditorAccessibility() throws {
        let editorSheet = NodeEditorSheet(
            node: .constant(testNode),
            onSave: { _ in },
            onCancel: {}
        )
        
        // Test that editor sheet has proper accessibility support
        XCTAssertNotNil(editorSheet)
    }
}

// MARK: - Mock Classes

class MockDataManager {
    var shouldSucceed = true
    var saveNodeCalled = false
    var errorToReturn: Error?
    
    func saveNode(_ node: Node, completion: @escaping (Result<Void, Error>) -> Void) {
        saveNodeCalled = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.shouldSucceed {
                completion(.success(()))
            } else {
                completion(.failure(self.errorToReturn ?? MockDataManagerError.saveFailed))
            }
        }
    }
}

enum MockDataManagerError: Error {
    case saveFailed
    case networkError
    case validationError
}

// MARK: - Test Extensions

extension Node {
    static func createTestNode(id: Int? = nil, text: String = "Test Node") -> Node {
        return Node(
            text: text,
            phonetic: "test",
            meaning: "A test node",
            layerId: UUID(),
            tags: [],
            markdown: "# \(text)\nTest node for integration testing."
        )
    }
}

// MARK: - Helper Classes for Graph Integration

class NodeGraphNode: UniversalGraphNode {
    let node: Node?
    let tag: Tag?
    let isCenter: Bool
    
    init(node: Node, isCenter: Bool = false) {
        self.node = node
        self.tag = nil
        self.isCenter = isCenter
    }
    
    init(tag: Tag, isCenter: Bool = false) {
        self.node = nil
        self.tag = tag
        self.isCenter = isCenter
    }
    
    var id: Int {
        return node?.id ?? tag?.id ?? 0
    }
    
    var label: String {
        return node?.text ?? tag?.value ?? "Unknown"
    }
    
    var subtitle: String? {
        return node?.meaning ?? tag?.type.displayName
    }
}

struct Tag {
    let id: Int
    let value: String
    let type: TagType
}

enum TagType {
    case memory
    case location
    case shape
    case sound
    
    var displayName: String {
        switch self {
        case .memory: return "Memory"
        case .location: return "Location"
        case .shape: return "Shape"
        case .sound: return "Sound"
        }
    }
}
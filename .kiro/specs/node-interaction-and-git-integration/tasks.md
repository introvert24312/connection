# Implementation Plan

- [x] 1. Set up keyboard event management system
  - Create KeyboardEventManager class with command cooldown and state tracking
  - Implement command execution prevention logic for rapid-fire events
  - Add automatic state cleanup mechanisms
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [x] 2. Fix Command+G/Command+W keyboard shortcut interference
  - [x] 2.1 Integrate KeyboardEventManager into CommandPaletteView
    - Import KeyboardEventManager as StateObject in CommandPaletteView
    - Replace existing onKeyPress handlers with manager-controlled versions
    - Add command cooldown checks before executing Command+G functionality
    - _Requirements: 2.1, 2.2, 2.4_

  - [x] 2.2 Implement Command+W state clearing mechanism
    - Add clearCommandState() call before window close operations
    - Ensure Command+W only executes after command state is cleared
    - Test that Command+W doesn't trigger Command+G functionality
    - _Requirements: 2.3, 2.5_

- [x] 3. Implement node context menu system
  - [x] 3.1 Create NodeContextMenuView component
    - Design SwiftUI view with Edit Command Label, Edit Node Name, and Delete options
    - Implement proper styling consistent with app design
    - Add action callbacks for each menu option
    - _Requirements: 1.1, 1.2_

  - [x] 3.2 Create NodeEditorSheet for node editing
    - Build sheet view with text fields for node name and command editing
    - Implement save/cancel functionality with proper data validation
    - Add error handling for invalid input and save failures
    - _Requirements: 1.3, 1.4, 1.5, 1.6_

  - [x] 3.3 Extend Node model with command label support
    - Add commandLabel computed property to Node extension
    - Implement markdown parsing for command extraction
    - Add command storage in markdown field
    - _Requirements: 1.3, 1.4, 1.5_

  - [x] 3.4 Add JavaScript bridge for right-click detection
    - Extend UniversalRelationshipGraphView HTML with oncontext event handler
    - Add nodeRightClicked message handler to WebView configuration
    - Implement coordinate passing for context menu positioning
    - _Requirements: 1.1_

  - [x] 3.5 Integrate context menu with graph view
    - Add right-click event handling to UniversalGraphWebView Coordinator
    - Implement context menu display at cursor position
    - Connect menu actions to NodeEditorSheet presentation
    - _Requirements: 1.1, 1.2, 1.6_

- [x] 4. Create Git integration service layer
  - [x] 4.1 Implement GitService class
    - Create GitService with connection status management
    - Add repository URL validation and credential handling
    - Implement async methods for Git operations (commit, push)
    - _Requirements: 3.2, 3.3, 3.5, 3.6_

  - [x] 4.2 Add secure credential storage
    - Implement Keychain integration for storing Git tokens
    - Create GitCredentials struct with username/token fields
    - Add credential validation and refresh mechanisms
    - _Requirements: 3.3, 3.9_

  - [x] 4.3 Implement Git repository operations
    - Add repository connectivity testing functionality
    - Implement commit changes with custom messages
    - Add push to remote with progress tracking
    - _Requirements: 3.4, 3.5, 3.6, 3.8_

- [x] 5. Build Git settings user interface
  - [x] 5.1 Create GitSettingsView component
    - Design settings panel with repository configuration section
    - Add connection status indicator with color coding
    - Implement repository URL input and validation
    - _Requirements: 3.1, 3.2, 3.7, 3.10_

  - [x] 5.2 Add Git credentials management UI
    - Create GitCredentialsSheet for secure credential input
    - Implement credential configuration workflow
    - Add credential testing and validation feedback
    - _Requirements: 3.3, 3.9_

  - [x] 5.3 Implement Git operations interface
    - Add commit changes button with pending changes counter
    - Create push to remote functionality with status feedback
    - Implement operation progress indicators and error handling
    - _Requirements: 3.5, 3.6, 3.7, 3.8_

  - [x] 5.4 Integrate Git settings into main SettingsView
    - Add Git tab to existing TabView in SettingsView
    - Ensure proper navigation and state management
    - Test settings persistence and loading
    - _Requirements: 3.1, 3.10_

- [x] 6. Add comprehensive error handling
  - [x] 6.1 Implement node editing error handling
    - Add validation for node name and command input
    - Handle save failures with retry mechanisms
    - Implement conflict resolution for concurrent edits
    - _Requirements: 1.5, 1.6_

  - [x] 6.2 Add Git operation error handling
    - Implement network failure retry with exponential backoff
    - Add authentication error handling with credential refresh prompts
    - Create user-friendly error messages for common Git issues
    - _Requirements: 3.7, 3.8_

  - [x] 6.3 Add keyboard event error recovery
    - Implement automatic state reset after timeout
    - Add focus management for event handling edge cases
    - Create fallback mechanisms for event conflicts
    - _Requirements: 2.4, 2.5_

- [x] 7. Write comprehensive tests
  - [x] 7.1 Create unit tests for KeyboardEventManager
    - Test command cooldown functionality
    - Verify state management and cleanup
    - Test concurrent command execution prevention
    - _Requirements: 2.1, 2.2, 2.4, 2.5_

  - [x] 7.2 Write tests for GitService
    - Mock repository operations and test error scenarios
    - Test credential validation and storage
    - Verify commit and push operation flows
    - _Requirements: 3.2, 3.3, 3.5, 3.6_

  - [x] 7.3 Add integration tests for node context menu
    - Test right-click detection and menu display
    - Verify node editing workflow end-to-end
    - Test data persistence after node modifications
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

- [x] 8. Final integration and testing
  - [x] 8.1 Integration testing of all features
    - Test keyboard shortcuts work correctly without interference
    - Verify node context menu integrates properly with existing graph
    - Test Git integration works with external data management
    - _Requirements: All requirements_

  - [x] 8.2 Performance optimization and cleanup
    - Optimize context menu creation and disposal
    - Ensure Git operations don't block UI thread
    - Clean up any memory leaks or performance issues
    - _Requirements: All requirements_

  - [x] 8.3 User acceptance testing preparation
    - Create test scenarios for manual verification
    - Document new features for user testing
    - Prepare rollback plan if issues are discovered
    - _Requirements: All requirements_
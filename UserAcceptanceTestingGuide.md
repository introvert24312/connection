# User Acceptance Testing Guide
## Node Interaction and Git Integration Features

### Overview
This document provides comprehensive test scenarios for validating the new node interaction and Git integration features in WordTagger. The testing covers three main areas:

1. **Node Context Menu System** - Right-click functionality for node editing
2. **Keyboard Shortcut Fixes** - Resolved Command+G/Command+W interference
3. **Git Integration** - Repository connectivity and synchronization

### Prerequisites

#### System Requirements
- macOS 14.0 or later
- Xcode 15.0 or later (for development testing)
- Git installed and configured
- Internet connection for Git operations
- At least 1GB free disk space

#### Test Environment Setup
1. Launch WordTagger application
2. Create a test workspace with sample nodes
3. Ensure Git is accessible from command line
4. Have a test Git repository available (GitHub, GitLab, etc.)

### Test Scenarios

## 1. Node Context Menu System Testing

### Test Case 1.1: Right-Click Detection
**Objective**: Verify that right-clicking on graph nodes displays context menu

**Steps**:
1. Open WordTagger and navigate to the graph view
2. Ensure there are visible nodes in the graph
3. Right-click on any node in the graph
4. Observe the context menu appearance

**Expected Results**:
- Context menu appears at cursor position
- Menu contains "Edit Command Label", "Edit Node Name", and "Delete" options
- Menu appears within 200ms of right-click
- Menu is properly positioned and visible

**Pass Criteria**: ✅ Context menu appears with all expected options

### Test Case 1.2: Context Menu Actions
**Objective**: Verify that context menu actions work correctly

**Steps**:
1. Right-click on a node to open context menu
2. Click "Edit Command Label"
3. Verify node editor opens with command field focused
4. Close editor and repeat with "Edit Node Name"
5. Verify node editor opens with name field focused

**Expected Results**:
- Node editor sheet opens for both actions
- Correct field is focused based on selected action
- Editor displays current node data
- Editor can be dismissed with Cancel or Escape

**Pass Criteria**: ✅ Both edit actions open appropriate editor interface

### Test Case 1.3: Node Data Editing
**Objective**: Verify that node data can be modified and saved

**Steps**:
1. Right-click on a node and select "Edit Node Name"
2. Change the node name to "Test Node Modified"
3. Add a command label "test command"
4. Add phonetic notation "test"
5. Add meaning "Modified for testing"
6. Click Save

**Expected Results**:
- All fields accept input correctly
- Save operation completes successfully
- Node displays updated name in graph
- Changes persist after application restart

**Pass Criteria**: ✅ Node data is successfully modified and persisted

### Test Case 1.4: Input Validation
**Objective**: Verify that input validation works correctly

**Steps**:
1. Open node editor
2. Clear the node name field (leave empty)
3. Attempt to save
4. Enter a very long name (300+ characters)
5. Attempt to save
6. Enter a very long command (400+ characters)
7. Attempt to save

**Expected Results**:
- Empty name shows validation error
- Long name shows character limit error
- Long command shows character limit error
- Save button is disabled for invalid input
- Validation messages are clear and helpful

**Pass Criteria**: ✅ Validation prevents invalid data and shows helpful messages

### Test Case 1.5: Concurrent Editing
**Objective**: Verify handling of concurrent node modifications

**Steps**:
1. Open node editor for a specific node
2. Simulate external modification of the same node
3. Attempt to save changes
4. Observe conflict resolution dialog

**Expected Results**:
- Conflict detection works correctly
- User is presented with resolution options
- User can choose to keep their changes or reload
- No data corruption occurs

**Pass Criteria**: ✅ Concurrent editing conflicts are handled gracefully

## 2. Keyboard Shortcut Testing

### Test Case 2.1: Command+G Functionality
**Objective**: Verify Command+G works without interference

**Steps**:
1. Open WordTagger
2. Press Command+G
3. Verify the intended action occurs
4. Wait 1 second
5. Press Command+G again
6. Verify action occurs again

**Expected Results**:
- Command+G executes intended functionality
- No interference from other shortcuts
- Cooldown period prevents rapid re-execution
- Function works consistently

**Pass Criteria**: ✅ Command+G works reliably without conflicts

### Test Case 2.2: Command+W Window Closing
**Objective**: Verify Command+W closes windows correctly

**Steps**:
1. Open WordTagger with multiple windows
2. Press Command+G to activate graph function
3. Immediately press Command+W
4. Verify window closes without triggering Command+G again
5. Repeat test with different timing intervals

**Expected Results**:
- Command+W closes the active window
- No Command+G functionality is triggered
- Window closes cleanly without errors
- Other windows remain unaffected

**Pass Criteria**: ✅ Command+W closes windows without triggering other commands

### Test Case 2.3: Keyboard Shortcut Sequence
**Objective**: Verify complex keyboard shortcut sequences work correctly

**Steps**:
1. Press Command+G
2. Wait for cooldown period (0.5 seconds)
3. Press Command+W
4. Open new window
5. Press Command+G again
6. Press Command+W again

**Expected Results**:
- Each command executes at appropriate time
- No commands interfere with each other
- Cooldown periods are respected
- State is properly cleared between commands

**Pass Criteria**: ✅ Keyboard shortcuts work in sequence without interference

### Test Case 2.4: Error Recovery
**Objective**: Verify keyboard event error recovery works

**Steps**:
1. Trigger rapid keyboard events to cause conflicts
2. Observe error recovery activation
3. Press Escape to trigger recovery
4. Verify normal operation resumes

**Expected Results**:
- Error recovery mode activates when needed
- Recovery commands (Escape) are still functional
- Normal operation resumes after recovery
- No permanent state corruption

**Pass Criteria**: ✅ Error recovery restores normal keyboard functionality

## 3. Git Integration Testing

### Test Case 3.1: Repository Configuration
**Objective**: Verify Git repository can be configured correctly

**Steps**:
1. Open WordTagger Settings
2. Navigate to Git tab
3. Enter a valid GitHub repository URL
4. Click "Configure Credentials"
5. Enter valid username and personal access token
6. Click "Connect"

**Expected Results**:
- Settings interface is intuitive and clear
- Repository URL validation works
- Credential input is secure (token masked)
- Connection test succeeds with valid credentials
- Connection status updates appropriately

**Pass Criteria**: ✅ Repository configuration completes successfully

### Test Case 3.2: Invalid Repository Handling
**Objective**: Verify handling of invalid repository configurations

**Steps**:
1. Enter an invalid repository URL
2. Attempt to connect
3. Enter valid URL with invalid credentials
4. Attempt to connect
5. Enter non-existent repository URL
6. Attempt to connect

**Expected Results**:
- Invalid URL shows appropriate error message
- Invalid credentials show authentication error
- Non-existent repository shows not found error
- Error messages are user-friendly and actionable
- Connection status reflects error state

**Pass Criteria**: ✅ Invalid configurations show helpful error messages

### Test Case 3.3: Commit Operations
**Objective**: Verify that changes can be committed to Git repository

**Steps**:
1. Configure valid Git repository
2. Make changes to WordTagger data
3. Navigate to Git settings
4. Verify pending changes counter updates
5. Enter commit message "Test commit from WordTagger"
6. Click "Commit Changes"

**Expected Results**:
- Pending changes are detected automatically
- Commit operation completes successfully
- Progress indicator shows during operation
- Success message appears after completion
- Commit appears in Git history

**Pass Criteria**: ✅ Changes are successfully committed to repository

### Test Case 3.4: Push Operations
**Objective**: Verify that commits can be pushed to remote repository

**Steps**:
1. Complete Test Case 3.3 (commit changes)
2. Click "Push to Remote"
3. Monitor progress indicator
4. Verify completion message
5. Check remote repository for changes

**Expected Results**:
- Push operation starts immediately
- Progress indicator shows push status
- Operation completes without errors
- Last sync date updates
- Changes appear in remote repository

**Pass Criteria**: ✅ Commits are successfully pushed to remote repository

### Test Case 3.5: Network Error Handling
**Objective**: Verify handling of network-related errors

**Steps**:
1. Configure Git repository
2. Disconnect from internet
3. Attempt to commit changes
4. Attempt to push changes
5. Reconnect to internet
6. Retry operations

**Expected Results**:
- Network errors are detected and reported
- Retry mechanism activates automatically
- User-friendly error messages appear
- Operations succeed after network restoration
- No data corruption occurs

**Pass Criteria**: ✅ Network errors are handled gracefully with retry capability

### Test Case 3.6: Credential Management
**Objective**: Verify secure credential storage and management

**Steps**:
1. Configure repository with credentials
2. Restart WordTagger
3. Verify connection is restored automatically
4. Update credentials with new token
5. Verify updated credentials work
6. Delete stored credentials
7. Verify connection requires re-authentication

**Expected Results**:
- Credentials are stored securely in Keychain
- Automatic reconnection works after restart
- Credential updates are applied correctly
- Credential deletion requires re-authentication
- No credentials are stored in plain text

**Pass Criteria**: ✅ Credentials are managed securely and persistently

## 4. Integration Testing

### Test Case 4.1: End-to-End Workflow
**Objective**: Verify complete workflow from node editing to Git sync

**Steps**:
1. Configure Git repository
2. Right-click on a node
3. Edit node name and command
4. Save changes
5. Verify pending changes counter updates
6. Commit changes with descriptive message
7. Push to remote repository
8. Verify changes in remote repository

**Expected Results**:
- Complete workflow executes without errors
- Each step transitions smoothly to the next
- Data integrity is maintained throughout
- Remote repository reflects all changes
- Performance is acceptable for typical usage

**Pass Criteria**: ✅ Complete workflow executes successfully

### Test Case 4.2: Performance Under Load
**Objective**: Verify performance with multiple operations

**Steps**:
1. Create 50+ nodes in the graph
2. Perform rapid right-click operations on different nodes
3. Edit multiple nodes in sequence
4. Perform Git operations with large changesets
5. Monitor memory usage and response times

**Expected Results**:
- Context menus appear quickly (<200ms)
- Node editing remains responsive
- Git operations handle large changesets
- Memory usage remains stable
- No performance degradation over time

**Pass Criteria**: ✅ Performance remains acceptable under load

### Test Case 4.3: Error Recovery Integration
**Objective**: Verify error recovery across all systems

**Steps**:
1. Trigger keyboard event conflicts
2. Cause node editing errors
3. Simulate Git operation failures
4. Verify each system recovers independently
5. Verify overall application stability

**Expected Results**:
- Each system handles errors independently
- Error recovery doesn't affect other systems
- Application remains stable throughout
- User can continue working after errors
- No permanent state corruption

**Pass Criteria**: ✅ Error recovery works across all integrated systems

## 5. Rollback Plan

### Immediate Rollback Triggers
- Critical functionality is broken
- Data corruption occurs
- Application crashes frequently
- Performance degrades significantly
- Security vulnerabilities discovered

### Rollback Procedure
1. **Immediate Actions**:
   - Stop deployment of new version
   - Document specific issues encountered
   - Notify development team immediately

2. **Code Rollback**:
   - Revert to previous stable commit
   - Remove new feature flags
   - Restore previous keyboard event handling
   - Disable Git integration features

3. **Data Protection**:
   - Backup any user data created with new features
   - Ensure data compatibility with previous version
   - Provide migration path if needed

4. **User Communication**:
   - Notify users of temporary rollback
   - Provide timeline for fix deployment
   - Offer workarounds if available

### Rollback Verification
- [ ] Previous functionality restored
- [ ] No data loss occurred
- [ ] Application stability confirmed
- [ ] User workflows unaffected
- [ ] Performance back to baseline

## 6. Success Criteria

### Functional Requirements
- [ ] All context menu operations work correctly
- [ ] Keyboard shortcuts function without interference
- [ ] Git integration connects and syncs successfully
- [ ] Data validation prevents corruption
- [ ] Error handling provides graceful recovery

### Performance Requirements
- [ ] Context menus appear within 200ms
- [ ] Node editing saves within 1 second
- [ ] Git operations complete within 30 seconds
- [ ] Memory usage remains under 500MB
- [ ] No memory leaks detected

### Usability Requirements
- [ ] Features are discoverable and intuitive
- [ ] Error messages are clear and actionable
- [ ] Workflows are efficient and logical
- [ ] Documentation is comprehensive
- [ ] User feedback is positive

### Reliability Requirements
- [ ] Features work consistently across sessions
- [ ] Error recovery restores normal operation
- [ ] Data integrity is maintained
- [ ] Network issues are handled gracefully
- [ ] Concurrent operations don't conflict

## 7. Test Execution Checklist

### Pre-Testing Setup
- [ ] Test environment configured
- [ ] Sample data prepared
- [ ] Git repository accessible
- [ ] Network connectivity verified
- [ ] Testing tools ready

### During Testing
- [ ] Document all issues found
- [ ] Record performance metrics
- [ ] Capture screenshots/videos of problems
- [ ] Test on different system configurations
- [ ] Verify fixes for reported issues

### Post-Testing
- [ ] Compile comprehensive test report
- [ ] Prioritize issues by severity
- [ ] Verify all critical issues resolved
- [ ] Confirm rollback plan is ready
- [ ] Obtain stakeholder approval

## 8. Contact Information

### Development Team
- **Lead Developer**: [Contact Information]
- **QA Lead**: [Contact Information]
- **Product Manager**: [Contact Information]

### Escalation Path
1. Report issues to QA Lead
2. Critical issues escalate to Lead Developer
3. Rollback decisions involve Product Manager
4. User communication handled by Product Manager

---

**Document Version**: 1.0  
**Last Updated**: 2025-08-19  
**Next Review**: Before feature release
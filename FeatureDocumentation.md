# WordTagger New Features Guide
## Node Interaction and Git Integration

### Overview
WordTagger has been enhanced with powerful new features that make node management and data synchronization more efficient and intuitive. This guide covers the three major improvements:

1. **Node Context Menu** - Right-click editing for quick node modifications
2. **Improved Keyboard Shortcuts** - Resolved conflicts for smoother operation
3. **Git Integration** - Version control and synchronization for your data

---

## 🖱️ Node Context Menu

### What's New
You can now right-click on any node in the graph view to access quick editing options, making node management faster and more intuitive.

### How to Use

#### Accessing the Context Menu
1. Navigate to the graph view in WordTagger
2. Right-click on any node
3. A context menu will appear with the following options:
   - **Edit Command Label** - Modify the command associated with the node
   - **Edit Node Name** - Change the node's display name
   - **Delete Node** - Remove the node (with confirmation)

#### Editing Node Information
1. **Quick Name Edit**:
   - Right-click node → "Edit Node Name"
   - The editor opens with the name field focused
   - Make your changes and click "Save"

2. **Command Label Management**:
   - Right-click node → "Edit Command Label"
   - The editor opens with the command field focused
   - Add or modify commands for quick access
   - Commands are stored in the node's markdown

3. **Complete Node Editing**:
   - Either edit option opens the full node editor
   - Modify name, phonetic notation, meaning, and commands
   - All changes are validated before saving
   - Changes persist across application restarts

#### Tips and Best Practices
- **Quick Access**: Use right-click for faster editing than navigating through menus
- **Command Labels**: Use descriptive commands that help you remember the node's purpose
- **Validation**: The editor prevents saving invalid data (empty names, overly long text)
- **Keyboard Shortcuts**: Use Cmd+Return to save, Escape to cancel

### Troubleshooting
- **Context menu doesn't appear**: Ensure you're right-clicking directly on a node, not empty space
- **Editor won't save**: Check for validation errors (empty name, text too long)
- **Changes don't persist**: Verify you clicked "Save" before closing the editor

---

## ⌨️ Improved Keyboard Shortcuts

### What's Fixed
Previous versions had conflicts between Command+G and Command+W shortcuts. These have been resolved with a new keyboard event management system.

### How It Works

#### Command+G (Graph Function)
- **Function**: Activates graph-related functionality
- **Behavior**: Now works reliably without interference
- **Cooldown**: Brief cooldown period prevents accidental rapid execution
- **Status**: Fully functional and conflict-free

#### Command+W (Window Close)
- **Function**: Closes the active window
- **Behavior**: No longer triggers other commands
- **State Clearing**: Automatically clears any pending command states
- **Status**: Clean window closing without side effects

#### Error Recovery
- **Automatic Recovery**: System detects and recovers from keyboard conflicts
- **Manual Recovery**: Press Escape to manually reset keyboard state
- **Status Indication**: Error recovery mode is indicated in the interface
- **Timeout**: Automatic recovery after 5 seconds if needed

### Best Practices
- **Normal Usage**: Use keyboard shortcuts as usual - the system handles conflicts automatically
- **Rapid Input**: Avoid extremely rapid keyboard input to prevent conflicts
- **Recovery**: If shortcuts seem unresponsive, press Escape to reset
- **Feedback**: Report any persistent keyboard issues for further improvement

### Troubleshooting
- **Shortcuts not working**: Press Escape to reset keyboard state
- **Unexpected behavior**: Wait a moment for cooldown period to expire
- **Persistent issues**: Restart the application to fully reset keyboard state

---

## 🔄 Git Integration

### What's New
WordTagger now supports Git repository integration, allowing you to version control your data and synchronize across multiple devices or collaborate with others.

### Getting Started

#### Initial Setup
1. **Open Settings**:
   - Go to WordTagger → Settings (or Cmd+,)
   - Navigate to the "Git" tab

2. **Configure Repository**:
   - Enter your Git repository URL (GitHub, GitLab, etc.)
   - Example: `https://github.com/username/wordtagger-data.git`
   - Click "Configure Credentials"

3. **Set Up Authentication**:
   - Enter your Git username
   - Enter a Personal Access Token (not your password)
   - Click "Save Credentials"

4. **Test Connection**:
   - Click "Connect"
   - Wait for connection verification
   - Status indicator shows connection state

#### Creating a Personal Access Token
**For GitHub**:
1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Click "Generate new token (classic)"
3. Select scopes: `repo` (for private repos) or `public_repo` (for public repos)
4. Copy the generated token and use it in WordTagger

**For GitLab**:
1. Go to GitLab → User Settings → Access Tokens
2. Create token with `read_repository` and `write_repository` scopes
3. Copy and use the token in WordTagger

### Using Git Integration

#### Committing Changes
1. **Make Changes**: Edit nodes, add content, modify relationships
2. **Check Status**: Git settings show pending changes counter
3. **Commit Changes**:
   - Enter a descriptive commit message
   - Click "Commit Changes"
   - Wait for completion confirmation

#### Pushing to Remote
1. **After Committing**: Ensure you have committed changes locally
2. **Push Changes**:
   - Click "Push to Remote"
   - Monitor progress indicator
   - Verify success message

#### Monitoring Status
- **Connection Status**: Green = connected, Red = error, Orange = connecting
- **Pending Changes**: Counter shows number of uncommitted changes
- **Last Sync**: Displays when you last pushed to remote
- **Repository Info**: Shows current branch and repository URL

### Advanced Features

#### Automatic Change Detection
- WordTagger automatically detects when you make changes
- Pending changes counter updates in real-time
- No manual refresh needed

#### Error Handling and Retry
- Network errors are automatically retried
- Authentication errors prompt for credential refresh
- User-friendly error messages with suggested actions
- Retry mechanisms for temporary failures

#### Security Features
- Credentials stored securely in macOS Keychain
- Tokens are never displayed in plain text
- Secure HTTPS connections only
- No credentials stored in application files

### Best Practices

#### Repository Management
- **Dedicated Repository**: Use a dedicated repository for WordTagger data
- **Regular Commits**: Commit changes frequently with descriptive messages
- **Meaningful Messages**: Use clear commit messages like "Added project nodes" or "Updated relationship mappings"
- **Regular Pushes**: Push to remote regularly to keep data synchronized

#### Security
- **Token Permissions**: Use minimal required permissions for access tokens
- **Token Rotation**: Regularly rotate access tokens for security
- **Private Repositories**: Use private repositories for sensitive data
- **Backup Strategy**: Git serves as backup, but maintain additional backups

#### Collaboration
- **Branch Strategy**: Use branches for experimental changes
- **Merge Conflicts**: Resolve conflicts carefully to avoid data loss
- **Communication**: Coordinate with team members when sharing repositories
- **Access Control**: Manage repository access permissions appropriately

### Troubleshooting

#### Connection Issues
- **Invalid URL**: Verify repository URL format and accessibility
- **Authentication Failed**: Check username and token validity
- **Network Errors**: Verify internet connection and repository availability
- **Permission Denied**: Ensure token has required repository permissions

#### Operation Failures
- **Commit Failed**: Check for uncommitted changes or repository conflicts
- **Push Failed**: Verify network connection and repository permissions
- **Sync Issues**: Try disconnecting and reconnecting to repository

#### Common Solutions
1. **Refresh Credentials**: Update expired or invalid tokens
2. **Check Repository**: Verify repository exists and is accessible
3. **Network Troubleshooting**: Test internet connection and firewall settings
4. **Reset Connection**: Disconnect and reconfigure repository connection

---

## 🔧 Technical Details

### System Requirements
- **macOS**: 14.0 or later
- **Memory**: Minimum 4GB RAM, 8GB recommended
- **Storage**: Additional 100MB for Git operations
- **Network**: Internet connection required for Git operations

### Performance Considerations
- **Context Menus**: Optimized for quick display (<200ms)
- **Git Operations**: Background processing to avoid UI blocking
- **Memory Management**: Automatic cleanup prevents memory leaks
- **Caching**: Intelligent caching reduces network requests

### Data Safety
- **Automatic Backups**: Local backups created before Git operations
- **Validation**: Input validation prevents data corruption
- **Error Recovery**: Robust error handling protects data integrity
- **Rollback Capability**: Can revert to previous stable state if needed

---

## 📞 Support and Feedback

### Getting Help
- **Documentation**: Refer to this guide for common questions
- **Troubleshooting**: Check troubleshooting sections for specific issues
- **Support**: Contact support team for technical assistance
- **Community**: Join user community for tips and best practices

### Reporting Issues
When reporting issues, please include:
- **Steps to Reproduce**: Detailed steps that led to the issue
- **Expected Behavior**: What you expected to happen
- **Actual Behavior**: What actually happened
- **System Information**: macOS version, WordTagger version
- **Screenshots**: Visual evidence of the issue if applicable

### Feature Requests
We welcome feedback and suggestions for improvements:
- **Enhancement Ideas**: Suggest improvements to existing features
- **New Features**: Propose additional functionality
- **Usability Feedback**: Share your experience using the features
- **Integration Requests**: Suggest additional Git providers or tools

---

## 📋 Quick Reference

### Keyboard Shortcuts
- **Cmd+G**: Graph function (with cooldown protection)
- **Cmd+W**: Close window (with state clearing)
- **Escape**: Reset keyboard state / Cancel operations
- **Cmd+Return**: Save in node editor
- **Cmd+,**: Open Settings

### Context Menu Options
- **Right-click node** → Edit Command Label
- **Right-click node** → Edit Node Name  
- **Right-click node** → Delete Node

### Git Operations
1. **Setup**: Settings → Git → Configure Repository
2. **Commit**: Enter message → Commit Changes
3. **Push**: Commit Changes → Push to Remote
4. **Status**: Check connection indicator and pending changes

### Common File Locations
- **User Data**: `~/Library/Application Support/WordTagger/`
- **Git Config**: Stored in application settings
- **Credentials**: macOS Keychain (secure storage)
- **Backups**: Created automatically before Git operations

---

**Version**: 1.0  
**Last Updated**: 2025-08-19  
**Compatible with**: WordTagger 2.0+
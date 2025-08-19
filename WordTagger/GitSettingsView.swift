import SwiftUI

struct GitSettingsView: View {
    @StateObject private var gitService = GitService()
    @State private var repositoryURL: String = ""
    @State private var username: String = ""
    @State private var token: String = ""
    @State private var showingCredentialsSheet = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State private var isConnecting = false
    
    // Enhanced error handling states
    @State private var showingErrorDialog = false
    @State private var showingRetryDialog = false
    @State private var currentError: GitError?
    @State private var errorDetails: (title: String, message: String, action: String)?
    @State private var showingCredentialRefreshDialog = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Connection Status
                GroupBox("Repository Status") {
                    HStack {
                        statusIndicator
                        VStack(alignment: .leading, spacing: 4) {
                            Text(statusText)
                                .font(.headline)
                                .fontWeight(.semibold)
                            if let lastSync = gitService.lastSyncDate {
                                Text("Last sync: \(lastSync, style: .relative) ago")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if gitService.pendingChanges > 0 {
                                Text("\(gitService.pendingChanges) pending changes")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        Spacer()
                        
                        // Connection indicator with animation
                        if gitService.connectionStatus == .connecting || isConnecting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle())
                        }
                    }
                    .padding(12)
                }
                
                // Repository Configuration
                GroupBox("Repository Configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Repository URL")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            TextField("https://github.com/username/repository.git", text: $repositoryURL)
                                .textFieldStyle(.roundedBorder)
                                .disabled(gitService.connectionStatus == .connected)
                            Text("Enter the HTTPS URL of your Git repository")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Button("Configure Credentials") {
                                showingCredentialsSheet = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(repositoryURL.isEmpty)
                            
                            Spacer()
                            
                            if gitService.connectionStatus == .connected {
                                Button("Disconnect") {
                                    disconnectRepository()
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                            } else {
                                Button("Connect") {
                                    Task {
                                        await connectToRepository()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(repositoryURL.isEmpty || username.isEmpty || token.isEmpty || isConnecting)
                            }
                        }
                    }
                    .padding(12)
                }
                
                // Git Operations (only show when connected)
                if gitService.connectionStatus == .connected {
                    GroupBox("Git Operations") {
                        VStack(spacing: 16) {
                            // Repository Status Section
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Repository Status")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    Spacer()
                                    
                                    Button("Refresh") {
                                        Task {
                                            await gitService.checkPendingChanges()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(gitService.isOperationInProgress)
                                }
                                
                                HStack(spacing: 16) {
                                    // Pending changes indicator
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(gitService.pendingChanges > 0 ? Color.orange : Color.green)
                                            .frame(width: 8, height: 8)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(gitService.pendingChanges)")
                                                .font(.title3)
                                                .fontWeight(.bold)
                                                .foregroundColor(gitService.pendingChanges > 0 ? .orange : .green)
                                            Text("Pending Changes")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Last sync indicator
                                    if let lastSync = gitService.lastSyncDate {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(lastSync, style: .relative)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.blue)
                                            Text("Last Sync")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            // Operation Progress Section
                            if gitService.isOperationInProgress, let progress = gitService.operationProgress {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Operation in Progress")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        Spacer()
                                        
                                        Text("\(Int(progress.progress * 100))%")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.blue)
                                    }
                                    
                                    ProgressView(value: progress.progress)
                                        .progressViewStyle(LinearProgressViewStyle())
                                    
                                    HStack {
                                        Text(progress.phase)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.blue)
                                        
                                        Spacer()
                                        
                                        Text(progress.message)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 8)
                                
                                Divider()
                            }
                            
                            // Action Buttons Section
                            VStack(spacing: 12) {
                                // Commit section
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Commit Changes")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("Save current changes to local repository")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button("Commit") {
                                        Task {
                                            await commitChanges()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(gitService.pendingChanges == 0 || gitService.isOperationInProgress)
                                }
                                
                                // Push section
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Push to Remote")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("Upload committed changes to remote repository")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button("Push") {
                                        Task {
                                            await pushChanges()
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(gitService.isOperationInProgress)
                                }
                                
                                // Quick commit and push
                                if gitService.pendingChanges > 0 {
                                    Divider()
                                    
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Quick Sync")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Text("Commit and push changes in one action")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button("Commit & Push") {
                                            Task {
                                                await commitAndPushChanges()
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(gitService.isOperationInProgress)
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showingCredentialsSheet) {
            GitCredentialsSheet(
                repositoryURL: repositoryURL,
                username: $username,
                token: $token,
                onSave: { savedUsername, savedToken in
                    username = savedUsername
                    token = savedToken
                    showingCredentialsSheet = false
                },
                onCancel: {
                    showingCredentialsSheet = false
                }
            )
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .alert("Git Operation Failed", isPresented: $showingErrorDialog) {
            if let error = currentError, error.isRetryable {
                Button("Retry") {
                    Task {
                        await retryLastOperation()
                    }
                }
                Button("Cancel") {
                    currentError = nil
                }
            } else {
                Button("OK") {
                    currentError = nil
                }
            }
        } message: {
            if let details = errorDetails {
                VStack(alignment: .leading, spacing: 8) {
                    Text(details.message)
                    Text("Suggested action: \(details.action)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .alert("Retry Operation", isPresented: $showingRetryDialog) {
            Button("Retry Now") {
                Task {
                    await retryLastOperation()
                }
            }
            Button("Cancel") {
                showingRetryDialog = false
            }
        } message: {
            Text("The operation failed but can be retried. Attempt \(gitService.retryCount + 1) of \(3).")
        }
        .alert("Credentials Required", isPresented: $showingCredentialRefreshDialog) {
            Button("Update Credentials") {
                showingCredentialsSheet = true
                showingCredentialRefreshDialog = false
            }
            Button("Cancel") {
                showingCredentialRefreshDialog = false
            }
        } message: {
            Text("Your Git credentials need to be updated. Please provide new credentials to continue.")
        }
        .onAppear {
            loadExistingConfiguration()
            setupNotificationObservers()
        }
    }
    
    // MARK: - Status Indicators
    
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 12, height: 12)
    }
    
    private var statusColor: Color {
        switch gitService.connectionStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }
    
    private var statusText: String {
        switch gitService.connectionStatus {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .error(let message): return "Error: \(message)"
        case .disconnected: return "Not connected"
        }
    }
    
    // MARK: - Actions
    
    private func loadExistingConfiguration() {
        // Load any existing configuration from the GitService
        // This would be called when the view appears
    }
    
    private func connectToRepository() async {
        guard !repositoryURL.isEmpty, !username.isEmpty, !token.isEmpty else {
            showAlert(title: "Missing Information", message: "Please provide repository URL and configure credentials.")
            return
        }
        
        isConnecting = true
        
        do {
            let credentials = GitCredentials(username: username, token: token)
            try await gitService.configureRepository(url: repositoryURL, credentials: credentials)
            
            // Refresh pending changes after successful connection
            await gitService.checkPendingChanges()
            
            showAlert(title: "Success", message: "Successfully connected to repository.")
        } catch {
            showAlert(title: "Connection Failed", message: error.localizedDescription)
        }
        
        isConnecting = false
    }
    
    private func disconnectRepository() {
        gitService.disconnect()
        repositoryURL = ""
        username = ""
        token = ""
        showAlert(title: "Disconnected", message: "Repository has been disconnected.")
    }
    
    private func commitChanges() async {
        do {
            let commitMessage = "Auto-commit from WordTagger - \(Date().formatted(date: .abbreviated, time: .shortened))"
            try await gitService.commitChanges(message: commitMessage)
            showAlert(title: "Commit Successful", message: "Changes have been successfully committed to the local repository.")
        } catch {
            await handleGitError(error, operation: "commit")
        }
    }
    
    private func pushChanges() async {
        do {
            try await gitService.pushToRemote()
            showAlert(title: "Push Successful", message: "Changes have been successfully pushed to the remote repository.")
        } catch {
            await handleGitError(error, operation: "push")
        }
    }
    
    private func commitAndPushChanges() async {
        do {
            // First commit the changes
            let commitMessage = "Auto-sync from WordTagger - \(Date().formatted(date: .abbreviated, time: .shortened))"
            try await gitService.commitChanges(message: commitMessage)
            
            // Then push to remote
            try await gitService.pushToRemote()
            
            showAlert(title: "Sync Successful", message: "Changes have been committed and pushed to the remote repository.")
        } catch {
            await handleGitError(error, operation: "sync")
        }
    }
    
    private func formatGitError(_ error: Error) -> String {
        if let gitError = error as? GitError {
            switch gitError {
            case .networkError:
                return "Network connection failed. Please check your internet connection and try again."
            case .authenticationFailed:
                return "Authentication failed. Please check your credentials and try again."
            case .commitFailed(let message):
                return "Commit failed: \(message)\n\nPlease ensure there are changes to commit."
            case .pushFailed(let message):
                return "Push failed: \(message)\n\nThis might be due to conflicts or network issues."
            default:
                return gitError.localizedDescription
            }
        }
        return error.localizedDescription
    }
    
    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
    
    // MARK: - Enhanced Error Handling
    
    private func handleGitError(_ error: Error, operation: String) async {
        if let gitError = error as? GitError {
            currentError = gitError
            errorDetails = gitService.getDetailedErrorMessage(gitError)
            
            // Handle specific error types
            switch gitError {
            case .authenticationFailed, .invalidCredentials, .tokenExpired:
                showingCredentialRefreshDialog = true
                return
                
            case .networkError, .connectionTimeout, .serverUnavailable:
                if gitError.isRetryable && gitService.retryCount < 3 {
                    showingRetryDialog = true
                    return
                }
                
            default:
                break
            }
            
            showingErrorDialog = true
        } else {
            // Fallback for non-GitError types
            showAlert(title: "\(operation.capitalized) Failed", message: error.localizedDescription)
        }
    }
    
    private func retryLastOperation() async {
        do {
            try await gitService.retryLastOperation()
            showAlert(title: "Operation Successful", message: "The operation completed successfully after retry.")
        } catch {
            await handleGitError(error, operation: "retry")
        }
    }
    
    private func handleAuthenticationError() {
        showingCredentialRefreshDialog = true
    }
    
    // MARK: - Notification Handling
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .gitAuthenticationRequired,
            object: nil,
            queue: .main
        ) { _ in
            self.handleAuthenticationError()
        }
        
        NotificationCenter.default.addObserver(
            forName: .gitOperationFailed,
            object: nil,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?["error"] as? GitError {
                Task {
                    await self.handleGitError(error, operation: "operation")
                }
            }
        }
    }
}

// MARK: - Preview

struct GitSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GitSettingsView()
            .frame(width: 600, height: 500)
    }
}
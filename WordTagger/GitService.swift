import Foundation
import Security

// MARK: - Git Service Errors
enum GitError: Error, LocalizedError {
    case invalidRepository
    case notConnected
    case authenticationFailed
    case networkError(underlying: Error?)
    case commitFailed(String)
    case pushFailed(String)
    case credentialStorageFailed
    case credentialRetrievalFailed
    case repositoryNotFound
    case permissionDenied
    case diskSpaceInsufficient
    case connectionTimeout
    case rateLimitExceeded
    case serverUnavailable
    case conflictDetected
    case branchProtected
    case invalidCredentials
    case tokenExpired
    
    var errorDescription: String? {
        switch self {
        case .invalidRepository:
            return "Invalid repository URL or repository not accessible"
        case .notConnected:
            return "Not connected to a Git repository"
        case .authenticationFailed:
            return "Authentication failed. Please check your credentials"
        case .networkError(let underlying):
            if let underlying = underlying {
                return "Network error: \(underlying.localizedDescription)"
            }
            return "Network error occurred during Git operation"
        case .commitFailed(let message):
            return "Commit failed: \(message)"
        case .pushFailed(let message):
            return "Push failed: \(message)"
        case .credentialStorageFailed:
            return "Failed to store credentials securely"
        case .credentialRetrievalFailed:
            return "Failed to retrieve stored credentials"
        case .repositoryNotFound:
            return "Repository not found. Please check the URL and your access permissions"
        case .permissionDenied:
            return "Permission denied. You may not have write access to this repository"
        case .diskSpaceInsufficient:
            return "Insufficient disk space to complete the operation"
        case .connectionTimeout:
            return "Connection timed out. Please check your internet connection"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please wait before trying again"
        case .serverUnavailable:
            return "Git server is temporarily unavailable. Please try again later"
        case .conflictDetected:
            return "Merge conflict detected. Please resolve conflicts manually"
        case .branchProtected:
            return "Cannot push to protected branch. Check branch protection rules"
        case .invalidCredentials:
            return "Invalid credentials. Please update your username and token"
        case .tokenExpired:
            return "Access token has expired. Please generate a new token"
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .networkError, .connectionTimeout, .serverUnavailable, .rateLimitExceeded:
            return true
        case .authenticationFailed, .invalidCredentials, .tokenExpired:
            return false // Requires user intervention
        case .permissionDenied, .branchProtected, .repositoryNotFound:
            return false // Configuration issue
        case .diskSpaceInsufficient:
            return false // System issue
        case .conflictDetected:
            return false // Requires manual resolution
        default:
            return false
        }
    }
    
    var suggestedAction: String {
        switch self {
        case .authenticationFailed, .invalidCredentials:
            return "Please check your username and personal access token"
        case .tokenExpired:
            return "Please generate a new personal access token from your Git provider"
        case .repositoryNotFound:
            return "Verify the repository URL and ensure you have access permissions"
        case .permissionDenied:
            return "Contact the repository owner to request write access"
        case .networkError, .connectionTimeout:
            return "Check your internet connection and try again"
        case .serverUnavailable:
            return "The Git server is temporarily down. Please try again later"
        case .rateLimitExceeded:
            return "You've exceeded the API rate limit. Please wait before trying again"
        case .diskSpaceInsufficient:
            return "Free up disk space and try again"
        case .conflictDetected:
            return "Resolve merge conflicts manually before pushing"
        case .branchProtected:
            return "Use a pull request or contact an administrator to modify branch protection rules"
        default:
            return "Please try again or contact support if the problem persists"
        }
    }
}

// MARK: - Git Connection Status
enum GitConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    static func == (lhs: GitConnectionStatus, rhs: GitConnectionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

// MARK: - Git Credentials
struct GitCredentials {
    let username: String
    let token: String
    
    init(username: String, token: String) {
        self.username = username
        self.token = token
    }
}

// MARK: - Git Configuration
struct GitConfiguration: Codable {
    let repositoryURL: String
    let username: String
    let lastSyncDate: Date?
    let autoSync: Bool
    
    init(repositoryURL: String, username: String, lastSyncDate: Date? = nil, autoSync: Bool = false) {
        self.repositoryURL = repositoryURL
        self.username = username
        self.lastSyncDate = lastSyncDate
        self.autoSync = autoSync
    }
}

// MARK: - Git Service
@MainActor
class GitService: ObservableObject {
    @Published var connectionStatus: GitConnectionStatus = .disconnected
    @Published var lastSyncDate: Date?
    @Published var pendingChanges: Int = 0
    @Published var isOperationInProgress: Bool = false
    @Published var operationProgress: GitOperationProgress?
    @Published var repositoryStatus: GitRepositoryStatus = GitRepositoryStatus()
    @Published var lastError: GitError?
    @Published var retryCount: Int = 0
    @Published var isRetrying: Bool = false
    
    private var repositoryURL: String?
    private var credentials: GitCredentials?
    private var configuration: GitConfiguration?
    private var gitOperations: GitOperations?
    
    // Configuration and keychain management
    private let keychainManager = KeychainManager.shared
    private let configurationKey = "GitConfiguration"
    
    // Retry configuration
    private let maxRetryAttempts = 3
    private let baseRetryDelay: TimeInterval = 1.0
    private let maxRetryDelay: TimeInterval = 30.0
    private var currentRetryDelay: TimeInterval = 1.0
    
    init() {
        // Initialize with default working directory (Documents/WordTagger)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let workingDirectory = documentsPath.appendingPathComponent("WordTagger")
        self.gitOperations = GitOperations(workingDirectory: workingDirectory)
        
        loadConfiguration()
    }
    
    convenience init(workingDirectory: URL) {
        self.init()
        self.gitOperations = GitOperations(workingDirectory: workingDirectory)
    }
    
    // MARK: - Repository Configuration
    func configureRepository(url: String, credentials: GitCredentials) async throws {
        connectionStatus = .connecting
        
        // Validate repository URL format
        guard isValidRepositoryURL(url) else {
            connectionStatus = .error("Invalid repository URL format")
            throw GitError.invalidRepository
        }
        
        // Test repository accessibility
        do {
            let isAccessible = try await validateRepository(url: url, credentials: credentials)
            guard isAccessible else {
                connectionStatus = .error("Unable to access repository")
                throw GitError.invalidRepository
            }
            
            // Store configuration
            self.repositoryURL = url
            self.credentials = credentials
            
            let config = GitConfiguration(
                repositoryURL: url,
                username: credentials.username,
                lastSyncDate: lastSyncDate,
                autoSync: false
            )
            self.configuration = config
            
            // Save configuration and credentials
            try saveConfiguration(config)
            try keychainManager.saveGitCredentials(credentials, for: url)
            
            connectionStatus = .connected
            
        } catch {
            connectionStatus = .error(error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Git Operations
    func commitChanges(message: String) async throws {
        try await performOperationWithRetry {
            try await self.performCommitOperation(message: message)
        }
    }
    
    private func performCommitOperation(message: String) async throws {
        guard connectionStatus == .connected else {
            throw GitError.notConnected
        }
        
        guard let repoURL = repositoryURL,
              let creds = credentials else {
            throw GitError.notConnected
        }
        
        isOperationInProgress = true
        operationProgress = nil
        
        defer { 
            isOperationInProgress = false
            operationProgress = nil
        }
        
        do {
            try await performCommit(repositoryURL: repoURL, credentials: creds, message: message)
            // Refresh repository status
            await refreshRepositoryStatus()
            
            // Reset retry state on success
            resetRetryState()
        } catch {
            let gitError = mapToGitError(error)
            lastError = gitError
            throw gitError
        }
    }
    
    func pushToRemote() async throws {
        try await performOperationWithRetry {
            try await self.performPushOperation()
        }
    }
    
    private func performPushOperation() async throws {
        guard connectionStatus == .connected else {
            throw GitError.notConnected
        }
        
        guard let repoURL = repositoryURL,
              let creds = credentials else {
            throw GitError.notConnected
        }
        
        isOperationInProgress = true
        operationProgress = nil
        
        defer { 
            isOperationInProgress = false
            operationProgress = nil
        }
        
        do {
            try await performPush(repositoryURL: repoURL, credentials: creds)
            lastSyncDate = Date()
            
            // Update configuration with new sync date
            if var config = configuration {
                config = GitConfiguration(
                    repositoryURL: config.repositoryURL,
                    username: config.username,
                    lastSyncDate: lastSyncDate,
                    autoSync: config.autoSync
                )
                self.configuration = config
                try saveConfiguration(config)
            }
            
            // Refresh repository status
            await refreshRepositoryStatus()
            
            // Reset retry state on success
            resetRetryState()
        } catch {
            let gitError = mapToGitError(error)
            lastError = gitError
            throw gitError
        }
    }
    
    func disconnect() {
        repositoryURL = nil
        credentials = nil
        configuration = nil
        connectionStatus = .disconnected
        lastSyncDate = nil
        pendingChanges = 0
        
        // Clear stored configuration
        UserDefaults.standard.removeObject(forKey: configurationKey)
    }
    
    // MARK: - Repository Validation
    private func isValidRepositoryURL(_ url: String) -> Bool {
        // Basic URL validation for Git repositories
        let gitURLPattern = #"^https://github\.com/[\w\-\.]+/[\w\-\.]+(?:\.git)?/?$"#
        let regex = try? NSRegularExpression(pattern: gitURLPattern)
        let range = NSRange(location: 0, length: url.utf16.count)
        return regex?.firstMatch(in: url, options: [], range: range) != nil
    }
    
    private func validateRepository(url: String, credentials: GitCredentials) async throws -> Bool {
        guard let operations = gitOperations else {
            throw GitError.notConnected
        }
        
        return try await operations.testRepositoryConnectivity(url: url, credentials: credentials)
    }
    
    // MARK: - Git Operations Implementation
    private func performCommit(repositoryURL: String, credentials: GitCredentials, message: String) async throws {
        guard let operations = gitOperations else {
            throw GitError.notConnected
        }
        
        try await operations.commitChanges(message: message) { [weak self] progress in
            DispatchQueue.main.async {
                self?.operationProgress = progress
            }
        }
    }
    
    private func performPush(repositoryURL: String, credentials: GitCredentials) async throws {
        guard let operations = gitOperations else {
            throw GitError.notConnected
        }
        
        try await operations.pushToRemote(credentials: credentials) { [weak self] progress in
            DispatchQueue.main.async {
                self?.operationProgress = progress
            }
        }
    }
}   
 
    // MARK: - Configuration Management
    private func saveConfiguration(_ config: GitConfiguration) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        UserDefaults.standard.set(data, forKey: configurationKey)
    }
    
    private func loadConfiguration() {
        guard let data = UserDefaults.standard.data(forKey: configurationKey) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let config = try decoder.decode(GitConfiguration.self, from: data)
            self.configuration = config
            self.repositoryURL = config.repositoryURL
            self.lastSyncDate = config.lastSyncDate
            
            // Try to load credentials
            do {
                let allCredentials = try keychainManager.loadAllGitCredentials(for: config.repositoryURL)
                if let credentials = allCredentials.first(where: { $0.username == config.username }) {
                    self.credentials = credentials
                    connectionStatus = .connected
                } else {
                    connectionStatus = .error("Credentials not found")
                }
            } catch {
                connectionStatus = .error("Failed to load credentials")
            }
        } catch {
            print("Failed to load Git configuration: \(error)")
        }
    }
    
    // MARK: - Credential Management
    func getAllStoredCredentials(for repositoryURL: String) throws -> [GitCredentials] {
        return try keychainManager.loadAllGitCredentials(for: repositoryURL)
    }
    
    func deleteStoredCredentials(for repositoryURL: String, username: String) throws {
        try keychainManager.deleteGitCredentials(for: repositoryURL, username: username)
    }
    
    func deleteAllStoredCredentials(for repositoryURL: String) throws {
        try keychainManager.deleteAllGitCredentials(for: repositoryURL)
    }
    
    // MARK: - Utility Methods
    func refreshCredentials(_ newCredentials: GitCredentials) async throws {
        guard let repoURL = repositoryURL else {
            throw GitError.notConnected
        }
        
        // Test new credentials
        connectionStatus = .connecting
        
        do {
            let isValid = try await validateRepository(url: repoURL, credentials: newCredentials)
            guard isValid else {
                connectionStatus = .error("Invalid credentials")
                throw GitError.authenticationFailed
            }
            
            // Update stored credentials
            try keychainManager.saveGitCredentials(newCredentials, for: repoURL)
            self.credentials = newCredentials
            connectionStatus = .connected
            
        } catch {
            connectionStatus = .error(error.localizedDescription)
            throw error
        }
    }
    
    func refreshRepositoryStatus() async {
        guard let operations = gitOperations else {
            repositoryStatus = GitRepositoryStatus()
            pendingChanges = 0
            return
        }
        
        do {
            let status = try await operations.getRepositoryStatus()
            repositoryStatus = status
            pendingChanges = status.uncommittedFiles.count
        } catch {
            repositoryStatus = GitRepositoryStatus()
            pendingChanges = 0
        }
    }
    
    func checkPendingChanges() async {
        await refreshRepositoryStatus()
    }
    
    // MARK: - Repository Management
    func initializeLocalRepository() async throws {
        guard let operations = gitOperations else {
            throw GitError.notConnected
        }
        
        try await operations.initializeRepository()
        await refreshRepositoryStatus()
    }
    
    func addRemoteRepository(url: String, name: String = "origin") async throws {
        guard let operations = gitOperations else {
            throw GitError.notConnected
        }
        
        try await operations.addRemote(url: url, name: name)
    }
    
    // MARK: - Status Monitoring
    func startPeriodicStatusCheck(interval: TimeInterval = 30.0) {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshRepositoryStatus()
            }
        }
    }
    
    // MARK: - Credential Validation
    func validateCredentials(_ credentials: GitCredentials, for repositoryURL: String) async throws -> Bool {
        do {
            return try await validateRepository(url: repositoryURL, credentials: credentials)
        } catch {
            throw GitError.authenticationFailed
        }
    }
    
    func refreshStoredCredentials(for repositoryURL: String, username: String, newToken: String) async throws {
        let newCredentials = GitCredentials(username: username, token: newToken)
        
        // Validate new credentials first
        let isValid = try await validateCredentials(newCredentials, for: repositoryURL)
        guard isValid else {
            throw GitError.authenticationFailed
        }
        
        // Save new credentials
        try keychainManager.saveGitCredentials(newCredentials, for: repositoryURL)
        
        // Update current credentials if this is the active repository
        if self.repositoryURL == repositoryURL && self.credentials?.username == username {
            self.credentials = newCredentials
        }
    }
    
    func hasStoredCredentials(for repositoryURL: String, username: String) -> Bool {
        do {
            let credentials = try keychainManager.loadGitCredentials(for: repositoryURL, username: username)
            return credentials != nil
        } catch {
            return false
        }
    }
    
    func getStoredCredentials(for repositoryURL: String, username: String) throws -> GitCredentials? {
        return try keychainManager.loadGitCredentials(for: repositoryURL, username: username)
    }
    
    // MARK: - Error Handling and Retry Logic
    
    private func performOperationWithRetry<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxRetryAttempts {
            do {
                retryCount = attempt
                if attempt > 0 {
                    isRetrying = true
                    // Calculate exponential backoff delay
                    let delay = calculateRetryDelay(attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                
                let result = try await operation()
                
                // Success - reset retry state
                resetRetryState()
                return result
                
            } catch {
                lastError = error
                let gitError = mapToGitError(error)
                
                // Don't retry if error is not retryable
                if !gitError.isRetryable {
                    resetRetryState()
                    throw gitError
                }
                
                // Don't retry on last attempt
                if attempt == maxRetryAttempts - 1 {
                    resetRetryState()
                    throw gitError
                }
                
                print("Git operation failed (attempt \(attempt + 1)/\(maxRetryAttempts)): \(gitError.localizedDescription)")
            }
        }
        
        resetRetryState()
        throw lastError ?? GitError.networkError(underlying: nil)
    }
    
    private func calculateRetryDelay(attempt: Int) -> TimeInterval {
        // Exponential backoff with jitter
        let exponentialDelay = baseRetryDelay * pow(2.0, Double(attempt))
        let jitter = Double.random(in: 0.8...1.2) // Add 20% jitter
        let delayWithJitter = exponentialDelay * jitter
        
        return min(delayWithJitter, maxRetryDelay)
    }
    
    private func resetRetryState() {
        retryCount = 0
        isRetrying = false
        currentRetryDelay = baseRetryDelay
        lastError = nil
    }
    
    private func mapToGitError(_ error: Error) -> GitError {
        // Map common errors to specific GitError cases
        let errorDescription = error.localizedDescription.lowercased()
        
        if errorDescription.contains("authentication failed") || errorDescription.contains("invalid credentials") {
            return .authenticationFailed
        } else if errorDescription.contains("repository not found") || errorDescription.contains("not found") {
            return .repositoryNotFound
        } else if errorDescription.contains("permission denied") || errorDescription.contains("forbidden") {
            return .permissionDenied
        } else if errorDescription.contains("timeout") || errorDescription.contains("timed out") {
            return .connectionTimeout
        } else if errorDescription.contains("rate limit") || errorDescription.contains("too many requests") {
            return .rateLimitExceeded
        } else if errorDescription.contains("server error") || errorDescription.contains("service unavailable") {
            return .serverUnavailable
        } else if errorDescription.contains("conflict") || errorDescription.contains("merge") {
            return .conflictDetected
        } else if errorDescription.contains("protected") || errorDescription.contains("branch protection") {
            return .branchProtected
        } else if errorDescription.contains("token") && errorDescription.contains("expired") {
            return .tokenExpired
        } else if errorDescription.contains("disk") && errorDescription.contains("space") {
            return .diskSpaceInsufficient
        } else if errorDescription.contains("network") || errorDescription.contains("connection") {
            return .networkError(underlying: error)
        }
        
        // Default to network error for unknown errors
        return .networkError(underlying: error)
    }
    
    // MARK: - User-Friendly Error Messages
    
    func getDetailedErrorMessage(_ error: GitError) -> (title: String, message: String, action: String) {
        let title: String
        let message: String
        let action = error.suggestedAction
        
        switch error {
        case .authenticationFailed, .invalidCredentials:
            title = "Authentication Failed"
            message = "Your Git credentials are invalid or have been rejected by the server."
            
        case .tokenExpired:
            title = "Access Token Expired"
            message = "Your personal access token has expired and needs to be renewed."
            
        case .repositoryNotFound:
            title = "Repository Not Found"
            message = "The specified repository could not be found or you don't have access to it."
            
        case .permissionDenied:
            title = "Permission Denied"
            message = "You don't have the necessary permissions to perform this operation on the repository."
            
        case .networkError:
            title = "Network Error"
            message = "A network error occurred while communicating with the Git server."
            
        case .connectionTimeout:
            title = "Connection Timeout"
            message = "The connection to the Git server timed out. This might be due to a slow internet connection or server issues."
            
        case .serverUnavailable:
            title = "Server Unavailable"
            message = "The Git server is currently unavailable or experiencing issues."
            
        case .rateLimitExceeded:
            title = "Rate Limit Exceeded"
            message = "You've made too many requests in a short period. Please wait before trying again."
            
        case .conflictDetected:
            title = "Merge Conflict"
            message = "There are conflicting changes that need to be resolved manually."
            
        case .branchProtected:
            title = "Branch Protected"
            message = "The target branch is protected and doesn't allow direct pushes."
            
        case .diskSpaceInsufficient:
            title = "Insufficient Disk Space"
            message = "There isn't enough disk space to complete the Git operation."
            
        default:
            title = "Git Operation Failed"
            message = error.localizedDescription
        }
        
        return (title: title, message: message, action: action)
    }
    
    // MARK: - Credential Refresh Handling
    
    func handleAuthenticationError() async throws {
        // Clear current credentials to force re-authentication
        credentials = nil
        connectionStatus = .error("Authentication required")
        
        // Notify UI to show credential input dialog
        NotificationCenter.default.post(
            name: .gitAuthenticationRequired,
            object: self,
            userInfo: ["repositoryURL": repositoryURL ?? ""]
        )
    }
    
    func retryLastOperation() async throws {
        guard let lastError = lastError else {
            throw GitError.notConnected
        }
        
        // Only retry if the error is retryable
        guard lastError.isRetryable else {
            throw lastError
        }
        
        // Reset retry count for manual retry
        retryCount = 0
        
        // The specific operation will need to be tracked and re-executed
        // This is a simplified implementation
        throw GitError.notConnected // Placeholder
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let gitAuthenticationRequired = Notification.Name("gitAuthenticationRequired")
    static let gitOperationFailed = Notification.Name("gitOperationFailed")
    static let gitOperationSucceeded = Notification.Name("gitOperationSucceeded")
}
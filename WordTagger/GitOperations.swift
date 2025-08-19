import Foundation

// MARK: - Git Operations Progress
struct GitOperationProgress {
    let phase: String
    let progress: Double // 0.0 to 1.0
    let message: String
    
    init(phase: String, progress: Double, message: String) {
        self.phase = phase
        self.progress = max(0.0, min(1.0, progress))
        self.message = message
    }
}

// MARK: - Git Repository Status
struct GitRepositoryStatus {
    let isConnected: Bool
    let hasUncommittedChanges: Bool
    let uncommittedFiles: [String]
    let currentBranch: String?
    let lastCommitHash: String?
    let lastCommitMessage: String?
    let lastCommitDate: Date?
    
    init(isConnected: Bool = false,
         hasUncommittedChanges: Bool = false,
         uncommittedFiles: [String] = [],
         currentBranch: String? = nil,
         lastCommitHash: String? = nil,
         lastCommitMessage: String? = nil,
         lastCommitDate: Date? = nil) {
        self.isConnected = isConnected
        self.hasUncommittedChanges = hasUncommittedChanges
        self.uncommittedFiles = uncommittedFiles
        self.currentBranch = currentBranch
        self.lastCommitHash = lastCommitHash
        self.lastCommitMessage = lastCommitMessage
        self.lastCommitDate = lastCommitDate
    }
}

// MARK: - Git Operations Manager
class GitOperations {
    private let workingDirectory: URL
    private let fileManager = FileManager.default
    
    init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }
    
    // MARK: - Repository Connectivity Testing
    func testRepositoryConnectivity(url: String, credentials: GitCredentials) async throws -> Bool {
        // Create a temporary directory for testing
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer {
                try? fileManager.removeItem(at: tempDir)
            }
            
            // Test connectivity by attempting a shallow clone
            let result = try await executeGitCommand([
                "clone",
                "--depth", "1",
                "--quiet",
                authenticatedURL(url, credentials: credentials),
                tempDir.path
            ], workingDirectory: tempDir.deletingLastPathComponent())
            
            return result.exitCode == 0
            
        } catch {
            return false
        }
    }
    
    func getRepositoryStatus() async throws -> GitRepositoryStatus {
        // Check if we're in a git repository
        let isRepoResult = try await executeGitCommand(["rev-parse", "--git-dir"], workingDirectory: workingDirectory)
        guard isRepoResult.exitCode == 0 else {
            return GitRepositoryStatus()
        }
        
        // Get current branch
        let branchResult = try await executeGitCommand(["branch", "--show-current"], workingDirectory: workingDirectory)
        let currentBranch = branchResult.exitCode == 0 ? branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        
        // Get uncommitted files
        let statusResult = try await executeGitCommand(["status", "--porcelain"], workingDirectory: workingDirectory)
        let uncommittedFiles = statusResult.exitCode == 0 ? 
            statusResult.output.components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
                .map { String($0.dropFirst(3)) } : []
        
        // Get last commit info
        let logResult = try await executeGitCommand([
            "log", "-1", "--format=%H|%s|%ct"
        ], workingDirectory: workingDirectory)
        
        var lastCommitHash: String?
        var lastCommitMessage: String?
        var lastCommitDate: Date?
        
        if logResult.exitCode == 0 && !logResult.output.isEmpty {
            let components = logResult.output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
            if components.count >= 3 {
                lastCommitHash = components[0]
                lastCommitMessage = components[1]
                if let timestamp = TimeInterval(components[2]) {
                    lastCommitDate = Date(timeIntervalSince1970: timestamp)
                }
            }
        }
        
        return GitRepositoryStatus(
            isConnected: true,
            hasUncommittedChanges: !uncommittedFiles.isEmpty,
            uncommittedFiles: uncommittedFiles,
            currentBranch: currentBranch,
            lastCommitHash: lastCommitHash,
            lastCommitMessage: lastCommitMessage,
            lastCommitDate: lastCommitDate
        )
    }
    
    // MARK: - Commit Operations
    func commitChanges(message: String, progressHandler: @escaping (GitOperationProgress) -> Void) async throws {
        progressHandler(GitOperationProgress(phase: "Staging", progress: 0.0, message: "Staging files..."))
        
        // Stage all changes
        let addResult = try await executeGitCommand(["add", "."], workingDirectory: workingDirectory)
        guard addResult.exitCode == 0 else {
            throw GitError.commitFailed("Failed to stage files: \(addResult.error)")
        }
        
        progressHandler(GitOperationProgress(phase: "Staging", progress: 0.5, message: "Files staged successfully"))
        
        // Check if there are any changes to commit
        let statusResult = try await executeGitCommand(["status", "--porcelain", "--cached"], workingDirectory: workingDirectory)
        guard !statusResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitError.commitFailed("No changes to commit")
        }
        
        progressHandler(GitOperationProgress(phase: "Committing", progress: 0.7, message: "Creating commit..."))
        
        // Create commit
        let commitResult = try await executeGitCommand([
            "commit", "-m", message
        ], workingDirectory: workingDirectory)
        
        guard commitResult.exitCode == 0 else {
            throw GitError.commitFailed("Failed to create commit: \(commitResult.error)")
        }
        
        progressHandler(GitOperationProgress(phase: "Committing", progress: 1.0, message: "Commit created successfully"))
    }
    
    // MARK: - Push Operations
    func pushToRemote(credentials: GitCredentials, progressHandler: @escaping (GitOperationProgress) -> Void) async throws {
        progressHandler(GitOperationProgress(phase: "Preparing", progress: 0.0, message: "Preparing to push..."))
        
        // Get remote URL
        let remoteResult = try await executeGitCommand(["remote", "get-url", "origin"], workingDirectory: workingDirectory)
        guard remoteResult.exitCode == 0 else {
            throw GitError.pushFailed("No remote repository configured")
        }
        
        let remoteURL = remoteResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let authenticatedRemoteURL = authenticatedURL(remoteURL, credentials: credentials)
        
        progressHandler(GitOperationProgress(phase: "Pushing", progress: 0.3, message: "Pushing to remote..."))
        
        // Push to remote
        let pushResult = try await executeGitCommand([
            "push", authenticatedRemoteURL, "HEAD"
        ], workingDirectory: workingDirectory)
        
        guard pushResult.exitCode == 0 else {
            throw GitError.pushFailed("Failed to push: \(pushResult.error)")
        }
        
        progressHandler(GitOperationProgress(phase: "Pushing", progress: 1.0, message: "Push completed successfully"))
    }
    
    // MARK: - Repository Initialization
    func initializeRepository() async throws {
        let initResult = try await executeGitCommand(["init"], workingDirectory: workingDirectory)
        guard initResult.exitCode == 0 else {
            throw GitError.commitFailed("Failed to initialize repository: \(initResult.error)")
        }
    }
    
    func addRemote(url: String, name: String = "origin") async throws {
        // Remove existing remote if it exists
        _ = try await executeGitCommand(["remote", "remove", name], workingDirectory: workingDirectory)
        
        // Add new remote
        let addResult = try await executeGitCommand(["remote", "add", name, url], workingDirectory: workingDirectory)
        guard addResult.exitCode == 0 else {
            throw GitError.commitFailed("Failed to add remote: \(addResult.error)")
        }
    }
    
    // MARK: - Utility Methods
    private func authenticatedURL(_ url: String, credentials: GitCredentials) -> String {
        // Convert HTTPS URL to include credentials
        if url.hasPrefix("https://github.com/") {
            let urlWithoutProtocol = String(url.dropFirst("https://".count))
            return "https://\(credentials.username):\(credentials.token)@\(urlWithoutProtocol)"
        }
        return url
    }
    
    private func executeGitCommand(_ arguments: [String], workingDirectory: URL) async throws -> GitCommandResult {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            do {
                try process.run()
                
                process.terminationHandler = { process in
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let error = String(data: errorData, encoding: .utf8) ?? ""
                    
                    let result = GitCommandResult(
                        exitCode: Int(process.terminationStatus),
                        output: output,
                        error: error
                    )
                    
                    continuation.resume(returning: result)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Git Command Result
struct GitCommandResult {
    let exitCode: Int
    let output: String
    let error: String
    
    var isSuccess: Bool {
        return exitCode == 0
    }
}
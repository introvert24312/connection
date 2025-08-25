import Foundation

// MARK: - Traced GitService Extensions

extension GitService {
    
    // MARK: - Traced Repository Configuration
    
    /// Configure repository with comprehensive tracing
    func configureRepositoryTraced(
        url: String,
        credentials: GitCredentials,
        context: TraceContext? = nil
    ) async throws {
        try await TracingService.shared.traced(
            "GitService.configureRepository",
            parentContext: context,
            tags: [
                "service": "GitService",
                "operation_type": "configure",
                "repository_url": url,
                "username": credentials.username
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            logger.info("Starting repository configuration", context: traceContext, fields: [
                "repository_url": url,
                "username": credentials.username
            ])
            
            connectionStatus = .connecting
            
            // Validate URL format with tracing
            let validationContext = TracingService.shared.startSpan(
                "GitService.validateURL",
                parentContext: traceContext,
                tags: ["validation_type": "url_format"]
            )
            
            guard isValidRepositoryURL(url) else {
                logger.error("Invalid repository URL format", context: validationContext, fields: [
                    "url": url
                ])
                connectionStatus = .error("Invalid repository URL format")
                TracingService.shared.finishSpan(validationContext, outcome: .error(GitError.invalidRepository))
                throw GitError.invalidRepository
            }
            
            TracingService.shared.finishSpan(validationContext, outcome: .success)
            logger.debug("URL format validation passed", context: traceContext)
            
            // Test repository accessibility with tracing
            let accessibilityContext = TracingService.shared.startSpan(
                "GitService.testAccessibility",
                parentContext: traceContext,
                tags: ["test_type": "repository_accessibility"]
            )
            
            do {
                logger.info("Testing repository accessibility", context: accessibilityContext)
                let isAccessible = try await validateRepository(url: url, credentials: credentials)
                
                guard isAccessible else {
                    logger.error("Repository is not accessible", context: accessibilityContext)
                    connectionStatus = .error("Unable to access repository")
                    TracingService.shared.finishSpan(accessibilityContext, outcome: .error(GitError.invalidRepository))
                    throw GitError.invalidRepository
                }
                
                TracingService.shared.finishSpan(accessibilityContext, outcome: .success)
                logger.info("Repository accessibility test passed", context: traceContext)
                
                // Store configuration with tracing
                let configContext = TracingService.shared.startSpan(
                    "GitService.storeConfiguration",
                    parentContext: traceContext,
                    tags: ["storage_type": "configuration_and_credentials"]
                )
                
                self.repositoryURL = url
                self.credentials = credentials
                
                let config = GitConfiguration(
                    repositoryURL: url,
                    username: credentials.username,
                    lastSyncDate: lastSyncDate,
                    autoSync: false
                )
                self.configuration = config
                
                try saveConfiguration(config)
                try keychainManager.saveGitCredentials(credentials, for: url)
                
                TracingService.shared.finishSpan(configContext, outcome: .success)
                logger.info("Configuration and credentials stored successfully", context: traceContext)
                
                connectionStatus = .connected
                logger.info("Repository configuration completed successfully", context: traceContext)
                
            } catch {
                logger.error("Repository configuration failed", context: accessibilityContext, fields: [
                    "error": error.localizedDescription
                ])
                connectionStatus = .error(error.localizedDescription)
                TracingService.shared.finishSpan(accessibilityContext, outcome: .error(error))
                throw error
            }
        }
    }
    
    // MARK: - Traced Git Operations with Retry Logic
    
    /// Commit changes with comprehensive tracing and retry correlation
    func commitChangesTraced(message: String, context: TraceContext? = nil) async throws {
        try await performOperationWithRetryTraced(
            operationName: "GitService.commitChanges",
            parentContext: context,
            tags: [
                "service": "GitService",
                "operation_type": "commit",
                "commit_message": message
            ]
        ) { traceContext in
            try await performCommitOperationTraced(message: message, context: traceContext)
        }
    }
    
    private func performCommitOperationTraced(message: String, context: TraceContext) async throws {
        let logger = StructuredLogger.shared
        
        guard connectionStatus == .connected else {
            logger.error("Cannot commit: not connected to repository", context: context)
            throw GitError.notConnected
        }
        
        guard let repoURL = repositoryURL,
              let creds = credentials else {
            logger.error("Cannot commit: missing repository URL or credentials", context: context)
            throw GitError.notConnected
        }
        
        logger.info("Starting commit operation", context: context, fields: [
            "repository_url": repoURL,
            "username": creds.username,
            "commit_message": message
        ])
        
        isOperationInProgress = true
        operationProgress = nil
        
        defer {
            isOperationInProgress = false
            operationProgress = nil
        }
        
        do {
            try await performCommit(repositoryURL: repoURL, credentials: creds, message: message)
            
            // Refresh repository status with tracing
            let statusContext = TracingService.shared.startSpan(
                "GitService.refreshStatus",
                parentContext: context,
                tags: ["status_type": "post_commit"]
            )
            
            await refreshRepositoryStatus()
            TracingService.shared.finishSpan(statusContext, outcome: .success)
            
            // Reset retry state on success
            resetRetryState()
            
            logger.info("Commit operation completed successfully", context: context)
            
        } catch {
            let gitError = mapToGitError(error)
            lastError = gitError
            
            logger.error("Commit operation failed", context: context, fields: [
                "error_type": String(describing: type(of: gitError)),
                "error_message": gitError.localizedDescription,
                "is_retryable": String(gitError.isRetryable)
            ])
            
            throw gitError
        }
    }
    
    /// Push to remote with comprehensive tracing and retry correlation
    func pushToRemoteTraced(context: TraceContext? = nil) async throws {
        try await performOperationWithRetryTraced(
            operationName: "GitService.pushToRemote",
            parentContext: context,
            tags: [
                "service": "GitService",
                "operation_type": "push"
            ]
        ) { traceContext in
            try await performPushOperationTraced(context: traceContext)
        }
    }
    
    private func performPushOperationTraced(context: TraceContext) async throws {
        let logger = StructuredLogger.shared
        
        guard connectionStatus == .connected else {
            logger.error("Cannot push: not connected to repository", context: context)
            throw GitError.notConnected
        }
        
        guard let repoURL = repositoryURL,
              let creds = credentials else {
            logger.error("Cannot push: missing repository URL or credentials", context: context)
            throw GitError.notConnected
        }
        
        logger.info("Starting push operation", context: context, fields: [
            "repository_url": repoURL,
            "username": creds.username
        ])
        
        isOperationInProgress = true
        operationProgress = nil
        
        defer {
            isOperationInProgress = false
            operationProgress = nil
        }
        
        do {
            try await performPush(repositoryURL: repoURL, credentials: creds)
            
            let newSyncDate = Date()
            lastSyncDate = newSyncDate
            
            logger.info("Push operation completed successfully", context: context, fields: [
                "sync_date": DateFormatter.iso8601WithMilliseconds.string(from: newSyncDate)
            ])
            
            // Update configuration with new sync date
            if var config = configuration {
                let configContext = TracingService.shared.startSpan(
                    "GitService.updateSyncDate",
                    parentContext: context,
                    tags: ["update_type": "last_sync_date"]
                )
                
                config = GitConfiguration(
                    repositoryURL: config.repositoryURL,
                    username: config.username,
                    lastSyncDate: lastSyncDate,
                    autoSync: config.autoSync
                )
                self.configuration = config
                try saveConfiguration(config)
                
                TracingService.shared.finishSpan(configContext, outcome: .success)
                logger.debug("Configuration updated with new sync date", context: context)
            }
            
            // Refresh repository status with tracing
            let statusContext = TracingService.shared.startSpan(
                "GitService.refreshStatus",
                parentContext: context,
                tags: ["status_type": "post_push"]
            )
            
            await refreshRepositoryStatus()
            TracingService.shared.finishSpan(statusContext, outcome: .success)
            
            // Reset retry state on success
            resetRetryState()
            
        } catch {
            let gitError = mapToGitError(error)
            lastError = gitError
            
            logger.error("Push operation failed", context: context, fields: [
                "error_type": String(describing: type(of: gitError)),
                "error_message": gitError.localizedDescription,
                "is_retryable": String(gitError.isRetryable)
            ])
            
            throw gitError
        }
    }
    
    // MARK: - Enhanced Retry Logic with Tracing
    
    private func performOperationWithRetryTraced<T>(
        operationName: String,
        parentContext: TraceContext? = nil,
        tags: [String: String] = [:],
        operation: @escaping (TraceContext) async throws -> T
    ) async throws -> T {
        
        return try await TracingService.shared.traced(
            operationName,
            parentContext: parentContext,
            tags: tags.merging([
                "retry_enabled": "true",
                "max_attempts": String(maxRetryAttempts)
            ]) { _, new in new }
        ) { mainContext in
            
            let logger = StructuredLogger.shared
            var lastError: Error?
            
            logger.info("Starting operation with retry logic", context: mainContext, fields: [
                "max_attempts": String(maxRetryAttempts),
                "base_delay": String(baseRetryDelay)
            ])
            
            for attempt in 0..<maxRetryAttempts {
                let attemptContext = TracingService.shared.startSpan(
                    "\(operationName).attempt",
                    parentContext: mainContext,
                    tags: [
                        "attempt_number": String(attempt + 1),
                        "is_retry": String(attempt > 0)
                    ]
                )
                
                do {
                    retryCount = attempt
                    
                    if attempt > 0 {
                        isRetrying = true
                        let delay = calculateRetryDelay(attempt: attempt)
                        
                        logger.info("Retrying operation after delay", context: attemptContext, fields: [
                            "attempt": String(attempt + 1),
                            "delay_seconds": String(format: "%.2f", delay),
                            "previous_error": lastError?.localizedDescription ?? "unknown"
                        ])
                        
                        // Sleep with trace context
                        let sleepContext = TracingService.shared.startSpan(
                            "GitService.retryDelay",
                            parentContext: attemptContext,
                            tags: [
                                "delay_seconds": String(format: "%.2f", delay),
                                "delay_type": "exponential_backoff"
                            ]
                        )
                        
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        TracingService.shared.finishSpan(sleepContext, outcome: .success)
                    }
                    
                    logger.debug("Executing operation attempt", context: attemptContext, fields: [
                        "attempt": String(attempt + 1)
                    ])
                    
                    let result = try await operation(attemptContext)
                    
                    // Success - reset retry state and record metrics
                    resetRetryState()
                    
                    TracingService.shared.finishSpan(attemptContext, outcome: .success, metrics: [
                        "total_attempts": Double(attempt + 1),
                        "success": 1.0
                    ])
                    
                    logger.info("Operation succeeded", context: mainContext, fields: [
                        "total_attempts": String(attempt + 1),
                        "success_on_retry": String(attempt > 0)
                    ])
                    
                    return result
                    
                } catch {
                    lastError = error
                    let gitError = mapToGitError(error)
                    
                    logger.warn("Operation attempt failed", context: attemptContext, fields: [
                        "attempt": String(attempt + 1),
                        "error_type": String(describing: type(of: gitError)),
                        "error_message": gitError.localizedDescription,
                        "is_retryable": String(gitError.isRetryable)
                    ])
                    
                    TracingService.shared.finishSpan(attemptContext, outcome: .error(gitError), metrics: [
                        "attempt_number": Double(attempt + 1),
                        "is_retryable": gitError.isRetryable ? 1.0 : 0.0
                    ])
                    
                    // Don't retry if error is not retryable
                    if !gitError.isRetryable {
                        resetRetryState()
                        
                        logger.error("Operation failed with non-retryable error", context: mainContext, fields: [
                            "final_error": gitError.localizedDescription,
                            "total_attempts": String(attempt + 1)
                        ])
                        
                        throw gitError
                    }
                    
                    // Don't retry on last attempt
                    if attempt == maxRetryAttempts - 1 {
                        resetRetryState()
                        
                        logger.error("Operation failed after all retry attempts", context: mainContext, fields: [
                            "final_error": gitError.localizedDescription,
                            "total_attempts": String(maxRetryAttempts)
                        ])
                        
                        throw gitError
                    }
                }
            }
            
            resetRetryState()
            throw lastError ?? GitError.networkError(underlying: nil)
        }
    }
    
    // MARK: - Traced Credential Management
    
    /// Refresh credentials with tracing
    func refreshCredentialsTraced(_ newCredentials: GitCredentials, context: TraceContext? = nil) async throws {
        try await TracingService.shared.traced(
            "GitService.refreshCredentials",
            parentContext: context,
            tags: [
                "service": "GitService",
                "operation_type": "credential_refresh",
                "username": newCredentials.username
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            guard let repoURL = repositoryURL else {
                logger.error("Cannot refresh credentials: no repository URL", context: traceContext)
                throw GitError.notConnected
            }
            
            logger.info("Starting credential refresh", context: traceContext, fields: [
                "repository_url": repoURL,
                "new_username": newCredentials.username
            ])
            
            connectionStatus = .connecting
            
            // Test new credentials with tracing
            let validationContext = TracingService.shared.startSpan(
                "GitService.validateNewCredentials",
                parentContext: traceContext,
                tags: ["validation_type": "new_credentials"]
            )
            
            do {
                let isValid = try await validateRepository(url: repoURL, credentials: newCredentials)
                guard isValid else {
                    logger.error("New credentials are invalid", context: validationContext)
                    connectionStatus = .error("Invalid credentials")
                    TracingService.shared.finishSpan(validationContext, outcome: .error(GitError.authenticationFailed))
                    throw GitError.authenticationFailed
                }
                
                TracingService.shared.finishSpan(validationContext, outcome: .success)
                logger.info("New credentials validated successfully", context: traceContext)
                
                // Store new credentials with tracing
                let storageContext = TracingService.shared.startSpan(
                    "GitService.storeNewCredentials",
                    parentContext: traceContext,
                    tags: ["storage_type": "keychain_update"]
                )
                
                try keychainManager.saveGitCredentials(newCredentials, for: repoURL)
                self.credentials = newCredentials
                connectionStatus = .connected
                
                TracingService.shared.finishSpan(storageContext, outcome: .success)
                logger.info("Credentials refreshed successfully", context: traceContext)
                
            } catch {
                logger.error("Credential refresh failed", context: traceContext, fields: [
                    "error": error.localizedDescription
                ])
                connectionStatus = .error(error.localizedDescription)
                throw error
            }
        }
    }
    
    // MARK: - Traced Repository Status Management
    
    /// Refresh repository status with tracing
    func refreshRepositoryStatusTraced(context: TraceContext? = nil) async {
        await TracingService.shared.traced(
            "GitService.refreshRepositoryStatus",
            parentContext: context,
            tags: [
                "service": "GitService",
                "operation_type": "status_check"
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            guard let operations = gitOperations else {
                logger.warn("No git operations available for status check", context: traceContext)
                repositoryStatus = GitRepositoryStatus()
                pendingChanges = 0
                return
            }
            
            logger.debug("Checking repository status", context: traceContext)
            
            do {
                let status = try await operations.getRepositoryStatus()
                repositoryStatus = status
                pendingChanges = status.uncommittedFiles.count
                
                logger.info("Repository status updated", context: traceContext, fields: [
                    "uncommitted_files": String(status.uncommittedFiles.count),
                    "untracked_files": String(status.untrackedFiles.count),
                    "pending_changes": String(pendingChanges)
                ])
                
            } catch {
                logger.error("Failed to get repository status", context: traceContext, fields: [
                    "error": error.localizedDescription
                ])
                repositoryStatus = GitRepositoryStatus()
                pendingChanges = 0
            }
        }
    }
    
    // MARK: - Traced Error Handling
    
    /// Handle authentication error with tracing
    func handleAuthenticationErrorTraced(context: TraceContext? = nil) async throws {
        await TracingService.shared.traced(
            "GitService.handleAuthenticationError",
            parentContext: context,
            tags: [
                "service": "GitService",
                "operation_type": "auth_error_handling"
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            logger.warn("Handling authentication error", context: traceContext, fields: [
                "repository_url": repositoryURL ?? "none"
            ])
            
            // Clear current credentials to force re-authentication
            credentials = nil
            connectionStatus = .error("Authentication required")
            
            logger.info("Cleared credentials, requesting re-authentication", context: traceContext)
            
            // Notify UI to show credential input dialog
            NotificationCenter.default.post(
                name: .gitAuthenticationRequired,
                object: self,
                userInfo: ["repositoryURL": repositoryURL ?? ""],
                context: traceContext
            )
            
            logger.debug("Posted authentication required notification", context: traceContext)
        }
    }
    
    // MARK: - Traced Repository Management
    
    /// Initialize local repository with tracing
    func initializeLocalRepositoryTraced(context: TraceContext? = nil) async throws {
        try await TracingService.shared.traced(
            "GitService.initializeRepository",
            parentContext: context,
            tags: [
                "service": "GitService",
                "operation_type": "init_repository"
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            guard let operations = gitOperations else {
                logger.error("Cannot initialize repository: no git operations available", context: traceContext)
                throw GitError.notConnected
            }
            
            logger.info("Initializing local repository", context: traceContext)
            
            try await operations.initializeRepository()
            
            logger.info("Repository initialized successfully", context: traceContext)
            
            // Refresh status after initialization
            let statusContext = TracingService.shared.startSpan(
                "GitService.refreshStatus",
                parentContext: traceContext,
                tags: ["status_type": "post_init"]
            )
            
            await refreshRepositoryStatus()
            TracingService.shared.finishSpan(statusContext, outcome: .success)
        }
    }
    
    /// Add remote repository with tracing
    func addRemoteRepositoryTraced(url: String, name: String = "origin", context: TraceContext? = nil) async throws {
        try await TracingService.shared.traced(
            "GitService.addRemote",
            parentContext: context,
            tags: [
                "service": "GitService",
                "operation_type": "add_remote",
                "remote_url": url,
                "remote_name": name
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            guard let operations = gitOperations else {
                logger.error("Cannot add remote: no git operations available", context: traceContext)
                throw GitError.notConnected
            }
            
            logger.info("Adding remote repository", context: traceContext, fields: [
                "remote_name": name,
                "remote_url": url
            ])
            
            try await operations.addRemote(url: url, name: name)
            
            logger.info("Remote repository added successfully", context: traceContext)
        }
    }
    
    // MARK: - Traced Credential Validation
    
    /// Validate stored credentials with tracing
    func validateStoredCredentialsTraced(
        for repositoryURL: String,
        username: String,
        context: TraceContext? = nil
    ) async throws -> Bool {
        return try await TracingService.shared.traced(
            "GitService.validateStoredCredentials",
            parentContext: context,
            tags: [
                "service": "GitService",
                "operation_type": "credential_validation",
                "repository_url": repositoryURL,
                "username": username
            ]
        ) { traceContext in
            
            let logger = StructuredLogger.shared
            
            logger.info("Validating stored credentials", context: traceContext, fields: [
                "repository_url": repositoryURL,
                "username": username
            ])
            
            // Load credentials from keychain with tracing
            let loadContext = TracingService.shared.startSpan(
                "GitService.loadStoredCredentials",
                parentContext: traceContext,
                tags: ["source": "keychain"]
            )
            
            guard let storedCredentials = try? keychainManager.loadGitCredentials(for: repositoryURL, username: username),
                  storedCredentials.username == username else {
                logger.error("Stored credentials not found", context: loadContext)
                TracingService.shared.finishSpan(loadContext, outcome: .error(GitError.credentialRetrievalFailed))
                throw GitError.credentialRetrievalFailed
            }
            
            TracingService.shared.finishSpan(loadContext, outcome: .success)
            logger.debug("Stored credentials loaded successfully", context: traceContext)
            
            // Validate credentials against repository
            let validationContext = TracingService.shared.startSpan(
                "GitService.validateCredentialsAgainstRepo",
                parentContext: traceContext,
                tags: ["validation_type": "repository_access"]
            )
            
            do {
                let isValid = try await validateRepository(url: repositoryURL, credentials: storedCredentials)
                
                TracingService.shared.finishSpan(validationContext, outcome: .success, metrics: [
                    "validation_result": isValid ? 1.0 : 0.0
                ])
                
                logger.info("Credential validation completed", context: traceContext, fields: [
                    "is_valid": String(isValid)
                ])
                
                return isValid
                
            } catch {
                TracingService.shared.finishSpan(validationContext, outcome: .error(error))
                logger.error("Credential validation failed", context: traceContext, fields: [
                    "error": error.localizedDescription
                ])
                throw GitError.authenticationFailed
            }
        }
    }
}
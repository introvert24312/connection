import SwiftUI

struct GitCredentialsSheet: View {
    let repositoryURL: String
    @Binding var username: String
    @Binding var token: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void
    
    @State private var localUsername: String = ""
    @State private var localToken: String = ""
    @State private var showToken: Bool = false
    @State private var isValidating: Bool = false
    @State private var validationResult: ValidationResult?
    @State private var showingValidationAlert = false
    @State private var hasLoadedStoredCredentials = false
    
    enum ValidationResult {
        case success
        case failure(String)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                HStack {
                    Text("Git Credentials")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                }
                
                // Repository info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repository")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(repositoryURL)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider()
            
            // Form content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Username field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("Enter your Git username", text: $localUsername)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                        
                        Text("Your Git username or email address")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Token field
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Personal Access Token")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Button(action: {
                                showToken.toggle()
                            }) {
                                Image(systemName: showToken ? "eye.slash" : "eye")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(showToken ? "Hide token" : "Show token")
                        }
                        
                        Group {
                            if showToken {
                                TextField("Enter your personal access token", text: $localToken)
                            } else {
                                SecureField("Enter your personal access token", text: $localToken)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Generate a personal access token from your Git provider:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if repositoryURL.contains("github.com") {
                                Link("GitHub Token Settings", destination: URL(string: "https://github.com/settings/tokens")!)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            } else if repositoryURL.contains("gitlab.com") {
                                Link("GitLab Token Settings", destination: URL(string: "https://gitlab.com/-/profile/personal_access_tokens")!)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            
                            Text("Required permissions: repo (full control of private repositories)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.top, 2)
                        }
                    }
                    
                    // Stored credentials section
                    if hasLoadedStoredCredentials {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Stored Credentials")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            StoredCredentialsView(
                                repositoryURL: repositoryURL,
                                onCredentialSelected: { credentials in
                                    localUsername = credentials.username
                                    localToken = credentials.token
                                }
                            )
                        }
                    }
                    
                    // Validation section
                    if let result = validationResult {
                        VStack(alignment: .leading, spacing: 8) {
                            switch result {
                            case .success:
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Credentials validated successfully")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                                
                            case .failure(let message):
                                HStack(alignment: .top) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Validation failed")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.red)
                                        Text(message)
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            
            Divider()
            
            // Footer with action buttons
            HStack(spacing: 12) {
                Button("Test Credentials") {
                    Task {
                        await validateCredentials()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(localUsername.isEmpty || localToken.isEmpty || isValidating)
                
                if isValidating {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Validating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Save") {
                    saveCredentials()
                }
                .buttonStyle(.borderedProminent)
                .disabled(localUsername.isEmpty || localToken.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadInitialValues()
            loadStoredCredentials()
        }
        .alert("Validation Result", isPresented: $showingValidationAlert) {
            Button("OK") { }
        } message: {
            if case .failure(let message) = validationResult {
                Text(message)
            } else {
                Text("Credentials are valid and can access the repository.")
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadInitialValues() {
        localUsername = username
        localToken = token
    }
    
    private func loadStoredCredentials() {
        hasLoadedStoredCredentials = true
    }
    
    private func validateCredentials() async {
        guard !localUsername.isEmpty, !localToken.isEmpty else { return }
        
        isValidating = true
        validationResult = nil
        
        do {
            let credentials = GitCredentials(username: localUsername, token: localToken)
            let gitService = GitService()
            let isValid = try await gitService.validateCredentials(credentials, for: repositoryURL)
            
            if isValid {
                validationResult = .success
            } else {
                validationResult = .failure("Unable to access repository with provided credentials")
            }
        } catch {
            validationResult = .failure(error.localizedDescription)
        }
        
        isValidating = false
        showingValidationAlert = true
    }
    
    private func saveCredentials() {
        // Save to keychain through GitService
        do {
            let credentials = GitCredentials(username: localUsername, token: localToken)
            let keychainManager = KeychainManager.shared
            try keychainManager.saveGitCredentials(credentials, for: repositoryURL)
            
            // Call the completion handler
            onSave(localUsername, localToken)
        } catch {
            validationResult = .failure("Failed to save credentials: \(error.localizedDescription)")
            showingValidationAlert = true
        }
    }
}

// MARK: - Stored Credentials View

struct StoredCredentialsView: View {
    let repositoryURL: String
    let onCredentialSelected: (GitCredentials) -> Void
    
    @State private var storedCredentials: [GitCredentials] = []
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading stored credentials...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if storedCredentials.isEmpty {
                Text("No stored credentials found for this repository")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(storedCredentials.indices, id: \.self) { index in
                    let credential = storedCredentials[index]
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(credential.username)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Stored credential")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Use") {
                            onCredentialSelected(credential)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button(action: {
                            deleteCredential(at: index)
                        }) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
        }
        .onAppear {
            loadStoredCredentials()
        }
    }
    
    private func loadStoredCredentials() {
        isLoading = true
        
        do {
            let keychainManager = KeychainManager.shared
            storedCredentials = try keychainManager.loadAllGitCredentials(for: repositoryURL)
        } catch {
            storedCredentials = []
        }
        
        isLoading = false
    }
    
    private func deleteCredential(at index: Int) {
        guard index < storedCredentials.count else { return }
        
        let credential = storedCredentials[index]
        
        do {
            let keychainManager = KeychainManager.shared
            try keychainManager.deleteGitCredentials(for: repositoryURL, username: credential.username)
            storedCredentials.remove(at: index)
        } catch {
            // Handle error - could show an alert
            print("Failed to delete credential: \(error)")
        }
    }
}

// MARK: - Preview

struct GitCredentialsSheet_Previews: PreviewProvider {
    static var previews: some View {
        GitCredentialsSheet(
            repositoryURL: "https://github.com/user/repo.git",
            username: .constant(""),
            token: .constant(""),
            onSave: { _, _ in },
            onCancel: { }
        )
    }
}
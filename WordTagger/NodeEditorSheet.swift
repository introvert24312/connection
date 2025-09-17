import SwiftUI

struct NodeEditorSheet: View {
    @Binding var node: Node
    let onSave: (Node) -> Void
    let onCancel: () -> Void
    
    @State private var editedText: String = ""
    @State private var editedCommand: String = ""
    @State private var editedPhonetic: String = ""
    @State private var editedMeaning: String = ""
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isSaving: Bool = false
    
    // Enhanced error handling states
    @State private var saveAttempts: Int = 0
    @State private var maxRetryAttempts: Int = 3
    @State private var showingRetryDialog: Bool = false
    @State private var showingConflictDialog: Bool = false
    @State private var conflictingNode: Node?
    @State private var originalNodeSnapshot: Node?
    @State private var hasUnsavedChanges: Bool = false
    @State private var validationErrors: [ValidationError] = []
    @State private var showingValidationAlert: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Node")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        handleCancel()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape)
                    
                    Button("Save") {
                        handleSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!isFormValid || isSaving)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Node Name Section
                    GroupBox("Node Information") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Node Name")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                
                                TextField("Enter node name", text: $editedText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body)
                                    .onChange(of: editedText) {
                                        hasUnsavedChanges = hasChanges()
                                    }
                                
                                if editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Node name is required")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Phonetic (Optional)")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                
                                TextField("Enter phonetic notation", text: $editedPhonetic)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body)
                                    .onChange(of: editedPhonetic) {
                                        hasUnsavedChanges = hasChanges()
                                    }
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Meaning (Optional)")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                
                                TextField("Enter meaning or description", text: $editedMeaning, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body)
                                    .lineLimit(3...6)
                                    .onChange(of: editedMeaning) {
                                        hasUnsavedChanges = hasChanges()
                                    }
                            }
                        }
                        .padding(12)
                    }
                    
                    // Command Label Section
                    GroupBox("Command Configuration") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Command Label")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                
                                TextField("Enter command or action", text: $editedCommand, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body)
                                    .lineLimit(2...4)
                                    .onChange(of: editedCommand) {
                                        hasUnsavedChanges = hasChanges()
                                    }
                                
                                Text("This command will be associated with the node for quick access")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                    }
                    
                    // Preview Section
                    if !editedText.isEmpty {
                        GroupBox("Preview") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Node:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(editedText)
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                                
                                if !editedPhonetic.isEmpty {
                                    HStack {
                                        Text("Phonetic:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(editedPhonetic)
                                            .font(.body)
                                            .foregroundColor(.blue)
                                    }
                                }
                                
                                if !editedMeaning.isEmpty {
                                    HStack(alignment: .top) {
                                        Text("Meaning:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(editedMeaning)
                                            .font(.body)
                                            .foregroundColor(.green)
                                    }
                                }
                                
                                if !editedCommand.isEmpty {
                                    HStack(alignment: .top) {
                                        Text("Command:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(editedCommand)
                                            .font(.body)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            .padding(12)
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadNodeData()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                showingError = false
            }
        } message: {
            Text(errorMessage)
        }
        .alert("Validation Errors", isPresented: $showingValidationAlert) {
            Button("OK") {
                showingValidationAlert = false
            }
        } message: {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(validationErrors, id: \.field) { error in
                    Text("• \(error.message)")
                }
            }
        }
        .alert("Save Failed", isPresented: $showingRetryDialog) {
            Button("Retry") {
                showingRetryDialog = false
                attemptSave()
            }
            Button("Cancel") {
                showingRetryDialog = false
                saveAttempts = 0
            }
        } message: {
            Text("Failed to save after \(saveAttempts) attempt(s). Would you like to retry? (\(maxRetryAttempts - saveAttempts) attempts remaining)")
        }
        .alert("Conflict Detected", isPresented: $showingConflictDialog) {
            Button("Use My Changes") {
                showingConflictDialog = false
                // Force save with current changes
                node.updatedAt = Date()
                attemptSave()
            }
            Button("Reload and Discard") {
                showingConflictDialog = false
                // Reload the node data and discard changes
                if let conflicting = conflictingNode {
                    node = conflicting
                    loadNodeData()
                }
            }
            Button("Cancel") {
                showingConflictDialog = false
            }
        } message: {
            Text("This node has been modified by another process. Choose how to resolve the conflict.")
        }
        .overlay(
            Group {
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Saving...")
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .shadow(radius: 8)
                        )
                    }
                }
            }
        )
    }
    
    // MARK: - Computed Properties
    
    private var isFormValid: Bool {
        !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Methods
    
    private func loadNodeData() {
        editedText = node.text
        editedPhonetic = node.phonetic ?? ""
        editedMeaning = node.meaning ?? ""
        editedCommand = node.commandLabel ?? ""
        
        // Create snapshot for conflict detection
        originalNodeSnapshot = node
        hasUnsavedChanges = false
        
        // Setup change tracking
        setupChangeTracking()
    }
    
    private func setupChangeTracking() {
        // Monitor changes to detect unsaved modifications
        DispatchQueue.main.async {
            self.hasUnsavedChanges = self.hasChanges()
        }
    }
    
    private func hasChanges() -> Bool {
        guard let original = originalNodeSnapshot else { return false }
        
        return editedText != original.text ||
               editedPhonetic != (original.phonetic ?? "") ||
               editedMeaning != (original.meaning ?? "") ||
               editedCommand != (original.commandLabel ?? "")
    }
    
    private func handleSave() {
        // Perform comprehensive validation first
        let errors = performComprehensiveValidation()
        if !errors.isEmpty {
            validationErrors = errors
            showingValidationAlert = true
            return
        }
        
        guard !isSaving else { return }
        
        // Check for concurrent modifications
        if let original = originalNodeSnapshot, hasNodeBeenModifiedExternally(original) {
            detectAndHandleConflict()
            return
        }
        
        attemptSave()
    }
    
    private func attemptSave() {
        isSaving = true
        saveAttempts += 1
        
        // Create updated node
        var updatedNode = node
        updatedNode.text = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedNode.phonetic = editedPhonetic.isEmpty ? nil : editedPhonetic.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedNode.meaning = editedMeaning.isEmpty ? nil : editedMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedNode.updatedAt = Date()
        
        // Update command label in markdown
        updatedNode.commandLabel = editedCommand.isEmpty ? nil : editedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Perform save operation on background queue for better performance
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Validate the updated node
                try self.validateNode(updatedNode)
                
                // Simulate potential save failures for testing retry mechanism
                if self.shouldSimulateSaveFailure() {
                    throw NodeSaveError.networkTimeout
                }
                
                // Simulate save delay
                Thread.sleep(forTimeInterval: 0.1)
                
                DispatchQueue.main.async {
                    // Call the save callback
                    self.onSave(updatedNode)
                    
                    // Reset state on successful save
                    self.saveAttempts = 0
                    self.hasUnsavedChanges = false
                    self.isSaving = false
                    self.dismiss()
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.handleSaveError(error)
                }
            }
        }
    }
    
    private func handleSaveError(_ error: Error) {
        if saveAttempts < maxRetryAttempts && isRetryableError(error) {
            // Show retry dialog for retryable errors
            showingRetryDialog = true
        } else {
            // Show final error for non-retryable errors or max attempts reached
            let errorMessage = generateUserFriendlyErrorMessage(error)
            showError(errorMessage)
            saveAttempts = 0 // Reset for next attempt
        }
    }
    
    private func isRetryableError(_ error: Error) -> Bool {
        if let nodeError = error as? NodeSaveError {
            switch nodeError {
            case .networkTimeout, .temporaryUnavailable, .concurrentModification:
                return true
            case .validationFailed, .permissionDenied, .invalidData:
                return false
            }
        }
        return false
    }
    
    private func shouldSimulateSaveFailure() -> Bool {
        // Simulate failure for testing (remove in production)
        #if DEBUG
        return saveAttempts == 1 && Int.random(in: 1...10) <= 2 // 20% chance
        #else
        return false
        #endif
    }
    
    private func generateUserFriendlyErrorMessage(_ error: Error) -> String {
        if let nodeError = error as? NodeSaveError {
            switch nodeError {
            case .networkTimeout:
                return "Save failed due to network timeout. Please check your connection and try again."
            case .temporaryUnavailable:
                return "Service is temporarily unavailable. Please try again in a moment."
            case .concurrentModification:
                return "This node was modified by another process. Please review the changes and try again."
            case .validationFailed(let details):
                return "Validation failed: \(details)"
            case .permissionDenied:
                return "You don't have permission to modify this node."
            case .invalidData:
                return "The node data is invalid. Please check your input and try again."
            }
        } else if let validationError = error as? NodeValidationError {
            return validationError.localizedDescription
        }
        
        return "Failed to save node: \(error.localizedDescription)"
    }
    
    private func handleCancel() {
        if hasChanges() {
            // Show confirmation dialog for unsaved changes
            showUnsavedChangesDialog()
        } else {
            onCancel()
            dismiss()
        }
    }
    
    private func showUnsavedChangesDialog() {
        let alert = NSAlert()
        alert.messageText = "Unsaved Changes"
        alert.informativeText = "You have unsaved changes. Do you want to save them before closing?"
        alert.alertStyle = .warning
        
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn: // Save
            handleSave()
        case .alertSecondButtonReturn: // Don't Save
            onCancel()
            dismiss()
        case .alertThirdButtonReturn: // Cancel
            break // Do nothing, stay in editor
        default:
            break
        }
    }
    
    private func validateNode(_ node: Node) throws {
        guard !node.text.isEmpty else {
            throw NodeValidationError.emptyName
        }
        
        guard node.text.count <= 200 else {
            throw NodeValidationError.nameTooLong
        }
        
        if let phonetic = node.phonetic, phonetic.count > 100 {
            throw NodeValidationError.phoneticTooLong
        }
        
        if let meaning = node.meaning, meaning.count > 500 {
            throw NodeValidationError.meaningTooLong
        }
        
        if let command = node.commandLabel, command.count > 300 {
            throw NodeValidationError.commandTooLong
        }
    }
    
    private func performComprehensiveValidation() -> [ValidationError] {
        var errors: [ValidationError] = []
        
        // Text validation
        let trimmedText = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            errors.append(ValidationError(field: "text", message: "Node name is required"))
        } else if trimmedText.count > 200 {
            errors.append(ValidationError(field: "text", message: "Node name cannot exceed 200 characters"))
        } else if trimmedText.count < 2 {
            errors.append(ValidationError(field: "text", message: "Node name must be at least 2 characters"))
        }
        
        // Check for invalid characters
        let invalidChars = CharacterSet.alphanumerics.union(.whitespaces).union(.punctuationCharacters).inverted
        if trimmedText.rangeOfCharacter(from: invalidChars) != nil {
            errors.append(ValidationError(field: "text", message: "Node name contains invalid characters"))
        }
        
        // Phonetic validation
        if !editedPhonetic.isEmpty {
            if editedPhonetic.count > 100 {
                errors.append(ValidationError(field: "phonetic", message: "Phonetic notation cannot exceed 100 characters"))
            }
        }
        
        // Meaning validation
        if !editedMeaning.isEmpty {
            if editedMeaning.count > 500 {
                errors.append(ValidationError(field: "meaning", message: "Meaning cannot exceed 500 characters"))
            }
        }
        
        // Command validation
        if !editedCommand.isEmpty {
            if editedCommand.count > 300 {
                errors.append(ValidationError(field: "command", message: "Command cannot exceed 300 characters"))
            }
            
            // Validate command syntax if it contains markdown
            let commandValidation = MarkdownCommandValidator.validateCommandSyntax(in: editedCommand)
            if case .error(let message) = commandValidation {
                errors.append(ValidationError(field: "command", message: "Command syntax error: \(message)"))
            }
        }
        
        return errors
    }
    
    private func hasNodeBeenModifiedExternally(_ original: Node) -> Bool {
        // In a real implementation, this would check if the node has been modified
        // by another user or process since we started editing
        // For now, we'll simulate this check
        
        // Check if the node's updatedAt timestamp is newer than when we started editing
        return node.updatedAt > original.updatedAt
    }
    
    private func detectAndHandleConflict() {
        // Store the conflicting node for resolution
        conflictingNode = node
        showingConflictDialog = true
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Validation Errors

enum NodeValidationError: LocalizedError {
    case emptyName
    case nameTooLong
    case phoneticTooLong
    case meaningTooLong
    case commandTooLong
    
    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Node name cannot be empty"
        case .nameTooLong:
            return "Node name cannot exceed 200 characters"
        case .phoneticTooLong:
            return "Phonetic notation cannot exceed 100 characters"
        case .meaningTooLong:
            return "Meaning cannot exceed 500 characters"
        case .commandTooLong:
            return "Command cannot exceed 300 characters"
        }
    }
}

// MARK: - Save Errors

enum NodeSaveError: LocalizedError {
    case networkTimeout
    case temporaryUnavailable
    case concurrentModification
    case validationFailed(String)
    case permissionDenied
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .networkTimeout:
            return "Network timeout occurred while saving"
        case .temporaryUnavailable:
            return "Service is temporarily unavailable"
        case .concurrentModification:
            return "Node was modified by another process"
        case .validationFailed(let details):
            return "Validation failed: \(details)"
        case .permissionDenied:
            return "Permission denied"
        case .invalidData:
            return "Invalid node data"
        }
    }
}

// MARK: - Validation Error Structure

struct ValidationError {
    let field: String
    let message: String
}

// MARK: - Preview

#Preview {
    @Previewable @State var sampleNode = Node(
        text: "Sample Node",
        phonetic: "sample",
        meaning: "A test node for preview",
        layerId: UUID(),
        tags: [],
        isCompound: false,
        markdown: "# Sample Node\nThis is a test node."
    )
    
    NodeEditorSheet(
        node: $sampleNode,
        onSave: { node in
            print("Saved node: \(node.text)")
        },
        onCancel: {
            print("Cancelled editing")
        }
    )
}
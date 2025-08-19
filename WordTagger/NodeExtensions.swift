import Foundation

// MARK: - Node Command Label Extension

extension Node {
    /// Computed property to get/set command label from markdown content
    var commandLabel: String? {
        get {
            return extractCommandFromMarkdown()
        }
        set {
            updateCommandInMarkdown(newValue)
        }
    }
    
    // MARK: - Private Methods
    
    /// Extracts command information from markdown content
    private func extractCommandFromMarkdown() -> String? {
        guard !markdown.isEmpty else { return nil }
        
        // Look for command patterns in markdown:
        // 1. <!-- command: [command text] -->
        // 2. Command: [command text]
        // 3. @command [command text]
        
        let patterns = [
            #"<!--\s*command:\s*(.+?)\s*-->"#,  // HTML comment style
            #"^Command:\s*(.+)$"#,              // Command: style
            #"^@command\s+(.+)$"#               // @command style
        ]
        
        for pattern in patterns {
            if let command = extractUsingPattern(pattern, from: markdown) {
                return command.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return nil
    }
    
    /// Updates the markdown content with the new command
    private mutating func updateCommandInMarkdown(_ command: String?) {
        let commandPattern = #"<!--\s*command:\s*(.+?)\s*-->"#
        
        if let command = command, !command.isEmpty {
            let commandComment = "<!-- command: \(command) -->"
            
            // Check if command already exists and replace it
            if markdown.range(of: commandPattern, options: .regularExpression) != nil {
                markdown = markdown.replacingOccurrences(
                    of: commandPattern,
                    with: commandComment,
                    options: .regularExpression
                )
            } else {
                // Add command at the beginning of markdown
                if markdown.isEmpty {
                    markdown = commandComment
                } else {
                    markdown = commandComment + "\n\n" + markdown
                }
            }
        } else {
            // Remove existing command if setting to nil or empty
            markdown = markdown.replacingOccurrences(
                of: commandPattern,
                with: "",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    /// Helper method to extract text using regex pattern
    private func extractUsingPattern(_ pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines, .caseInsensitive]) else {
            return nil
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        
        for match in matches {
            if match.numberOfRanges > 1 {
                let captureRange = match.range(at: 1)
                if let swiftRange = Range(captureRange, in: text) {
                    return String(text[swiftRange])
                }
            }
        }
        
        return nil
    }
}

// MARK: - Node Command Utilities

extension Node {
    /// Checks if the node has a command label
    var hasCommand: Bool {
        return commandLabel != nil && !commandLabel!.isEmpty
    }
    
    /// Returns a formatted display string for the command
    var commandDisplayText: String? {
        guard let command = commandLabel else { return nil }
        
        // Truncate long commands for display
        if command.count > 50 {
            return String(command.prefix(47)) + "..."
        }
        
        return command
    }
    
    /// Validates if the command is properly formatted
    var isCommandValid: Bool {
        guard let command = commandLabel else { return true } // No command is valid
        
        // Basic validation rules
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 300
    }
    
    /// Returns command type based on content analysis
    var commandType: CommandType {
        guard let command = commandLabel?.lowercased() else { return .none }
        
        if command.contains("open") || command.contains("launch") {
            return .launch
        } else if command.contains("search") || command.contains("find") {
            return .search
        } else if command.contains("create") || command.contains("new") {
            return .create
        } else if command.contains("delete") || command.contains("remove") {
            return .delete
        } else if command.contains("edit") || command.contains("modify") {
            return .edit
        } else {
            return .custom
        }
    }
}

// MARK: - Command Type Enumeration

enum CommandType: String, CaseIterable {
    case none = "none"
    case launch = "launch"
    case search = "search"
    case create = "create"
    case delete = "delete"
    case edit = "edit"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .none: return "No Command"
        case .launch: return "Launch"
        case .search: return "Search"
        case .create: return "Create"
        case .delete: return "Delete"
        case .edit: return "Edit"
        case .custom: return "Custom"
        }
    }
    
    var systemImage: String {
        switch self {
        case .none: return "minus.circle"
        case .launch: return "play.circle"
        case .search: return "magnifyingglass.circle"
        case .create: return "plus.circle"
        case .delete: return "trash.circle"
        case .edit: return "pencil.circle"
        case .custom: return "gear.circle"
        }
    }
    
    var color: String {
        switch self {
        case .none: return "gray"
        case .launch: return "green"
        case .search: return "blue"
        case .create: return "purple"
        case .delete: return "red"
        case .edit: return "orange"
        case .custom: return "teal"
        }
    }
}

// MARK: - Node Command Search Extension

extension Node {
    /// Searches for nodes with specific command patterns
    static func nodesWithCommand(in nodes: [Node], matching pattern: String) -> [Node] {
        return nodes.filter { node in
            guard let command = node.commandLabel else { return false }
            return command.localizedCaseInsensitiveContains(pattern)
        }
    }
    
    /// Groups nodes by command type
    static func groupedByCommandType(_ nodes: [Node]) -> [CommandType: [Node]] {
        var grouped: [CommandType: [Node]] = [:]
        
        for node in nodes {
            let type = node.commandType
            if grouped[type] == nil {
                grouped[type] = []
            }
            grouped[type]?.append(node)
        }
        
        return grouped
    }
}

// MARK: - Markdown Command Validation

struct MarkdownCommandValidator {
    /// Validates markdown content for command syntax
    static func validateCommandSyntax(in markdown: String) -> ValidationResult {
        let commandPattern = #"<!--\s*command:\s*(.+?)\s*-->"#
        
        guard let regex = try? NSRegularExpression(pattern: commandPattern, options: []) else {
            return .error("Invalid regex pattern")
        }
        
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let matches = regex.matches(in: markdown, options: [], range: range)
        
        if matches.isEmpty {
            return .noCommand
        }
        
        if matches.count > 1 {
            return .error("Multiple command declarations found")
        }
        
        // Validate the command content
        let match = matches[0]
        if match.numberOfRanges > 1 {
            let captureRange = match.range(at: 1)
            if let swiftRange = Range(captureRange, in: markdown) {
                let command = String(markdown[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                if command.isEmpty {
                    return .error("Empty command")
                }
                
                if command.count > 300 {
                    return .error("Command too long (max 300 characters)")
                }
                
                return .valid(command)
            }
        }
        
        return .error("Invalid command format")
    }
    
    enum ValidationResult {
        case valid(String)
        case noCommand
        case error(String)
        
        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }
        
        var command: String? {
            if case .valid(let cmd) = self { return cmd }
            return nil
        }
        
        var errorMessage: String? {
            if case .error(let msg) = self { return msg }
            return nil
        }
    }
}
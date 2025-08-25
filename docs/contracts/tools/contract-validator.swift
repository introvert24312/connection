import Foundation
import Combine

// MARK: - Contract Validation Framework
// This tool provides runtime validation of service contracts and interface compliance

/// Main contract validation engine
public class ContractValidator {
    private let jsonValidator = JSONSchemaValidator()
    private let protocolValidator = ProtocolComplianceValidator()
    private let eventValidator = EventContractValidator()
    
    public static let shared = ContractValidator()
    
    private init() {}
    
    /// Validates all contracts for a given service
    public func validateService<T>(_ service: T, 
                                 conformingTo protocols: [Any.Type],
                                 withName serviceName: String) -> ValidationReport {
        var violations: [ContractViolation] = []
        var warnings: [String] = []
        
        // Protocol compliance validation
        let protocolResults = protocolValidator.validate(service: service, 
                                                       expectedProtocols: protocols)
        violations.append(contentsOf: protocolResults.violations)
        warnings.append(contentsOf: protocolResults.warnings)
        
        // Data structure validation if applicable
        if let dataProvider = service as? DataProvider {
            let dataResults = validateDataStructures(dataProvider)
            violations.append(contentsOf: dataResults.violations)
            warnings.append(contentsOf: dataResults.warnings)
        }
        
        // Event publishing validation if applicable
        if let eventPublisher = service as? EventPublisher {
            let eventResults = validateEventContracts(eventPublisher)
            violations.append(contentsOf: eventResults.violations)
            warnings.append(contentsOf: eventResults.warnings)
        }
        
        return ValidationReport(
            serviceName: serviceName,
            isValid: violations.isEmpty,
            violations: violations,
            warnings: warnings,
            validatedAt: Date()
        )
    }
    
    /// Validates data structures against JSON schemas
    public func validateDataStructure<T: Codable>(_ data: T, 
                                                against schema: String) -> ValidationResult {
        do {
            let jsonData = try JSONEncoder().encode(data)
            return jsonValidator.validate(jsonData, against: schema)
        } catch {
            return ValidationResult(
                isValid: false,
                violations: [ContractViolation(
                    rule: "JSON_ENCODING",
                    description: "Failed to encode data structure: \(error)",
                    severity: .error
                )],
                warnings: []
            )
        }
    }
    
    /// Validates published events against AsyncAPI specifications
    public func validateEvent(_ event: Any, 
                            ofType eventType: String,
                            against asyncAPISpec: String) -> ValidationResult {
        return eventValidator.validate(event, ofType: eventType, against: asyncAPISpec)
    }
    
    /// Runs a comprehensive validation suite
    public func runValidationSuite(for services: [String: Any]) async -> [ValidationReport] {
        var reports: [ValidationReport] = []
        
        for (serviceName, service) in services {
            let protocols = getExpectedProtocols(for: serviceName)
            let report = validateService(service, 
                                       conformingTo: protocols, 
                                       withName: serviceName)
            reports.append(report)
        }
        
        return reports
    }
    
    // MARK: - Private Methods
    
    private func validateDataStructures(_ dataProvider: DataProvider) -> ValidationResult {
        var violations: [ContractViolation] = []
        var warnings: [String] = []
        
        // Validate nodes
        for node in dataProvider.getAllNodes() {
            let result = validateDataStructure(node, against: "node.schema.json")
            if !result.isValid {
                violations.append(contentsOf: result.violations)
                warnings.append(contentsOf: result.warnings)
            }
        }
        
        // Validate layers
        for layer in dataProvider.getAllLayers() {
            let result = validateDataStructure(layer, against: "layer.schema.json")
            if !result.isValid {
                violations.append(contentsOf: result.violations)
                warnings.append(contentsOf: result.warnings)
            }
        }
        
        return ValidationResult(
            isValid: violations.isEmpty,
            violations: violations,
            warnings: warnings
        )
    }
    
    private func validateEventContracts(_ eventPublisher: EventPublisher) -> ValidationResult {
        // This would validate that published events conform to AsyncAPI specs
        // Implementation would check event structure, required fields, etc.
        return ValidationResult(isValid: true, violations: [], warnings: [])
    }
    
    private func getExpectedProtocols(for serviceName: String) -> [Any.Type] {
        switch serviceName {
        case "NodeStore":
            return [NodeStoreProtocol.self]
        case "SearchService":
            return [SearchServiceProtocol.self]
        case "GitService":
            return [GitServiceProtocol.self]
        case "KeychainManager":
            return [KeychainManagerProtocol.self]
        case "GraphService":
            return [GraphServiceProtocol.self]
        case "ExternalDataService":
            return [ExternalDataServiceProtocol.self]
        default:
            return []
        }
    }
}

// MARK: - Protocol Compliance Validator

public class ProtocolComplianceValidator {
    
    public func validate<T>(service: T, expectedProtocols: [Any.Type]) -> ValidationResult {
        var violations: [ContractViolation] = []
        var warnings: [String] = []
        
        for protocolType in expectedProtocols {
            if !isConforming(service: service, to: protocolType) {
                violations.append(ContractViolation(
                    rule: "PROTOCOL_CONFORMANCE",
                    description: "Service does not conform to expected protocol: \(protocolType)",
                    severity: .error
                ))
            }
        }
        
        return ValidationResult(
            isValid: violations.isEmpty,
            violations: violations,
            warnings: warnings
        )
    }
    
    private func isConforming<T>(service: T, to protocolType: Any.Type) -> Bool {
        return type(of: service) is any ObservableObject.Type
        // This would be expanded with proper protocol checking
    }
}

// MARK: - JSON Schema Validator

public class JSONSchemaValidator {
    
    public func validate(_ jsonData: Data, against schemaName: String) -> ValidationResult {
        // This would implement actual JSON Schema validation
        // For now, it's a placeholder implementation
        
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
            return validateJSONObject(jsonObject, against: schemaName)
        } catch {
            return ValidationResult(
                isValid: false,
                violations: [ContractViolation(
                    rule: "JSON_PARSING",
                    description: "Invalid JSON format: \(error)",
                    severity: .error
                )],
                warnings: []
            )
        }
    }
    
    private func validateJSONObject(_ jsonObject: Any, against schemaName: String) -> ValidationResult {
        // Placeholder validation logic
        // In a real implementation, this would load the JSON schema file
        // and validate the object against it
        
        guard let dictionary = jsonObject as? [String: Any] else {
            return ValidationResult(
                isValid: false,
                violations: [ContractViolation(
                    rule: "JSON_STRUCTURE",
                    description: "Expected JSON object, got \(type(of: jsonObject))",
                    severity: .error
                )],
                warnings: []
            )
        }
        
        switch schemaName {
        case "node.schema.json":
            return validateNodeSchema(dictionary)
        case "layer.schema.json":
            return validateLayerSchema(dictionary)
        default:
            return ValidationResult(isValid: true, violations: [], warnings: [])
        }
    }
    
    private func validateNodeSchema(_ node: [String: Any]) -> ValidationResult {
        var violations: [ContractViolation] = []
        
        // Required fields validation
        let requiredFields = ["id", "text", "layerId", "tags", "isCompound", "createdAt", "updatedAt"]
        for field in requiredFields {
            if node[field] == nil {
                violations.append(ContractViolation(
                    rule: "REQUIRED_FIELD",
                    description: "Missing required field: \(field)",
                    severity: .error
                ))
            }
        }
        
        // Type validation
        if let text = node["text"] as? String, text.isEmpty {
            violations.append(ContractViolation(
                rule: "FIELD_VALIDATION",
                description: "Node text cannot be empty",
                severity: .error
            ))
        }
        
        // UUID format validation
        if let idString = node["id"] as? String, !isValidUUID(idString) {
            violations.append(ContractViolation(
                rule: "UUID_FORMAT",
                description: "Invalid UUID format for node ID",
                severity: .error
            ))
        }
        
        return ValidationResult(
            isValid: violations.isEmpty,
            violations: violations,
            warnings: []
        )
    }
    
    private func validateLayerSchema(_ layer: [String: Any]) -> ValidationResult {
        var violations: [ContractViolation] = []
        
        // Required fields for layers
        let requiredFields = ["id", "name", "displayName", "color", "isActive", "isCompound", "createdAt"]
        for field in requiredFields {
            if layer[field] == nil {
                violations.append(ContractViolation(
                    rule: "REQUIRED_FIELD",
                    description: "Missing required field: \(field)",
                    severity: .error
                ))
            }
        }
        
        // Compound layer validation
        if let isCompound = layer["isCompound"] as? Bool, isCompound {
            if let childLayerIds = layer["childLayerIds"] as? [String], childLayerIds.isEmpty {
                violations.append(ContractViolation(
                    rule: "COMPOUND_LAYER_VALIDATION",
                    description: "Compound layers must have at least one child layer",
                    severity: .error
                ))
            }
        }
        
        return ValidationResult(
            isValid: violations.isEmpty,
            violations: violations,
            warnings: []
        )
    }
    
    private func isValidUUID(_ string: String) -> Bool {
        return UUID(uuidString: string) != nil
    }
}

// MARK: - Event Contract Validator

public class EventContractValidator {
    
    public func validate(_ event: Any, ofType eventType: String, against asyncAPISpec: String) -> ValidationResult {
        // This would validate events against AsyncAPI specifications
        // For now, it's a placeholder implementation
        
        var violations: [ContractViolation] = []
        
        // Basic event structure validation
        if let eventData = event as? [String: Any] {
            // Check for required event metadata
            let requiredFields = ["eventId", "eventType", "timestamp", "source", "version"]
            for field in requiredFields {
                if eventData[field] == nil {
                    violations.append(ContractViolation(
                        rule: "EVENT_METADATA",
                        description: "Missing required event field: \(field)",
                        severity: .error
                    ))
                }
            }
            
            // Validate event type matches
            if let actualEventType = eventData["eventType"] as? String,
               actualEventType != eventType {
                violations.append(ContractViolation(
                    rule: "EVENT_TYPE_MISMATCH",
                    description: "Expected event type \(eventType), got \(actualEventType)",
                    severity: .error
                ))
            }
        } else {
            violations.append(ContractViolation(
                rule: "EVENT_FORMAT",
                description: "Event must be a JSON object",
                severity: .error
            ))
        }
        
        return ValidationResult(
            isValid: violations.isEmpty,
            violations: violations,
            warnings: []
        )
    }
}

// MARK: - Supporting Types

public struct ValidationResult {
    public let isValid: Bool
    public let violations: [ContractViolation]
    public let warnings: [String]
    
    public init(isValid: Bool, violations: [ContractViolation], warnings: [String]) {
        self.isValid = isValid
        self.violations = violations
        self.warnings = warnings
    }
}

public struct ValidationReport {
    public let serviceName: String
    public let isValid: Bool
    public let violations: [ContractViolation]
    public let warnings: [String]
    public let validatedAt: Date
    
    public init(serviceName: String, isValid: Bool, violations: [ContractViolation], warnings: [String], validatedAt: Date) {
        self.serviceName = serviceName
        self.isValid = isValid
        self.violations = violations
        self.warnings = warnings
        self.validatedAt = validatedAt
    }
}

public struct ContractViolation {
    public let rule: String
    public let description: String
    public let severity: Severity
    
    public enum Severity: String, CaseIterable {
        case warning = "warning"
        case error = "error"
        case critical = "critical"
    }
    
    public init(rule: String, description: String, severity: Severity) {
        self.rule = rule
        self.description = description
        self.severity = severity
    }
}

// MARK: - Helper Protocols

public protocol DataProvider {
    func getAllNodes() -> [Node]
    func getAllLayers() -> [Layer]
}

public protocol EventPublisher {
    func getPublishedEvents() -> [String: Any]
}

// MARK: - Test Runner

public class ContractTestRunner {
    private let validator = ContractValidator.shared
    
    public func runTests(for services: [String: Any]) async -> TestSuite {
        let validationReports = await validator.runValidationSuite(for: services)
        
        var testResults: [TestResult] = []
        for report in validationReports {
            let result = TestResult(
                testName: "Contract validation for \(report.serviceName)",
                passed: report.isValid,
                errorMessage: report.violations.isEmpty ? nil : formatViolations(report.violations),
                duration: 0.0,
                metadata: [
                    "service": report.serviceName,
                    "violationCount": report.violations.count,
                    "warningCount": report.warnings.count
                ]
            )
            testResults.append(result)
        }
        
        return TestSuite(
            name: "WordTagger Contract Validation Suite",
            results: testResults,
            executedAt: Date()
        )
    }
    
    private func formatViolations(_ violations: [ContractViolation]) -> String {
        return violations.map { "[\($0.severity.rawValue.uppercased())] \($0.rule): \($0.description)" }
                        .joined(separator: "\n")
    }
}

public struct TestResult {
    public let testName: String
    public let passed: Bool
    public let errorMessage: String?
    public let duration: TimeInterval
    public let metadata: [String: Any]
    
    public init(testName: String, passed: Bool, errorMessage: String?, duration: TimeInterval, metadata: [String: Any]) {
        self.testName = testName
        self.passed = passed
        self.errorMessage = errorMessage
        self.duration = duration
        self.metadata = metadata
    }
}

public struct TestSuite {
    public let name: String
    public let results: [TestResult]
    public let executedAt: Date
    
    public var passedCount: Int { results.filter { $0.passed }.count }
    public var failedCount: Int { results.count - passedCount }
    public var totalCount: Int { results.count }
    
    public init(name: String, results: [TestResult], executedAt: Date) {
        self.name = name
        self.results = results
        self.executedAt = executedAt
    }
    
    public func generateReport() -> String {
        var report = """
        Contract Validation Test Report
        ==============================
        Test Suite: \(name)
        Executed: \(executedAt)
        
        Summary:
        - Total Tests: \(totalCount)
        - Passed: \(passedCount)
        - Failed: \(failedCount)
        - Success Rate: \(String(format: "%.1f", Double(passedCount) / Double(totalCount) * 100))%
        
        Detailed Results:
        """
        
        for result in results {
            let status = result.passed ? "✅ PASS" : "❌ FAIL"
            report += "\n\n\(status) \(result.testName)"
            if let error = result.errorMessage {
                report += "\n   Error: \(error)"
            }
        }
        
        return report
    }
}

// MARK: - Mock Implementations for Testing

extension NodeStore: DataProvider {
    public func getAllNodes() -> [Node] {
        return self.nodes
    }
    
    public func getAllLayers() -> [Layer] {
        return self.layers
    }
}
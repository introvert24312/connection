# WordTagger Contract Validation Tools

This directory contains comprehensive tools for validating and testing WordTagger's service interface contracts.

## Overview

WordTagger uses multiple contract specification formats to define service boundaries:

- **Swift Protocols** - Define service interface contracts in native Swift
- **AsyncAPI Specifications** - Document event-driven communication patterns  
- **JSON Schema** - Validate data structures and API payloads
- **OpenAPI Specifications** - Document HTTP API contracts (if applicable)

## Tools Included

### 1. Contract Test Suite (`contract-test-suite.js`)

A comprehensive JavaScript tool that validates:
- JSON Schema syntax and examples
- AsyncAPI specification structure and consistency
- OpenAPI specification validity
- Cross-contract consistency checks
- Example data validation

**Usage:**
```bash
# Install dependencies
npm install

# Run all contract tests
npm test

# Run tests on specific directory
node contract-test-suite.js /path/to/contracts

# Validate current contracts
npm run validate
```

### 2. Swift Contract Validator (`contract-validator.swift`)

A Swift-based runtime validation framework that:
- Validates service protocol conformance
- Tests data structure compliance with JSON schemas
- Validates published events against AsyncAPI specs
- Provides comprehensive test reporting

**Integration:**
```swift
// Example usage in your Swift code
let validator = ContractValidator.shared
let report = validator.validateService(nodeStore, 
                                     conformingTo: [NodeStoreProtocol.self],
                                     withName: "NodeStore")

if !report.isValid {
    print("Contract violations found:")
    report.violations.forEach { print("- \($0.description)") }
}
```

### 3. Package Configuration (`package.json`)

NPM package configuration for easy dependency management and script execution.

## Contract Files Structure

```
docs/contracts/
├── swift/
│   └── service-protocols.swift     # Swift protocol definitions
├── events/
│   └── wordtagger-events.asyncapi.yaml  # Event specifications
├── schemas/
│   ├── node.schema.json           # Node data structure
│   ├── layer.schema.json          # Layer data structure  
│   ├── search-result.schema.json  # Search result format
│   ├── git-credentials.schema.json # Git credentials format
│   └── external-data-format.schema.json # External data format
├── http/
│   └── *.openapi.yaml             # HTTP API specifications
└── tools/                         # This directory
```

## Validation Rules

### JSON Schema Validation
- All schemas must have `$schema`, `$id`, and `title` properties
- Examples must validate against their schemas
- Required fields must be properly defined
- Data types and formats must be consistent

### AsyncAPI Validation  
- Must specify AsyncAPI version 2.6.0 or higher
- All channels must have descriptions
- Messages must have payload schemas
- Examples must be provided for all messages
- Bindings should match the transport mechanism

### Swift Protocol Validation
- All major services must have corresponding protocol definitions
- Required methods must be present
- Protocol conformance should be verifiable at runtime
- Error handling contracts must be defined

### Cross-Contract Consistency
- Event payload schemas must align with data schemas
- Referenced schemas must exist
- Swift protocols must match schema definitions
- Examples must be valid across all formats

## Running Tests

### Prerequisites
```bash
# Install Node.js dependencies
npm install

# For Swift validation (requires Xcode)
# No additional setup needed - uses Foundation and Combine
```

### Test Execution
```bash
# Run all contract validation tests
npm test

# Run with verbose output
npm run test:verbose  

# Validate specific contract types
node contract-test-suite.js --schemas-only
node contract-test-suite.js --events-only
node contract-test-suite.js --consistency-only
```

### Continuous Integration

Add to your CI pipeline:
```yaml
# Example GitHub Actions step
- name: Validate Service Contracts
  run: |
    cd docs/contracts/tools
    npm install
    npm test
```

## Error Types and Solutions

### Common JSON Schema Errors
- **Missing $schema**: Add `"$schema": "https://json-schema.org/draft/2020-12/schema"`
- **Invalid examples**: Ensure examples conform to the schema definition
- **Missing required fields**: Add all required properties to schema

### Common AsyncAPI Errors  
- **Missing version**: Add `asyncapi: 2.6.0` at the top level
- **Invalid channel names**: Use dot notation for NotificationCenter events
- **Missing examples**: Add example payloads to all message definitions

### Common Consistency Errors
- **Schema reference errors**: Ensure referenced schemas exist
- **Event/schema mismatch**: Align event payload structure with data schemas
- **Protocol/schema mismatch**: Ensure Swift protocols match schema requirements

## Best Practices

### Schema Design
1. Use semantic versioning for schema versions
2. Provide comprehensive examples for all schemas
3. Include validation rules for business logic
4. Use consistent naming conventions

### Event Design  
1. Follow consistent event naming patterns (noun.verb)
2. Include all required metadata fields
3. Provide clear descriptions and examples
4. Use appropriate bindings for the transport mechanism

### Protocol Design
1. Define clear error handling contracts
2. Use appropriate async/await patterns
3. Include performance contracts where relevant
4. Provide comprehensive documentation

## Contributing

When adding new contracts or modifying existing ones:

1. **Update all related files** - If you change a data structure, update the JSON schema, AsyncAPI events, and Swift protocols
2. **Add comprehensive examples** - Include realistic examples that demonstrate proper usage
3. **Run validation tests** - Ensure all tests pass before committing
4. **Update documentation** - Keep this README and other docs up to date

## Troubleshooting

### Test Failures
1. Check the error output for specific validation failures
2. Verify that all referenced files exist
3. Ensure examples match their schemas exactly
4. Check for syntax errors in YAML/JSON files

### Schema Validation Issues
1. Use online JSON Schema validators for debugging
2. Check that all required properties are defined
3. Verify data type consistency
4. Ensure format strings are valid

### AsyncAPI Problems
1. Validate YAML syntax first  
2. Check that all `$ref` references resolve
3. Ensure examples match the payload schema
4. Verify binding configurations

For additional help, check the test output for detailed error messages and suggested fixes.
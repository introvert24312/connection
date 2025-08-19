# Engineering Governance V1 Design Document

## Overview

This design implements a comprehensive engineering governance framework (六件套) that establishes a controllable minimal engineering governance backbone. The system ensures traceability, recoverability, and evolvability through six core components: dependency management, service catalog, CI guardrails, interface contracts, traceId propagation, and feature flags.

The design follows the principle of "规范必须落到 Git 仓库，CI 执行护栏检查" - all governance artifacts must be stored in Git repository with CI enforcement.

## Architecture

### Directory Structure

The governance framework organizes all artifacts under a standardized `docs/` directory structure:

```
docs/
├── architecture/          # L2 architecture diagrams + 3 critical data flows
├── services/              # Service catalog (one YAML per service)
├── contracts/             # Interface contracts
│   ├── http/             # OpenAPI specifications
│   └── events/           # AsyncAPI specifications
├── dependencies/          # Fine-grained endpoint dependencies (optional)
├── runbooks/             # Troubleshooting guides
├── release/              # Feature flags and rollback procedures
└── sre/                  # SLO and alerting baselines
```

### Core Components

1. **Dependency Management**: Two-tier approach with coarse (service-to-service) and fine (endpoint-to-endpoint) dependencies
2. **Service Catalog**: Lightweight service registry with essential metadata
3. **Contract Management**: API specifications using OpenAPI and AsyncAPI standards
4. **CI Guardrails**: Automated validation preventing documentation drift
5. **Distributed Tracing**: TraceId propagation across all service boundaries
6. **Feature Management**: Boolean flags with rollback strategies

## Components and Interfaces

### 1. Dependency Management Component

**Coarse Dependencies (Service-to-Service)**
- Storage: `docs/services/<svc>.yaml` in `depends_on` field
- Format: Array of service names
- Purpose: High-level service relationship mapping

**Fine Dependencies (Endpoint-to-Endpoint)**
- Storage: `docs/dependencies/*.yaml`
- Format: Structured YAML with from/to endpoints, contracts, and SLA requirements
- Purpose: Critical path documentation for key business flows

```yaml
# Example: docs/dependencies/order-beef.yaml
from: canteen POST /v1/order-beef
to:
  butcher POST /v1/beef
contract:
  required: [cut, kg, traceId]
  errors: [401, 409]
  auth: bearer
  timeout_ms: 2000
```

### 2. Service Catalog Component

**Service Registry**
- Storage: `docs/services/<service-name>.yaml`
- Schema: Fixed 8-10 line format for quick reference
- Required fields: name, purpose, owner, health, openapi, depends_on, runbook

```yaml
# Example: docs/services/canteen.yaml
name: canteen
purpose: 做菜
owner: Alice @oncall-123
health: /healthz
openapi: ../contracts/http/canteen.openapi.yaml
depends_on: [butcher, pantry]
runbook: ../runbooks/canteen.md
```

### 3. Contract Management Component

**HTTP API Contracts**
- Storage: `docs/contracts/http/*.openapi.yaml`
- Standard: OpenAPI 3.0+
- Minimum coverage: 3 critical endpoints per service

**Event Contracts**
- Storage: `docs/contracts/events/*.asyncapi.yaml`
- Standard: AsyncAPI 2.0+
- Minimum coverage: 1 main topic per event-driven service

**Contract Requirements**
- Paths and methods
- Required/optional fields
- Response schemas and error codes
- Authentication mechanisms
- Timeout specifications

### 4. CI Guardrails Component

**Catalog Schema Validation**
- Validates all `docs/services/*.yaml` files
- Checks required fields completeness
- Blocks PR merge on validation failure

**Contract Diff Detection**
- Compares OpenAPI/AsyncAPI changes against main branch
- Identifies breaking changes (removed endpoints, changed required fields, etc.)
- Blocks PR merge on incompatible changes

**Implementation**: GitHub Actions / GitLab CI pipelines

### 5. Distributed Tracing Component

**TraceId Generation**
- Entry points generate UUID traceId
- Format: Standard UUID or W3C Trace Context

**Propagation Mechanisms**
- HTTP: `traceparent` header (W3C standard) or `X-Trace-Id`
- gRPC: Metadata field
- Message queues: Header or payload field

**Logging Integration**
- All log entries include `traceId` field
- Structured logging format (JSON recommended)
- End-to-end tracing examples documented

### 6. Feature Management Component

**Feature Flags**
- Storage: `docs/release/flags.yaml`
- Format: Boolean flags with metadata
- Default state: "off" for new features

```yaml
# Example: docs/release/flags.yaml
flags:
  - name: login_v2
    owner: Alice
    default: off
    description: New authentication flow
```

**Rollback Strategy**
- Documentation: `docs/release/rollback.md`
- Three-tier approach:
  1. Disable feature flag
  2. Version rollback (previous container image)
  3. Database down script (if needed)

## Data Models

### Service Catalog Schema

```yaml
name: string (required)           # Service identifier
purpose: string (required)        # Brief description
owner: string (required)          # Team/person + oncall info
health: string (required)         # Health check endpoint
openapi: string (optional)        # Path to OpenAPI spec
asyncapi: string (optional)       # Path to AsyncAPI spec
depends_on: array (optional)      # List of dependent services
runbook: string (required)        # Path to troubleshooting guide
```

### Dependency Schema

```yaml
from: string (required)           # Source endpoint
to: object (required)             # Target service/endpoint
contract:
  required: array                 # Required fields
  errors: array                   # Expected error codes
  auth: string                    # Authentication method
  timeout_ms: integer             # Timeout specification
```

### Feature Flag Schema

```yaml
flags:
  - name: string (required)       # Flag identifier
    owner: string (required)      # Responsible person
    default: string (required)    # Default state (on/off)
    description: string (optional) # Purpose description
```

## Error Handling

### CI Pipeline Failures

**Catalog Validation Errors**
- Missing required fields in service YAML
- Invalid YAML syntax
- Broken file references

**Contract Diff Errors**
- Breaking API changes detected
- Removed endpoints without deprecation
- Changed required fields

**Resolution Strategy**
- Clear error messages with specific file/line references
- Automated suggestions for common fixes
- Documentation links for resolution guidance

### Runtime Tracing Failures

**Missing TraceId**
- Fallback: Generate new traceId at service boundary
- Log warning for missing upstream traceId
- Continue processing with new trace

**Propagation Failures**
- Log error but don't block request processing
- Use service-local traceId for logging
- Alert on high failure rates

## Testing Strategy

### Documentation Testing

**Schema Validation Tests**
- Automated validation of all YAML files
- JSON Schema validation for service catalog
- OpenAPI/AsyncAPI specification validation

**Link Validation Tests**
- Verify all internal file references
- Check external URL accessibility
- Validate contract-to-service mappings

### Integration Testing

**TraceId Propagation Tests**
- End-to-end trace validation across services
- Header propagation verification
- Logging integration tests

**Feature Flag Tests**
- Flag toggle functionality
- Default state verification
- Rollback procedure validation

### CI Pipeline Tests

**Guardrail Effectiveness Tests**
- Intentional breaking changes to verify blocking
- Schema violation detection
- False positive/negative analysis

**Performance Tests**
- CI pipeline execution time
- Large repository handling
- Concurrent PR processing

## Implementation Phases

### Phase 1: Foundation (Tasks 1-3)
- Directory structure setup
- Service catalog for existing services
- Basic contract documentation

### Phase 2: Automation (Tasks 4-5)
- CI guardrail implementation
- TraceId integration
- Feature flag framework

### Phase 3: Enhancement (Tasks 6-7)
- Advanced contract validation
- Comprehensive documentation
- Monitoring and alerting

## Security Considerations

### Access Control
- Git repository permissions for documentation updates
- CI pipeline security for automated checks
- Feature flag access controls

### Data Protection
- No sensitive data in public documentation
- Secure handling of API keys in contracts
- TraceId privacy considerations

## Monitoring and Observability

### Metrics
- Documentation coverage percentage
- CI guardrail effectiveness rates
- TraceId propagation success rates
- Feature flag usage statistics

### Alerting
- Failed CI validations
- Missing service documentation
- Broken contract references
- TraceId propagation failures

This design provides a comprehensive foundation for engineering governance while maintaining simplicity and enforceability through automated CI checks.
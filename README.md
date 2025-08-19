# Engineering Governance Framework

This repository implements a comprehensive engineering governance framework (六件套) with six core components:

1. **Dependency Management** - Service-to-service and endpoint-to-endpoint dependencies
2. **Service Catalog** - Lightweight service registry with essential metadata  
3. **Interface Contracts** - OpenAPI and AsyncAPI specifications
4. **CI Guardrails** - Automated validation preventing documentation drift
5. **Distributed Tracing** - TraceId propagation across all service boundaries
6. **Feature Management** - Boolean flags with rollback strategies

## Directory Structure

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

## Validation

### Setup

```bash
npm install
```

### Running Validation

```bash
# Validate all governance documentation
npm run validate

# Validate only service catalog
npm run validate:services

# Validate only dependencies
npm run validate:dependencies
```

### Manual Validation

```bash
# Validate all
node scripts/validate-governance.js

# Validate specific components
node scripts/validate-governance.js services
node scripts/validate-governance.js dependencies
```

## Service Catalog Format

Each service should have a YAML file in `docs/services/<service-name>.yaml`:

```yaml
name: canteen
purpose: 做菜
owner: Alice @oncall-123
health: /healthz
openapi: ../contracts/http/canteen.openapi.yaml
depends_on: [butcher, pantry]
runbook: ../runbooks/canteen.md
```

## Dependency Format

Fine-grained dependencies in `docs/dependencies/*.yaml`:

```yaml
from: canteen POST /v1/order-beef
to: butcher POST /v1/beef
contract:
  required: [cut, kg, traceId]
  errors: [401, 409]
  auth: bearer
  timeout_ms: 2000
```

## Next Steps

1. Populate service catalog for existing services
2. Create OpenAPI/AsyncAPI contracts
3. Set up CI guardrails
4. Implement traceId propagation
5. Configure feature flags
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';
import yaml from 'js-yaml';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('Governance Framework Integration Tests', () => {
  const testDir = path.join(__dirname, '../test-integration');
  const scriptsDir = path.join(__dirname, '../scripts');
  
  beforeEach(() => {
    // Create clean test environment
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true, force: true });
    }
    
    // Create complete governance directory structure
    const dirs = [
      'docs/services',
      'docs/contracts/http',
      'docs/contracts/events',
      'docs/dependencies',
      'docs/runbooks',
      'docs/release',
      'docs/architecture',
      'docs/sre'
    ];
    
    dirs.forEach(dir => {
      fs.mkdirSync(path.join(testDir, dir), { recursive: true });
    });
  });
  
  afterEach(() => {
    // Clean up test directory
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true, force: true });
    }
  });

  describe('End-to-End Governance Framework Validation', () => {
    it('should validate complete governance setup with all components', async () => {
      // Create a complete governance setup
      await createCompleteGovernanceSetup(testDir);
      
      // Run all validations
      const validations = [
        { flag: '--catalog', name: 'Service Catalog' },
        { flag: '--openapi', name: 'OpenAPI Contracts' },
        { flag: '--asyncapi', name: 'AsyncAPI Contracts' },
        { flag: '--sync', name: 'Documentation Sync' },
        { flag: '--orphans', name: 'Orphaned Contracts' }
      ];
      
      for (const validation of validations) {
        const result = execSync(
          `node ${scriptsDir}/validate-governance.js ${validation.flag} --path=${testDir}/docs`,
          { encoding: 'utf8', cwd: __dirname }
        );
        
        expect(result).toContain('✓');
        expect(result).not.toContain('✗');
      }
    });

    it('should detect and report multiple validation failures across components', async () => {
      // Create governance setup with intentional errors
      await createGovernanceSetupWithErrors(testDir);
      
      const validationResults = [];
      const validations = [
        { flag: '--catalog', name: 'Service Catalog' },
        { flag: '--openapi', name: 'OpenAPI Contracts' },
        { flag: '--sync', name: 'Documentation Sync' }
      ];
      
      for (const validation of validations) {
        try {
          execSync(
            `node ${scriptsDir}/validate-governance.js ${validation.flag} --path=${testDir}/docs`,
            { encoding: 'utf8', cwd: __dirname }
          );
          validationResults.push({ ...validation, passed: true });
        } catch (error) {
          validationResults.push({ 
            ...validation, 
            passed: false, 
            output: error.stdout || error.message 
          });
        }
      }
      
      // Expect some validations to fail
      const failedValidations = validationResults.filter(v => !v.passed);
      expect(failedValidations.length).toBeGreaterThan(0);
      
      // Verify specific error types are detected
      const catalogFailure = failedValidations.find(v => v.name === 'Service Catalog');
      expect(catalogFailure).toBeDefined();
      expect(catalogFailure.output).toContain('Missing Required Fields');
    });
  });

  describe('CI Guardrail Integration Tests', () => {
    it('should simulate complete CI pipeline validation', async () => {
      // Create valid governance setup
      await createCompleteGovernanceSetup(testDir);
      
      // Simulate CI pipeline by running all checks
      const ciChecks = [
        'catalog',
        'openapi', 
        'asyncapi',
        'sync',
        'orphans'
      ];
      
      let allPassed = true;
      const results = {};
      
      for (const check of ciChecks) {
        try {
          const result = execSync(
            `node ${scriptsDir}/validate-governance.js --${check} --path=${testDir}/docs`,
            { encoding: 'utf8', cwd: __dirname }
          );
          results[check] = { passed: true, output: result };
        } catch (error) {
          results[check] = { passed: false, output: error.stdout || error.message };
          allPassed = false;
        }
      }
      
      expect(allPassed).toBe(true);
      
      // Verify each check passed
      Object.entries(results).forEach(([check, result]) => {
        expect(result.passed).toBe(true);
        expect(result.output).toContain('✓');
      });
    });

    it('should block CI pipeline when breaking changes are detected', async () => {
      // Create initial valid setup
      await createCompleteGovernanceSetup(testDir);
      
      // Introduce breaking changes
      const breakingContract = {
        openapi: '3.0.0',
        info: { title: 'Breaking API', version: '2.0.0' },
        paths: {
          '/removed-endpoint': {
            get: { responses: { '200': { description: 'This will be removed' } } }
          }
        }
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/contracts/http/breaking.openapi.yaml'),
        yaml.dump(breakingContract)
      );
      
      // Update service to reference the breaking contract
      const breakingService = {
        name: 'breaking-service',
        purpose: 'Service with breaking changes',
        owner: 'Test Team @test-oncall',
        health: '/healthz',
        openapi: '../contracts/http/breaking.openapi.yaml',
        runbook: '../runbooks/breaking-service.md'
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/breaking-service.yaml'),
        yaml.dump(breakingService)
      );
      
      // Run validation - should still pass for new setup
      const result = execSync(
        `node ${scriptsDir}/validate-governance.js --catalog --openapi --sync --path=${testDir}/docs`,
        { encoding: 'utf8', cwd: __dirname }
      );
      
      expect(result).toContain('✓');
    });
  });

  describe('TraceId Propagation Integration Tests', () => {
    it('should validate traceId propagation across multiple service calls', async () => {
      // Test traceId utilities integration
      const { generateTraceId, extractTraceIdFromHeaders, createTracingHeaders } = 
        await import('../scripts/tracing-utils.js');
      
      // Simulate service chain: API Gateway -> Service A -> Service B
      const originalTraceId = generateTraceId();
      
      // Service A receives request with traceId
      const serviceAHeaders = createTracingHeaders(originalTraceId);
      const extractedTraceId = extractTraceIdFromHeaders(serviceAHeaders);
      
      expect(extractedTraceId).toBe(originalTraceId);
      
      // Service A makes call to Service B with same traceId
      const serviceBHeaders = createTracingHeaders(extractedTraceId);
      const finalTraceId = extractTraceIdFromHeaders(serviceBHeaders);
      
      expect(finalTraceId).toBe(originalTraceId);
      
      // Verify tracing headers format
      expect(serviceAHeaders).toHaveProperty('traceparent');
      expect(serviceAHeaders).toHaveProperty('X-Trace-Id', originalTraceId);
      expect(serviceBHeaders['traceparent']).toMatch(/^00-[0-9a-f]{32}-[0-9a-f]{16}-01$/);
    });

    it('should handle tracing middleware integration', async () => {
      const { tracingMiddleware } = await import('../scripts/tracing-middleware.js');
      
      // Mock Express request/response
      const req = { headers: {} };
      const res = { set: jest.fn() };
      const next = jest.fn();
      
      // Test middleware without existing traceId
      tracingMiddleware(req, res, next);
      
      expect(req.traceId).toBeDefined();
      expect(req.traceId).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
      expect(res.set).toHaveBeenCalledWith('X-Trace-Id', req.traceId);
      expect(next).toHaveBeenCalled();
      
      // Test middleware with existing traceId
      const existingTraceId = 'existing-trace-id';
      const req2 = { headers: { 'x-trace-id': existingTraceId } };
      const res2 = { set: jest.fn() };
      const next2 = jest.fn();
      
      tracingMiddleware(req2, res2, next2);
      
      expect(req2.traceId).toBe(existingTraceId);
      expect(res2.set).toHaveBeenCalledWith('X-Trace-Id', existingTraceId);
    });
  });

  describe('Feature Flag Integration Tests', () => {
    it('should validate feature flag configuration and rollback procedures', async () => {
      // Create feature flag configuration
      const featureFlags = {
        flags: [
          {
            name: 'new-authentication',
            owner: 'Security Team @security-oncall',
            default: 'off',
            description: 'New OAuth2 authentication flow'
          },
          {
            name: 'enhanced-search',
            owner: 'Search Team @search-oncall', 
            default: 'off',
            description: 'Enhanced search with ML ranking'
          }
        ]
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/release/flags.yaml'),
        yaml.dump(featureFlags)
      );
      
      // Create rollback procedure
      const rollbackProcedure = `# Rollback Procedures

## Feature Flag Rollback

### 1. Disable Feature Flag
\`\`\`bash
# Update flags.yaml to set flag to 'off'
# Deploy configuration change
\`\`\`

### 2. Version Rollback
\`\`\`bash
# Rollback to previous container image
kubectl rollout undo deployment/service-name
\`\`\`

### 3. Database Down Script (if needed)
\`\`\`sql
-- Rollback database schema changes if any
-- This should be tested in staging first
\`\`\`
`;
      
      fs.writeFileSync(
        path.join(testDir, 'docs/release/rollback.md'),
        rollbackProcedure
      );
      
      // Validate files exist and are properly formatted
      expect(fs.existsSync(path.join(testDir, 'docs/release/flags.yaml'))).toBe(true);
      expect(fs.existsSync(path.join(testDir, 'docs/release/rollback.md'))).toBe(true);
      
      // Parse and validate flag structure
      const flagsContent = fs.readFileSync(path.join(testDir, 'docs/release/flags.yaml'), 'utf8');
      const parsedFlags = yaml.load(flagsContent);
      
      expect(parsedFlags.flags).toHaveLength(2);
      expect(parsedFlags.flags[0]).toHaveProperty('name');
      expect(parsedFlags.flags[0]).toHaveProperty('owner');
      expect(parsedFlags.flags[0]).toHaveProperty('default', 'off');
    });
  });

  describe('Documentation Coverage and Completeness Tests', () => {
    it('should validate complete documentation coverage for all services', async () => {
      // Create comprehensive documentation setup
      await createCompleteGovernanceSetup(testDir);
      
      // Verify all required documentation exists
      const requiredFiles = [
        'docs/services/canteen.yaml',
        'docs/services/butcher.yaml',
        'docs/contracts/http/canteen.openapi.yaml',
        'docs/contracts/http/butcher.openapi.yaml',
        'docs/contracts/events/canteen.asyncapi.yaml',
        'docs/dependencies/order-beef.yaml',
        'docs/runbooks/canteen.md',
        'docs/runbooks/butcher.md',
        'docs/release/flags.yaml',
        'docs/release/rollback.md',
        'docs/architecture/l2.mmd'
      ];
      
      for (const file of requiredFiles) {
        const filePath = path.join(testDir, file);
        expect(fs.existsSync(filePath)).toBe(true);
      }
      
      // Validate cross-references between documents
      const canteenService = yaml.load(
        fs.readFileSync(path.join(testDir, 'docs/services/canteen.yaml'), 'utf8')
      );
      
      // Verify service references existing contracts
      const openapiPath = path.resolve(
        path.join(testDir, 'docs/services'),
        canteenService.openapi
      );
      expect(fs.existsSync(openapiPath)).toBe(true);
      
      const asyncapiPath = path.resolve(
        path.join(testDir, 'docs/services'),
        canteenService.asyncapi
      );
      expect(fs.existsSync(asyncapiPath)).toBe(true);
    });

    it('should detect missing documentation and provide actionable feedback', async () => {
      // Create incomplete governance setup
      const incompleteService = {
        name: 'incomplete-service',
        purpose: 'Service missing documentation',
        owner: 'Test Team @test-oncall',
        health: '/healthz',
        openapi: '../contracts/http/missing.openapi.yaml', // This file won't exist
        runbook: '../runbooks/incomplete-service.md'
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/incomplete-service.yaml'),
        yaml.dump(incompleteService)
      );
      
      // Run synchronization check
      try {
        execSync(
          `node ${scriptsDir}/validate-governance.js --sync --path=${testDir}/docs`,
          { encoding: 'utf8', cwd: __dirname }
        );
        // Should not reach here
        expect(true).toBe(false);
      } catch (error) {
        expect(error.stdout).toContain('Referenced OpenAPI contract not found');
        expect(error.stdout).toContain('missing.openapi.yaml');
      }
    });
  });

  describe('Performance and Scalability Tests', () => {
    it('should handle large governance repositories efficiently', async () => {
      // Create large number of services and contracts
      const serviceCount = 50;
      const startTime = Date.now();
      
      for (let i = 0; i < serviceCount; i++) {
        const service = {
          name: `service-${i.toString().padStart(3, '0')}`,
          purpose: `Test service number ${i}`,
          owner: `Team-${i % 5} @oncall-${i % 5}`,
          health: '/healthz',
          openapi: `../contracts/http/service-${i.toString().padStart(3, '0')}.openapi.yaml`,
          runbook: `../runbooks/service-${i.toString().padStart(3, '0')}.md`
        };
        
        fs.writeFileSync(
          path.join(testDir, `docs/services/service-${i.toString().padStart(3, '0')}.yaml`),
          yaml.dump(service)
        );
        
        const contract = {
          openapi: '3.0.0',
          info: { title: `Service ${i} API`, version: '1.0.0' },
          paths: {
            [`/service-${i}`]: {
              get: { responses: { '200': { description: 'OK' } } }
            }
          }
        };
        
        fs.writeFileSync(
          path.join(testDir, `docs/contracts/http/service-${i.toString().padStart(3, '0')}.openapi.yaml`),
          yaml.dump(contract)
        );
      }
      
      const setupTime = Date.now() - startTime;
      console.log(`Setup time for ${serviceCount} services: ${setupTime}ms`);
      
      // Run validation on large repository
      const validationStartTime = Date.now();
      const result = execSync(
        `node ${scriptsDir}/validate-governance.js --catalog --openapi --sync --path=${testDir}/docs`,
        { encoding: 'utf8', cwd: __dirname }
      );
      const validationTime = Date.now() - validationStartTime;
      
      console.log(`Validation time for ${serviceCount} services: ${validationTime}ms`);
      
      // Expect validation to complete within reasonable time (< 10 seconds)
      expect(validationTime).toBeLessThan(10000);
      expect(result).toContain(`Found ${serviceCount} service catalog files`);
      expect(result).toContain(`Found ${serviceCount} OpenAPI contract files`);
    });
  });
});

// Helper functions for creating test data
async function createCompleteGovernanceSetup(testDir) {
  // Create service catalog entries
  const canteenService = {
    name: 'canteen',
    purpose: '做菜',
    owner: 'Alice @oncall-123',
    health: '/healthz',
    openapi: '../contracts/http/canteen.openapi.yaml',
    asyncapi: '../contracts/events/canteen.asyncapi.yaml',
    depends_on: ['butcher', 'pantry'],
    runbook: '../runbooks/canteen.md'
  };
  
  const butcherService = {
    name: 'butcher',
    purpose: 'Meat processing service',
    owner: 'Bob @oncall-456',
    health: '/health',
    openapi: '../contracts/http/butcher.openapi.yaml',
    runbook: '../runbooks/butcher.md'
  };
  
  fs.writeFileSync(
    path.join(testDir, 'docs/services/canteen.yaml'),
    yaml.dump(canteenService)
  );
  
  fs.writeFileSync(
    path.join(testDir, 'docs/services/butcher.yaml'),
    yaml.dump(butcherService)
  );
  
  // Create OpenAPI contracts
  const canteenOpenAPI = {
    openapi: '3.0.0',
    info: { title: 'Canteen API', version: '1.0.0' },
    paths: {
      '/v1/order-beef': {
        post: {
          summary: 'Order beef from butcher',
          requestBody: {
            required: true,
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  required: ['cut', 'kg', 'traceId'],
                  properties: {
                    cut: { type: 'string' },
                    kg: { type: 'number' },
                    traceId: { type: 'string' }
                  }
                }
              }
            }
          },
          responses: {
            '200': { description: 'Order successful' },
            '401': { description: 'Unauthorized' },
            '409': { description: 'Conflict' }
          }
        }
      },
      '/v1/menu': {
        get: {
          responses: { '200': { description: 'Menu items' } }
        }
      },
      '/healthz': {
        get: {
          responses: { '200': { description: 'Health check' } }
        }
      }
    }
  };
  
  const butcherOpenAPI = {
    openapi: '3.0.0',
    info: { title: 'Butcher API', version: '1.0.0' },
    paths: {
      '/v1/beef': {
        post: {
          summary: 'Process beef order',
          responses: {
            '200': { description: 'Processing successful' },
            '401': { description: 'Unauthorized' },
            '409': { description: 'Conflict' }
          }
        }
      },
      '/v1/inventory': {
        get: {
          responses: { '200': { description: 'Current inventory' } }
        }
      },
      '/health': {
        get: {
          responses: { '200': { description: 'Health check' } }
        }
      }
    }
  };
  
  fs.writeFileSync(
    path.join(testDir, 'docs/contracts/http/canteen.openapi.yaml'),
    yaml.dump(canteenOpenAPI)
  );
  
  fs.writeFileSync(
    path.join(testDir, 'docs/contracts/http/butcher.openapi.yaml'),
    yaml.dump(butcherOpenAPI)
  );
  
  // Create AsyncAPI contract
  const canteenAsyncAPI = {
    asyncapi: '2.0.0',
    info: { title: 'Canteen Events', version: '1.0.0' },
    channels: {
      'canteen/orders': {
        subscribe: {
          message: {
            payload: {
              type: 'object',
              properties: {
                orderId: { type: 'string' },
                customerId: { type: 'string' },
                items: { type: 'array' },
                traceId: { type: 'string' }
              }
            }
          }
        }
      }
    }
  };
  
  fs.writeFileSync(
    path.join(testDir, 'docs/contracts/events/canteen.asyncapi.yaml'),
    yaml.dump(canteenAsyncAPI)
  );
  
  // Create dependency mapping
  const orderBeefDependency = {
    from: 'canteen POST /v1/order-beef',
    to: 'butcher POST /v1/beef',
    contract: {
      required: ['cut', 'kg', 'traceId'],
      errors: [401, 409],
      auth: 'bearer',
      timeout_ms: 2000
    }
  };
  
  fs.writeFileSync(
    path.join(testDir, 'docs/dependencies/order-beef.yaml'),
    yaml.dump(orderBeefDependency)
  );
  
  // Create runbooks
  const canteenRunbook = `# Canteen Service Runbook

## Overview
Service for managing restaurant operations and orders.

## Health Check
- Endpoint: \`GET /healthz\`
- Expected: 200 OK

## Common Issues
1. **High latency**: Check butcher service dependency
2. **Order failures**: Verify authentication tokens
3. **Database connection**: Check connection pool status

## Escalation
Contact: Alice @oncall-123
`;
  
  const butcherRunbook = `# Butcher Service Runbook

## Overview
Service for processing meat orders and inventory management.

## Health Check
- Endpoint: \`GET /health\`
- Expected: 200 OK

## Common Issues
1. **Inventory shortage**: Check supplier integration
2. **Processing delays**: Monitor queue depth
3. **Quality issues**: Review processing parameters

## Escalation
Contact: Bob @oncall-456
`;
  
  fs.writeFileSync(path.join(testDir, 'docs/runbooks/canteen.md'), canteenRunbook);
  fs.writeFileSync(path.join(testDir, 'docs/runbooks/butcher.md'), butcherRunbook);
  
  // Create feature flags
  const featureFlags = {
    flags: [
      {
        name: 'new-menu-system',
        owner: 'Canteen Team @canteen-oncall',
        default: 'off',
        description: 'New dynamic menu system'
      }
    ]
  };
  
  fs.writeFileSync(
    path.join(testDir, 'docs/release/flags.yaml'),
    yaml.dump(featureFlags)
  );
  
  // Create rollback procedure
  const rollbackProcedure = `# Rollback Procedures

## 1. Disable Feature Flag
Update flags.yaml and deploy configuration

## 2. Version Rollback
Use previous container image

## 3. Database Down Script
Run rollback scripts if needed
`;
  
  fs.writeFileSync(path.join(testDir, 'docs/release/rollback.md'), rollbackProcedure);
  
  // Create architecture diagram
  const architectureDiagram = `graph TD
    A[API Gateway] --> B[Canteen Service]
    B --> C[Butcher Service]
    B --> D[Pantry Service]
    C --> E[Supplier API]
    B --> F[Order Queue]
`;
  
  fs.writeFileSync(path.join(testDir, 'docs/architecture/l2.mmd'), architectureDiagram);
}

async function createGovernanceSetupWithErrors(testDir) {
  // Create service with missing required fields
  const invalidService = {
    name: 'invalid-service',
    purpose: 'Service with validation errors'
    // Missing: owner, health, runbook
  };
  
  fs.writeFileSync(
    path.join(testDir, 'docs/services/invalid-service.yaml'),
    yaml.dump(invalidService)
  );
  
  // Create service referencing non-existent contract
  const orphanedService = {
    name: 'orphaned-service',
    purpose: 'Service referencing missing contract',
    owner: 'Test Team @test-oncall',
    health: '/healthz',
    openapi: '../contracts/http/nonexistent.openapi.yaml',
    runbook: '../runbooks/orphaned-service.md'
  };
  
  fs.writeFileSync(
    path.join(testDir, 'docs/services/orphaned-service.yaml'),
    yaml.dump(orphanedService)
  );
  
  // Create invalid OpenAPI contract
  const invalidOpenAPI = {
    openapi: '3.0.0',
    info: { title: 'Invalid API' }
    // Missing: version, paths
  };
  
  fs.writeFileSync(
    path.join(testDir, 'docs/contracts/http/invalid.openapi.yaml'),
    yaml.dump(invalidOpenAPI)
  );
  
  // Create orphaned contract (no service references it)
  const orphanedContract = {
    openapi: '3.0.0',
    info: { title: 'Orphaned API', version: '1.0.0' },
    paths: {
      '/orphaned': {
        get: { responses: { '200': { description: 'OK' } } }
      }
    }
  };
  
  fs.writeFileSync(
    path.join(testDir, 'docs/contracts/http/orphaned.openapi.yaml'),
    yaml.dump(orphanedContract)
  );
}
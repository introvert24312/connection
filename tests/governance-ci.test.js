import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('Governance CI Validation', () => {
  const testDir = path.join(__dirname, '../test-governance');
  const scriptsDir = path.join(__dirname, '../scripts');
  
  beforeEach(() => {
    // Create test directory structure
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true, force: true });
    }
    
    fs.mkdirSync(testDir, { recursive: true });
    fs.mkdirSync(path.join(testDir, 'docs/services'), { recursive: true });
    fs.mkdirSync(path.join(testDir, 'docs/contracts/http'), { recursive: true });
    fs.mkdirSync(path.join(testDir, 'docs/contracts/events'), { recursive: true });
    fs.mkdirSync(path.join(testDir, 'docs/dependencies'), { recursive: true });
  });
  
  afterEach(() => {
    // Clean up test directory
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true, force: true });
    }
  });

  describe('Service Catalog Validation', () => {
    it('should pass validation for valid service catalog files', () => {
      // Create valid service catalog file
      const validService = {
        name: 'test-service',
        purpose: 'Test service for validation',
        owner: 'Test Team @test-oncall',
        health: '/healthz',
        openapi: '../contracts/http/test-service.openapi.yaml',
        depends_on: ['dependency-service'],
        runbook: '../runbooks/test-service.md'
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/test-service.yaml'),
        JSON.stringify(validService, null, 2)
      );
      
      // Run validation
      const result = execSync(
        `node ${scriptsDir}/validate-governance.js --catalog --path=${testDir}/docs`,
        { encoding: 'utf8', cwd: __dirname }
      );
      
      expect(result).toContain('✓ test-service.yaml');
    });
    
    it('should fail validation for service catalog with missing required fields', () => {
      // Create invalid service catalog file (missing required fields)
      const invalidService = {
        name: 'test-service',
        purpose: 'Test service for validation'
        // Missing: owner, health, runbook
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/test-service.yaml'),
        JSON.stringify(invalidService, null, 2)
      );
      
      // Run validation and expect failure
      expect(() => {
        execSync(
          `node ${scriptsDir}/validate-governance.js --catalog --path=${testDir}/docs`,
          { encoding: 'utf8', cwd: __dirname }
        );
      }).toThrow();
    });
    
    it('should fail validation for invalid YAML syntax', () => {
      // Create file with invalid YAML
      fs.writeFileSync(
        path.join(testDir, 'docs/services/invalid.yaml'),
        'name: test\ninvalid: yaml: syntax: error'
      );
      
      // Run validation and expect failure
      expect(() => {
        execSync(
          `node ${scriptsDir}/validate-governance.js --catalog --path=${testDir}/docs`,
          { encoding: 'utf8', cwd: __dirname }
        );
      }).toThrow();
    });
  });

  describe('OpenAPI Contract Validation', () => {
    it('should pass validation for valid OpenAPI contracts', () => {
      // Create valid OpenAPI contract
      const validOpenAPI = {
        openapi: '3.0.0',
        info: {
          title: 'Test API',
          version: '1.0.0'
        },
        paths: {
          '/test': {
            get: {
              summary: 'Test endpoint',
              responses: {
                '200': {
                  description: 'Success'
                }
              }
            }
          }
        }
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/contracts/http/test.openapi.yaml'),
        JSON.stringify(validOpenAPI, null, 2)
      );
      
      // Run validation
      const result = execSync(
        `node ${scriptsDir}/validate-governance.js --openapi --path=${testDir}/docs`,
        { encoding: 'utf8', cwd: __dirname }
      );
      
      expect(result).toContain('✓ test.openapi.yaml');
    });
    
    it('should fail validation for OpenAPI missing required fields', () => {
      // Create invalid OpenAPI contract (missing required fields)
      const invalidOpenAPI = {
        openapi: '3.0.0',
        info: {
          title: 'Test API'
          // Missing version
        }
        // Missing paths
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/contracts/http/invalid.openapi.yaml'),
        JSON.stringify(invalidOpenAPI, null, 2)
      );
      
      // Run validation and expect failure
      expect(() => {
        execSync(
          `node ${scriptsDir}/validate-governance.js --openapi --path=${testDir}/docs`,
          { encoding: 'utf8', cwd: __dirname }
        );
      }).toThrow();
    });
  });

  describe('AsyncAPI Contract Validation', () => {
    it('should pass validation for valid AsyncAPI contracts', () => {
      // Create valid AsyncAPI contract
      const validAsyncAPI = {
        asyncapi: '2.0.0',
        info: {
          title: 'Test Events',
          version: '1.0.0'
        },
        channels: {
          'test/events': {
            subscribe: {
              message: {
                payload: {
                  type: 'object'
                }
              }
            }
          }
        }
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/contracts/events/test.asyncapi.yaml'),
        JSON.stringify(validAsyncAPI, null, 2)
      );
      
      // Run validation
      const result = execSync(
        `node ${scriptsDir}/validate-governance.js --asyncapi --path=${testDir}/docs`,
        { encoding: 'utf8', cwd: __dirname }
      );
      
      expect(result).toContain('✓ test.asyncapi.yaml');
    });
    
    it('should fail validation for AsyncAPI missing required fields', () => {
      // Create invalid AsyncAPI contract
      const invalidAsyncAPI = {
        asyncapi: '2.0.0',
        info: {
          title: 'Test Events'
          // Missing version
        }
        // Missing channels
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/contracts/events/invalid.asyncapi.yaml'),
        JSON.stringify(invalidAsyncAPI, null, 2)
      );
      
      // Run validation and expect failure
      expect(() => {
        execSync(
          `node ${scriptsDir}/validate-governance.js --asyncapi --path=${testDir}/docs`,
          { encoding: 'utf8', cwd: __dirname }
        );
      }).toThrow();
    });
  });

  describe('Documentation Synchronization', () => {
    it('should pass when service references existing contracts', () => {
      // Create contract file
      const contract = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: { '/test': { get: { responses: { '200': { description: 'OK' } } } } }
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/contracts/http/test.openapi.yaml'),
        JSON.stringify(contract, null, 2)
      );
      
      // Create service that references the contract
      const service = {
        name: 'test-service',
        purpose: 'Test service',
        owner: 'Test Team @test-oncall',
        health: '/healthz',
        openapi: '../contracts/http/test.openapi.yaml',
        runbook: '../runbooks/test-service.md'
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/test-service.yaml'),
        JSON.stringify(service, null, 2)
      );
      
      // Run synchronization check
      const result = execSync(
        `node ${scriptsDir}/validate-governance.js --sync --path=${testDir}/docs`,
        { encoding: 'utf8', cwd: __dirname }
      );
      
      expect(result).toContain('✓ All service-contract references are valid');
    });
    
    it('should fail when service references non-existent contract', () => {
      // Create service that references non-existent contract
      const service = {
        name: 'test-service',
        purpose: 'Test service',
        owner: 'Test Team @test-oncall',
        health: '/healthz',
        openapi: '../contracts/http/nonexistent.openapi.yaml',
        runbook: '../runbooks/test-service.md'
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/test-service.yaml'),
        JSON.stringify(service, null, 2)
      );
      
      // Run synchronization check and expect failure
      let failed = false;
      try {
        execSync(
          `node ${scriptsDir}/validate-governance.js --sync --path=${testDir}/docs`,
          { encoding: 'utf8', cwd: __dirname }
        );
      } catch (error) {
        failed = true;
        expect(error.stdout || error.message).toContain('Referenced OpenAPI contract not found');
      }
      expect(failed).toBe(true);
    });
  });

  describe('Orphaned Contract Detection', () => {
    it('should detect orphaned contracts', () => {
      // Create contract file without corresponding service reference
      const contract = {
        openapi: '3.0.0',
        info: { title: 'Orphaned API', version: '1.0.0' },
        paths: { '/orphaned': { get: { responses: { '200': { description: 'OK' } } } } }
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/contracts/http/orphaned.openapi.yaml'),
        JSON.stringify(contract, null, 2)
      );
      
      // Run orphan check and expect it to detect orphans
      let result;
      try {
        result = execSync(
          `node ${scriptsDir}/validate-governance.js --orphans --path=${testDir}/docs`,
          { encoding: 'utf8', cwd: __dirname }
        );
      } catch (error) {
        // Orphan detection should fail (exit code 1) when orphans are found
        result = error.stdout || '';
      }
      
      expect(result).toContain('⚠ Orphaned HTTP contract: orphaned.openapi.yaml');
    });
    
    it('should pass when no orphaned contracts exist', () => {
      // Create contract and corresponding service reference
      const contract = {
        openapi: '3.0.0',
        info: { title: 'Referenced API', version: '1.0.0' },
        paths: { '/referenced': { get: { responses: { '200': { description: 'OK' } } } } }
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/contracts/http/referenced.openapi.yaml'),
        JSON.stringify(contract, null, 2)
      );
      
      const service = {
        name: 'test-service',
        purpose: 'Test service',
        owner: 'Test Team @test-oncall',
        health: '/healthz',
        openapi: '../contracts/http/referenced.openapi.yaml',
        runbook: '../runbooks/test-service.md'
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/test-service.yaml'),
        JSON.stringify(service, null, 2)
      );
      
      // Run orphan check
      const result = execSync(
        `node ${scriptsDir}/validate-governance.js --orphans --path=${testDir}/docs`,
        { encoding: 'utf8', cwd: __dirname }
      );
      
      expect(result).toContain('✓ No orphaned contracts found');
    });
  });

  describe('Comprehensive CI Scenarios', () => {
    it('should validate complete governance setup', () => {
      // Create complete governance setup
      
      // Service catalog
      const service = {
        name: 'complete-service',
        purpose: 'Complete test service',
        owner: 'Test Team @test-oncall',
        health: '/healthz',
        openapi: '../contracts/http/complete.openapi.yaml',
        asyncapi: '../contracts/events/complete.asyncapi.yaml',
        depends_on: ['dependency-service'],
        runbook: '../runbooks/complete-service.md'
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/complete-service.yaml'),
        JSON.stringify(service, null, 2)
      );
      
      // OpenAPI contract
      const openapi = {
        openapi: '3.0.0',
        info: { title: 'Complete API', version: '1.0.0' },
        paths: {
          '/complete': {
            get: { responses: { '200': { description: 'OK' } } },
            post: { responses: { '201': { description: 'Created' } } }
          }
        }
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/contracts/http/complete.openapi.yaml'),
        JSON.stringify(openapi, null, 2)
      );
      
      // AsyncAPI contract
      const asyncapi = {
        asyncapi: '2.0.0',
        info: { title: 'Complete Events', version: '1.0.0' },
        channels: {
          'complete/events': {
            subscribe: {
              message: { payload: { type: 'object' } }
            }
          }
        }
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/contracts/events/complete.asyncapi.yaml'),
        JSON.stringify(asyncapi, null, 2)
      );
      
      // Run all validations
      const catalogResult = execSync(
        `node ${scriptsDir}/validate-governance.js --catalog --path=${testDir}/docs`,
        { encoding: 'utf8', cwd: __dirname }
      );
      
      const openapiResult = execSync(
        `node ${scriptsDir}/validate-governance.js --openapi --path=${testDir}/docs`,
        { encoding: 'utf8', cwd: __dirname }
      );
      
      const asyncapiResult = execSync(
        `node ${scriptsDir}/validate-governance.js --asyncapi --path=${testDir}/docs`,
        { encoding: 'utf8', cwd: __dirname }
      );
      
      const syncResult = execSync(
        `node ${scriptsDir}/validate-governance.js --sync --path=${testDir}/docs`,
        { encoding: 'utf8', cwd: __dirname }
      );
      
      const orphansResult = execSync(
        `node ${scriptsDir}/validate-governance.js --orphans --path=${testDir}/docs`,
        { encoding: 'utf8', cwd: __dirname }
      );
      
      expect(catalogResult).toContain('✓ complete-service.yaml');
      expect(openapiResult).toContain('✓ complete.openapi.yaml');
      expect(asyncapiResult).toContain('✓ complete.asyncapi.yaml');
      expect(syncResult).toContain('✓ All service-contract references are valid');
      expect(orphansResult).toContain('✓ No orphaned contracts found');
    });
  });
});
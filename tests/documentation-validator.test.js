import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import DocumentationValidator from '../scripts/documentation-validator.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('Documentation Validator', () => {
  let tempDir;
  let docsDir;
  let validator;

  beforeEach(() => {
    // Create temporary directories for testing
    tempDir = path.join(__dirname, 'temp-doc-test');
    docsDir = path.join(tempDir, 'docs');
    
    // Clean up and create directories
    if (fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true });
    }
    
    fs.mkdirSync(path.join(docsDir, 'services'), { recursive: true });
    fs.mkdirSync(path.join(docsDir, 'contracts', 'http'), { recursive: true });
    fs.mkdirSync(path.join(docsDir, 'contracts', 'events'), { recursive: true });
    fs.mkdirSync(path.join(docsDir, 'dependencies'), { recursive: true });
    fs.mkdirSync(path.join(docsDir, 'runbooks'), { recursive: true });
    fs.mkdirSync(path.join(docsDir, 'architecture'), { recursive: true });

    validator = new DocumentationValidator(docsDir);
  });

  afterEach(() => {
    // Clean up
    if (fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true });
    }
  });

  describe('Documentation Loading', () => {
    it('should load all documentation components', () => {
      // Create test files
      fs.writeFileSync(
        path.join(docsDir, 'services', 'test-service.yaml'),
        `name: test-service
purpose: Test service
owner: Test Team
health: /health
openapi: ../contracts/http/test-service.openapi.yaml
runbook: ../runbooks/test-service.md`
      );

      fs.writeFileSync(
        path.join(docsDir, 'contracts', 'http', 'test-service.openapi.yaml'),
        'openapi: 3.0.0\ninfo:\n  title: Test Service\n  version: 1.0.0'
      );

      fs.writeFileSync(
        path.join(docsDir, 'runbooks', 'test-service.md'),
        '# Test Service Runbook\n\nTroubleshooting guide...'
      );

      fs.writeFileSync(
        path.join(docsDir, 'architecture', 'l2.mmd'),
        'graph TD\n    test_service["test-service<br/>Test service"]'
      );

      validator.loadAllDocumentation();

      expect(validator.services.size).toBe(1);
      expect(validator.contracts.size).toBe(1);
      expect(validator.runbooks.size).toBe(1);
      expect(validator.architectureDiagrams.size).toBe(1);
    });

    it('should handle missing directories gracefully', () => {
      // Remove some directories
      fs.rmSync(path.join(docsDir, 'dependencies'), { recursive: true });
      fs.rmSync(path.join(docsDir, 'runbooks'), { recursive: true });

      validator.loadAllDocumentation();

      expect(validator.services.size).toBe(0);
      expect(validator.contracts.size).toBe(0);
      expect(validator.dependencies.size).toBe(0);
      expect(validator.runbooks.size).toBe(0);
    });
  });

  describe('Service Cross-Reference Validation', () => {
    beforeEach(() => {
      // Create base service
      fs.writeFileSync(
        path.join(docsDir, 'services', 'test-service.yaml'),
        `name: test-service
purpose: Test service
owner: Test Team
health: /health
openapi: ../contracts/http/test-service.openapi.yaml
runbook: ../runbooks/test-service.md
depends_on:
  - dependency-service`
      );

      validator.loadAllDocumentation();
    });

    it('should detect missing OpenAPI references', () => {
      validator.validateServiceCrossReferences();

      const errors = validator.validationResults.filter(r => r.level === 'error');
      expect(errors.some(e => e.message.includes('OpenAPI reference not found'))).toBe(true);
    });

    it('should detect missing runbook references', () => {
      validator.validateServiceCrossReferences();

      const errors = validator.validationResults.filter(r => r.level === 'error');
      expect(errors.some(e => e.message.includes('Runbook reference not found'))).toBe(true);
    });

    it('should detect missing service dependencies', () => {
      validator.validateServiceCrossReferences();

      const errors = validator.validationResults.filter(r => r.level === 'error');
      expect(errors.some(e => e.message.includes('Service dependency not found: dependency-service'))).toBe(true);
    });

    it('should validate correct references', () => {
      // Create the referenced files
      fs.writeFileSync(
        path.join(docsDir, 'contracts', 'http', 'test-service.openapi.yaml'),
        'openapi: 3.0.0\ninfo:\n  title: Test Service\n  version: 1.0.0'
      );

      fs.writeFileSync(
        path.join(docsDir, 'runbooks', 'test-service.md'),
        '# Test Service Runbook'
      );

      fs.writeFileSync(
        path.join(docsDir, 'services', 'dependency-service.yaml'),
        `name: dependency-service
purpose: Dependency service
owner: Test Team
health: /health
runbook: ../runbooks/dependency-service.md`
      );

      fs.writeFileSync(
        path.join(docsDir, 'runbooks', 'dependency-service.md'),
        '# Dependency Service Runbook'
      );

      validator.loadAllDocumentation();
      validator.validateServiceCrossReferences();

      const errors = validator.validationResults.filter(r => r.level === 'error');
      expect(errors.length).toBe(0);
    });
  });

  describe('Dependency Cross-Reference Validation', () => {
    beforeEach(() => {
      // Create services
      fs.writeFileSync(
        path.join(docsDir, 'services', 'service-a.yaml'),
        `name: service-a
purpose: Service A
owner: Team A
health: /health
runbook: ../runbooks/service-a.md`
      );

      fs.writeFileSync(
        path.join(docsDir, 'services', 'service-b.yaml'),
        `name: service-b
purpose: Service B
owner: Team B
health: /health
runbook: ../runbooks/service-b.md`
      );

      // Create dependency
      fs.writeFileSync(
        path.join(docsDir, 'dependencies', 'test-dependency.yaml'),
        `from: service-a POST /api/test
to:
  endpoint: service-b GET /api/test
  contract:
    openapi_ref: ../contracts/http/service-b.openapi.yaml`
      );

      validator.loadAllDocumentation();
    });

    it('should validate service references in dependencies', () => {
      // Create the referenced contract file
      fs.writeFileSync(
        path.join(docsDir, 'contracts', 'http', 'service-b.openapi.yaml'),
        'openapi: 3.0.0\ninfo:\n  title: Service B\n  version: 1.0.0'
      );

      validator.loadAllDocumentation();
      validator.validateDependencyCrossReferences();

      const errors = validator.validationResults.filter(r => r.level === 'error');
      expect(errors.length).toBe(0);
    });

    it('should detect missing services in dependencies', () => {
      // Create dependency with missing service
      fs.writeFileSync(
        path.join(docsDir, 'dependencies', 'missing-service.yaml'),
        `from: missing-service POST /api/test
to:
  endpoint: another-missing GET /api/test`
      );

      validator.loadAllDocumentation();
      validator.validateDependencyCrossReferences();

      const errors = validator.validationResults.filter(r => r.level === 'error');
      expect(errors.some(e => e.message.includes('Source service not found in catalog: missing-service'))).toBe(true);
      expect(errors.some(e => e.message.includes('Target service not found in catalog: another-missing'))).toBe(true);
    });

    it('should detect missing contract references', () => {
      validator.validateDependencyCrossReferences();

      const errors = validator.validationResults.filter(r => r.level === 'error');
      expect(errors.some(e => e.message.includes('Contract reference not found: service-b'))).toBe(true);
    });
  });

  describe('Architecture Diagram Validation', () => {
    beforeEach(() => {
      // Create services
      fs.writeFileSync(
        path.join(docsDir, 'services', 'service-a.yaml'),
        `name: service-a
purpose: Service A
owner: Team A
health: /health
runbook: ../runbooks/service-a.md`
      );

      fs.writeFileSync(
        path.join(docsDir, 'services', 'service-b.yaml'),
        `name: service-b
purpose: Service B
owner: Team B
health: /health
runbook: ../runbooks/service-b.md`
      );

      validator.loadAllDocumentation();
    });

    it('should detect missing L2 diagram', () => {
      validator.validateArchitectureDiagramConsistency();

      const errors = validator.validationResults.filter(r => r.level === 'error');
      expect(errors.some(e => e.message.includes('L2 architecture diagram not found'))).toBe(true);
    });

    it('should detect services missing from diagram', () => {
      // Create diagram without all services
      fs.writeFileSync(
        path.join(docsDir, 'architecture', 'l2.mmd'),
        'graph TD\n    service_a["service-a<br/>Service A"]'
      );

      validator.validateArchitectureDiagramConsistency();

      const warnings = validator.validationResults.filter(r => r.level === 'warning');
      expect(warnings.some(w => w.message.includes('Service not found in L2 diagram: service-b'))).toBe(true);
    });

    it('should validate complete diagram', () => {
      // Create complete diagram
      fs.writeFileSync(
        path.join(docsDir, 'architecture', 'l2.mmd'),
        `graph TD
    service_a["service-a<br/>Service A"]
    service_b["service-b<br/>Service B"]
    service_a --> service_b`
      );

      validator.validateArchitectureDiagramConsistency();

      const warnings = validator.validationResults.filter(r => 
        r.level === 'warning' && r.message.includes('Service not found in L2 diagram')
      );
      expect(warnings.length).toBe(0);
    });
  });

  describe('Documentation Completeness Validation', () => {
    it('should detect missing required fields', () => {
      fs.writeFileSync(
        path.join(docsDir, 'services', 'incomplete-service.yaml'),
        `name: incomplete-service
purpose: Incomplete service`
        // Missing owner, health, runbook
      );

      validator.loadAllDocumentation();
      validator.validateDocumentationCompleteness();

      const errors = validator.validationResults.filter(r => r.level === 'error');
      expect(errors.some(e => e.message.includes('Missing required field: owner'))).toBe(true);
      expect(errors.some(e => e.message.includes('Missing required field: health'))).toBe(true);
      expect(errors.some(e => e.message.includes('Missing required field: runbook'))).toBe(true);
    });

    it('should detect services without API documentation', () => {
      fs.writeFileSync(
        path.join(docsDir, 'services', 'no-api-service.yaml'),
        `name: no-api-service
purpose: Service without API docs
owner: Team
health: /health
runbook: ../runbooks/no-api-service.md`
      );

      validator.loadAllDocumentation();
      validator.validateDocumentationCompleteness();

      const warnings = validator.validationResults.filter(r => r.level === 'warning');
      expect(warnings.some(w => w.message.includes('Service has no API documentation'))).toBe(true);
    });

    it('should detect orphaned contracts', () => {
      fs.writeFileSync(
        path.join(docsDir, 'contracts', 'http', 'orphaned-contract.openapi.yaml'),
        'openapi: 3.0.0\ninfo:\n  title: Orphaned Contract\n  version: 1.0.0'
      );

      validator.loadAllDocumentation();
      validator.validateDocumentationCompleteness();

      const warnings = validator.validationResults.filter(r => r.level === 'warning');
      expect(warnings.some(w => w.message.includes('Orphaned contract (no corresponding service): orphaned-contract'))).toBe(true);
    });
  });

  describe('Validation Report Generation', () => {
    it('should generate comprehensive validation report', () => {
      // Create minimal test data
      fs.writeFileSync(
        path.join(docsDir, 'services', 'test-service.yaml'),
        `name: test-service
purpose: Test service
owner: Test Team
health: /health
runbook: ../runbooks/test-service.md`
      );

      const result = validator.validate();

      expect(result).toBeDefined();
      expect(result.valid).toBeDefined();
      expect(result.errors).toBeDefined();
      expect(result.warnings).toBeDefined();
      expect(result.infos).toBeDefined();
      expect(result.reportPath).toBeDefined();
      expect(result.stats).toBeDefined();

      // Check that report file was created
      expect(fs.existsSync(result.reportPath)).toBe(true);

      const reportContent = fs.readFileSync(result.reportPath, 'utf8');
      expect(reportContent).toContain('# Comprehensive Documentation Validation Report');
      expect(reportContent).toContain('## Summary');
      expect(reportContent).toContain('## Documentation Statistics');
    });
  });

  describe('Utility Functions', () => {
    it('should extract service names from endpoints', () => {
      expect(validator.extractServiceName('service-a POST /api/test')).toBe('service-a');
      expect(validator.extractServiceName('user-service GET /users/123')).toBe('user-service');
    });

    it('should extract target services from to field', () => {
      const singleTarget = { endpoint: 'service-b GET /api/test' };
      expect(validator.extractToServices(singleTarget)).toEqual(['service-b']);

      const multipleTargets = [
        { endpoint: 'service-b GET /api/test' },
        { endpoint: 'service-c POST /api/data' }
      ];
      expect(validator.extractToServices(multipleTargets)).toEqual(['service-b', 'service-c']);
    });

    it('should resolve relative paths correctly', () => {
      const basePath = '/docs/services/test-service.yaml';
      const relativePath = '../contracts/http/test-service.openapi.yaml';
      const resolved = validator.resolveRelativePath(basePath, relativePath);
      
      expect(resolved).toContain('contracts/http/test-service.openapi.yaml');
    });
  });
});
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import GovernanceValidator from '../scripts/validate-governance.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('YAML File Validation', () => {
  let validator;
  let testDir;

  beforeEach(() => {
    validator = new GovernanceValidator();
    testDir = path.join(__dirname, 'temp-test-files');
    
    // Create test directory
    if (!fs.existsSync(testDir)) {
      fs.mkdirSync(testDir, { recursive: true });
    }
  });

  afterEach(() => {
    // Clean up test files
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true, force: true });
    }
  });

  describe('validateYamlFile method', () => {
    it('should validate a valid YAML file with service catalog schema', () => {
      const validYaml = `name: test-service
purpose: Test service for validation
owner: Alice @oncall-123
health: /healthz
runbook: ../runbooks/test.md`;

      const testFile = path.join(testDir, 'valid-service.yaml');
      fs.writeFileSync(testFile, validYaml);

      const result = validator.validateYamlFile(testFile, 'serviceCatalog');
      expect(result.valid).toBe(true);
      expect(result.errors).toEqual([]);
    });

    it('should reject invalid YAML file with missing required fields', () => {
      const invalidYaml = `name: test-service
purpose: Test service for validation
# missing owner, health, and runbook`;

      const testFile = path.join(testDir, 'invalid-service.yaml');
      fs.writeFileSync(testFile, invalidYaml);

      const result = validator.validateYamlFile(testFile, 'serviceCatalog');
      expect(result.valid).toBe(false);
      expect(result.errors).toHaveLength(3);
      expect(result.errors.some(err => err.includes("must have required property 'owner'"))).toBe(true);
      expect(result.errors.some(err => err.includes("must have required property 'health'"))).toBe(true);
      expect(result.errors.some(err => err.includes("must have required property 'runbook'"))).toBe(true);
    });

    it('should handle malformed YAML gracefully', () => {
      const malformedYaml = `name: test-service
purpose: Test service
owner: Alice
  invalid: indentation
health: /healthz
runbook: test.md`;

      const testFile = path.join(testDir, 'malformed.yaml');
      fs.writeFileSync(testFile, malformedYaml);

      const result = validator.validateYamlFile(testFile, 'serviceCatalog');
      expect(result.valid).toBe(false);
      expect(result.errors).toHaveLength(1);
      expect(result.errors[0]).toContain('YAML parsing error');
    });

    it('should handle non-existent files gracefully', () => {
      const nonExistentFile = path.join(testDir, 'does-not-exist.yaml');

      const result = validator.validateYamlFile(nonExistentFile, 'serviceCatalog');
      expect(result.valid).toBe(false);
      expect(result.errors).toHaveLength(1);
      expect(result.errors[0]).toContain('File not found');
    });

    it('should handle unknown schema types gracefully', () => {
      const validYaml = `name: test-service
purpose: Test service
owner: Alice @oncall-123
health: /healthz
runbook: ../runbooks/test.md`;

      const testFile = path.join(testDir, 'valid-service.yaml');
      fs.writeFileSync(testFile, validYaml);

      const result = validator.validateYamlFile(testFile, 'unknownSchema');
      expect(result.valid).toBe(false);
      expect(result.errors).toHaveLength(1);
      expect(result.errors[0]).toContain('Unknown schema type');
    });

    it('should validate complex service catalog with all optional fields', () => {
      const complexYaml = `name: canteen-service
purpose: 做菜
owner: Alice @oncall-123
health: /api/v1/health/status
openapi: ../contracts/http/canteen.openapi.yaml
asyncapi: ../contracts/events/canteen.asyncapi.yaml
depends_on:
  - butcher
  - pantry
  - inventory-service
runbook: ../runbooks/canteen.md`;

      const testFile = path.join(testDir, 'complex-service.yaml');
      fs.writeFileSync(testFile, complexYaml);

      const result = validator.validateYamlFile(testFile, 'serviceCatalog');
      expect(result.valid).toBe(true);
      expect(result.errors).toEqual([]);
    });

    it('should reject YAML with invalid field formats', () => {
      const invalidFormatYaml = `name: Invalid-Service-Name
purpose: ""
owner: Alice @oncall-123
health: healthz
runbook: ../runbooks/test.txt`;

      const testFile = path.join(testDir, 'invalid-format.yaml');
      fs.writeFileSync(testFile, invalidFormatYaml);

      const result = validator.validateYamlFile(testFile, 'serviceCatalog');
      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
      expect(result.errors.some(err => err.includes('must match pattern'))).toBe(true);
    });

    it('should handle empty YAML files', () => {
      const emptyYaml = '';

      const testFile = path.join(testDir, 'empty.yaml');
      fs.writeFileSync(testFile, emptyYaml);

      const result = validator.validateYamlFile(testFile, 'serviceCatalog');
      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
    });

    it('should handle YAML files with only comments', () => {
      const commentOnlyYaml = `# This is a comment
# Another comment
# No actual content`;

      const testFile = path.join(testDir, 'comments-only.yaml');
      fs.writeFileSync(testFile, commentOnlyYaml);

      const result = validator.validateYamlFile(testFile, 'serviceCatalog');
      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
    });
  });

  describe('File extension handling', () => {
    it('should validate .yml files', () => {
      const validYaml = `name: test-service
purpose: Test service for validation
owner: Alice @oncall-123
health: /healthz
runbook: ../runbooks/test.md`;

      const testFile = path.join(testDir, 'valid-service.yml');
      fs.writeFileSync(testFile, validYaml);

      const result = validator.validateYamlFile(testFile, 'serviceCatalog');
      expect(result.valid).toBe(true);
      expect(result.errors).toEqual([]);
    });

    it('should handle files with special characters in names', () => {
      const validYaml = `name: test-service
purpose: Test service for validation
owner: Alice @oncall-123
health: /healthz
runbook: ../runbooks/test.md`;

      const testFile = path.join(testDir, 'test-service_v1.2.yaml');
      fs.writeFileSync(testFile, validYaml);

      const result = validator.validateYamlFile(testFile, 'serviceCatalog');
      expect(result.valid).toBe(true);
      expect(result.errors).toEqual([]);
    });
  });

  describe('Error message formatting', () => {
    it('should provide detailed error messages with field paths', () => {
      const invalidYaml = `name: test-service
purpose: Test service
owner: ""
health: /healthz
depends_on:
  - invalid-Service-Name
runbook: ../runbooks/test.md`;

      const testFile = path.join(testDir, 'detailed-errors.yaml');
      fs.writeFileSync(testFile, invalidYaml);

      const result = validator.validateYamlFile(testFile, 'serviceCatalog');
      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
      
      // Check that error messages include field paths
      const hasOwnerError = result.errors.some(err => err.includes('/owner'));
      const hasDependsOnError = result.errors.some(err => err.includes('/depends_on'));
      
      expect(hasOwnerError || hasDependsOnError).toBe(true);
    });
  });
});
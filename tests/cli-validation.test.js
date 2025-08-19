import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import GovernanceValidator from '../scripts/validate-governance.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('CLI Validation Tool', () => {
  let validator;
  let testDir;

  beforeEach(() => {
    validator = new GovernanceValidator();
    testDir = path.join(__dirname, 'temp-cli-test');
    
    // Create test directory structure
    if (!fs.existsSync(testDir)) {
      fs.mkdirSync(testDir, { recursive: true });
    }
    
    const servicesDir = path.join(testDir, 'services');
    if (!fs.existsSync(servicesDir)) {
      fs.mkdirSync(servicesDir, { recursive: true });
    }
  });

  afterEach(() => {
    // Clean up test files
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true, force: true });
    }
  });

  describe('Batch Validation', () => {
    it('should validate multiple service catalog files', () => {
      // Create valid service files
      const validService1 = `name: service-one
purpose: First test service
owner: Team A @team-a-oncall
health: /health
runbook: ../runbooks/service-one.md`;

      const validService2 = `name: service-two
purpose: Second test service
owner: Team B @team-b-oncall
health: /healthz
depends_on:
  - service-one
runbook: ../runbooks/service-two.md`;

      fs.writeFileSync(path.join(testDir, 'services', 'service-one.yaml'), validService1);
      fs.writeFileSync(path.join(testDir, 'services', 'service-two.yaml'), validService2);

      const result = validator.validateServiceCatalog(path.join(testDir, 'services'));
      expect(result).toBe(true);
    });

    it('should handle mixed valid and invalid files', () => {
      // Create one valid and one invalid service file
      const validService = `name: valid-service
purpose: Valid test service
owner: Team A @team-a-oncall
health: /health
runbook: ../runbooks/valid-service.md`;

      const invalidService = `name: invalid-service
purpose: Invalid test service
# missing owner, health, and runbook`;

      fs.writeFileSync(path.join(testDir, 'services', 'valid-service.yaml'), validService);
      fs.writeFileSync(path.join(testDir, 'services', 'invalid-service.yaml'), invalidService);

      const result = validator.validateServiceCatalog(path.join(testDir, 'services'));
      expect(result).toBe(false);
    });

    it('should handle empty services directory', () => {
      const result = validator.validateServiceCatalog(path.join(testDir, 'services'));
      expect(result).toBe(true); // Empty directory should not be an error
    });

    it('should handle non-existent services directory', () => {
      const result = validator.validateServiceCatalog(path.join(testDir, 'non-existent'));
      expect(result).toBe(true); // Non-existent directory should not be an error
    });
  });

  describe('Error Reporting', () => {
    it('should group errors by type', () => {
      const detailedErrors = [
        { file: 'service1.yaml', error: "root: must have required property 'name'" },
        { file: 'service2.yaml', error: "root: must have required property 'owner'" },
        { file: 'service3.yaml', error: "/name: must match pattern" },
        { file: 'service4.yaml', error: "/health: must match pattern" },
        { file: 'service5.yaml', error: "YAML parsing error: invalid syntax" }
      ];

      const grouped = validator.groupErrorsByType(detailedErrors);
      
      expect(grouped['Missing Required Fields']).toHaveLength(2);
      expect(grouped['Invalid Format']).toHaveLength(2);
      expect(grouped['YAML Syntax Errors']).toHaveLength(1);
    });

    it('should categorize different error types correctly', () => {
      const detailedErrors = [
        { file: 'test.yaml', error: "root: must have required property 'name'" },
        { file: 'test.yaml', error: "/name: must match pattern" },
        { file: 'test.yaml', error: "YAML parsing error: bad indentation" },
        { file: 'test.yaml', error: "root: must NOT have additional properties" },
        { file: 'test.yaml', error: "/owner: must be string" },
        { file: 'test.yaml', error: "/purpose: must NOT have fewer than 1 characters" },
        { file: 'test.yaml', error: "/purpose: must NOT have more than 200 characters" },
        { file: 'test.yaml', error: "/depends_on: must NOT have duplicate items" },
        { file: 'test.yaml', error: "Unknown error type" }
      ];

      const grouped = validator.groupErrorsByType(detailedErrors);
      
      expect(grouped['Missing Required Fields']).toHaveLength(1);
      expect(grouped['Invalid Format']).toHaveLength(1);
      expect(grouped['YAML Syntax Errors']).toHaveLength(1);
      expect(grouped['Extra Fields']).toHaveLength(1);
      expect(grouped['Type Errors']).toHaveLength(1);
      expect(grouped['Empty Fields']).toHaveLength(1);
      expect(grouped['Field Too Long']).toHaveLength(1);
      expect(grouped['Duplicate Values']).toHaveLength(1);
      expect(grouped['Other']).toHaveLength(1);
    });
  });

  describe('File Filtering', () => {
    it('should only validate YAML files', () => {
      // Create various file types
      fs.writeFileSync(path.join(testDir, 'services', 'service.yaml'), 'name: test\npurpose: test\nowner: test\nhealth: /health\nrunbook: test.md');
      fs.writeFileSync(path.join(testDir, 'services', 'service.yml'), 'name: test2\npurpose: test\nowner: test\nhealth: /health\nrunbook: test.md');
      fs.writeFileSync(path.join(testDir, 'services', 'readme.txt'), 'This is not a YAML file');
      fs.writeFileSync(path.join(testDir, 'services', 'config.json'), '{"not": "yaml"}');
      fs.writeFileSync(path.join(testDir, 'services', '.hidden.yaml'), 'name: hidden\npurpose: test\nowner: test\nhealth: /health\nrunbook: test.md');

      const result = validator.validateServiceCatalog(path.join(testDir, 'services'));
      expect(result).toBe(true); // Should only validate the 2 YAML files and ignore others
    });
  });

  describe('Detailed Error Information', () => {
    it('should provide file path and line information in errors', () => {
      const invalidService = `name: test-service
purpose: ""
owner: Test Team
health: invalid-health
runbook: invalid.txt`;

      fs.writeFileSync(path.join(testDir, 'services', 'invalid.yaml'), invalidService);

      const result = validator.validateYamlFile(path.join(testDir, 'services', 'invalid.yaml'), 'serviceCatalog');
      
      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
      
      // Check that errors contain field path information
      const hasFieldPathError = result.errors.some(error => error.includes('/'));
      expect(hasFieldPathError).toBe(true);
    });

    it('should handle malformed YAML with descriptive errors', () => {
      const malformedYaml = `name: test-service
purpose: Test service
owner: Test Team
  invalid: indentation
health: /health`;

      fs.writeFileSync(path.join(testDir, 'services', 'malformed.yaml'), malformedYaml);

      const result = validator.validateYamlFile(path.join(testDir, 'services', 'malformed.yaml'), 'serviceCatalog');
      
      expect(result.valid).toBe(false);
      expect(result.errors).toHaveLength(1);
      expect(result.errors[0]).toContain('YAML parsing error');
    });
  });

  describe('Performance with Large Datasets', () => {
    it('should handle validation of many service files efficiently', () => {
      const startTime = Date.now();
      
      // Create 50 service files
      for (let i = 1; i <= 50; i++) {
        const serviceContent = `name: service-${i.toString().padStart(3, '0')}
purpose: Test service number ${i}
owner: Team ${i % 5 + 1} @team-${i % 5 + 1}-oncall
health: /health
runbook: ../runbooks/service-${i.toString().padStart(3, '0')}.md`;

        fs.writeFileSync(path.join(testDir, 'services', `service-${i.toString().padStart(3, '0')}.yaml`), serviceContent);
      }

      const result = validator.validateServiceCatalog(path.join(testDir, 'services'));
      const endTime = Date.now();
      
      expect(result).toBe(true);
      expect(endTime - startTime).toBeLessThan(5000); // Should complete within 5 seconds
    });
  });

  describe('Edge Cases', () => {
    it('should handle files with Unicode characters', () => {
      const unicodeService = `name: unicode-service
purpose: 测试服务 with émojis 🚀
owner: 国际团队 @international-oncall
health: /health
runbook: ../runbooks/unicode-service.md`;

      fs.writeFileSync(path.join(testDir, 'services', 'unicode.yaml'), unicodeService);

      const result = validator.validateServiceCatalog(path.join(testDir, 'services'));
      expect(result).toBe(true); // Should pass - Unicode is allowed in purpose and owner fields
    });

    it('should handle very long file names', () => {
      const longFileName = 'a'.repeat(100) + '.yaml';
      const validService = `name: long-filename-service
purpose: Service with very long filename
owner: Test Team @test-oncall
health: /health
runbook: ../runbooks/long-filename-service.md`;

      fs.writeFileSync(path.join(testDir, 'services', longFileName), validService);

      const result = validator.validateServiceCatalog(path.join(testDir, 'services'));
      expect(result).toBe(true);
    });

    it('should handle empty YAML files', () => {
      fs.writeFileSync(path.join(testDir, 'services', 'empty.yaml'), '');

      const result = validator.validateServiceCatalog(path.join(testDir, 'services'));
      expect(result).toBe(false); // Empty file should fail validation
    });

    it('should handle YAML files with only comments', () => {
      const commentOnlyYaml = `# This is a service catalog file
# But it has no actual content
# Just comments`;

      fs.writeFileSync(path.join(testDir, 'services', 'comments-only.yaml'), commentOnlyYaml);

      const result = validator.validateServiceCatalog(path.join(testDir, 'services'));
      expect(result).toBe(false); // Comment-only file should fail validation
    });
  });
});
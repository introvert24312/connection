import { describe, it, expect, beforeEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import GovernanceValidator from '../scripts/validate-governance.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('Service Catalog Schema Validation', () => {
  let validator;

  beforeEach(() => {
    validator = new GovernanceValidator();
  });

  describe('Valid service catalog entries', () => {
    it('should validate a minimal valid service catalog entry', () => {
      const validService = {
        name: 'test-service',
        purpose: 'Test service for validation',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        runbook: '../runbooks/test-service.md'
      };

      const result = validator.schemas.serviceCatalog(validService);
      expect(result).toBe(true);
      expect(validator.schemas.serviceCatalog.errors).toBeNull();
    });

    it('should validate a complete service catalog entry with all optional fields', () => {
      const completeService = {
        name: 'canteen-service',
        purpose: '做菜',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        openapi: '../contracts/http/canteen.openapi.yaml',
        asyncapi: '../contracts/events/canteen.asyncapi.yaml',
        depends_on: ['butcher', 'pantry'],
        runbook: '../runbooks/canteen.md'
      };

      const result = validator.schemas.serviceCatalog(completeService);
      expect(result).toBe(true);
      expect(validator.schemas.serviceCatalog.errors).toBeNull();
    });

    it('should validate service with empty depends_on array', () => {
      const serviceWithEmptyDeps = {
        name: 'standalone-service',
        purpose: 'Standalone service with no dependencies',
        owner: 'Bob @oncall-456',
        health: '/health',
        depends_on: [],
        runbook: '../runbooks/standalone.md'
      };

      const result = validator.schemas.serviceCatalog(serviceWithEmptyDeps);
      expect(result).toBe(true);
      expect(validator.schemas.serviceCatalog.errors).toBeNull();
    });

    it('should validate service with complex health endpoint path', () => {
      const serviceWithComplexHealth = {
        name: 'api-gateway',
        purpose: 'API Gateway service',
        owner: 'Platform Team @oncall-789',
        health: '/api/v1/health/status',
        runbook: '../runbooks/api-gateway.md'
      };

      const result = validator.schemas.serviceCatalog(serviceWithComplexHealth);
      expect(result).toBe(true);
      expect(validator.schemas.serviceCatalog.errors).toBeNull();
    });
  });

  describe('Invalid service catalog entries - missing required fields', () => {
    it('should reject service missing name field', () => {
      const invalidService = {
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors).toHaveLength(1);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain("must have required property 'name'");
    });

    it('should reject service missing purpose field', () => {
      const invalidService = {
        name: 'test-service',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors).toHaveLength(1);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain("must have required property 'purpose'");
    });

    it('should reject service missing owner field', () => {
      const invalidService = {
        name: 'test-service',
        purpose: 'Test service',
        health: '/healthz',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors).toHaveLength(1);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain("must have required property 'owner'");
    });

    it('should reject service missing health field', () => {
      const invalidService = {
        name: 'test-service',
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors).toHaveLength(1);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain("must have required property 'health'");
    });

    it('should reject service missing runbook field', () => {
      const invalidService = {
        name: 'test-service',
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: '/healthz'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors).toHaveLength(1);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain("must have required property 'runbook'");
    });
  });

  describe('Invalid service catalog entries - field format validation', () => {
    it('should reject invalid service name format (uppercase)', () => {
      const invalidService = {
        name: 'Test-Service',
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must match pattern');
    });

    it('should reject invalid service name format (starts with number)', () => {
      const invalidService = {
        name: '1test-service',
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must match pattern');
    });

    it('should reject invalid service name format (ends with hyphen)', () => {
      const invalidService = {
        name: 'test-service-',
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must match pattern');
    });

    it('should reject empty purpose field', () => {
      const invalidService = {
        name: 'test-service',
        purpose: '',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must NOT have fewer than 1 characters');
    });

    it('should reject purpose field that is too long', () => {
      const invalidService = {
        name: 'test-service',
        purpose: 'A'.repeat(201), // 201 characters, exceeds maxLength of 200
        owner: 'Alice @oncall-123',
        health: '/healthz',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must NOT have more than 200 characters');
    });

    it('should reject empty owner field', () => {
      const invalidService = {
        name: 'test-service',
        purpose: 'Test service',
        owner: '',
        health: '/healthz',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must NOT have fewer than 1 characters');
    });

    it('should reject health endpoint not starting with /', () => {
      const invalidService = {
        name: 'test-service',
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: 'healthz',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must match pattern');
    });

    it('should reject openapi file without yaml/yml extension', () => {
      const invalidService = {
        name: 'test-service',
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        openapi: '../contracts/http/test.json',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must match pattern');
    });

    it('should reject asyncapi file without yaml/yml extension', () => {
      const invalidService = {
        name: 'test-service',
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        asyncapi: '../contracts/events/test.json',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must match pattern');
    });

    it('should reject runbook file without md/markdown extension', () => {
      const invalidService = {
        name: 'test-service',
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        runbook: '../runbooks/test.txt'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must match pattern');
    });
  });

  describe('Invalid service catalog entries - depends_on validation', () => {
    it('should reject depends_on with invalid service name format', () => {
      const invalidService = {
        name: 'test-service',
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        depends_on: ['valid-service', 'Invalid-Service'],
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must match pattern');
    });

    it('should reject depends_on with duplicate service names', () => {
      const invalidService = {
        name: 'test-service',
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        depends_on: ['service-a', 'service-b', 'service-a'],
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must NOT have duplicate items');
    });

    it('should reject depends_on with non-string items', () => {
      const invalidService = {
        name: 'test-service',
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        depends_on: ['service-a', 123, 'service-b'],
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must be string');
    });
  });

  describe('Invalid service catalog entries - additional properties', () => {
    it('should reject service with additional properties', () => {
      const invalidService = {
        name: 'test-service',
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        runbook: '../runbooks/test.md',
        extraField: 'not allowed'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must NOT have additional properties');
    });
  });

  describe('Edge cases', () => {
    it('should handle null values gracefully', () => {
      const invalidService = {
        name: null,
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must be string');
    });

    it('should handle undefined values gracefully', () => {
      const invalidService = {
        name: undefined,
        purpose: 'Test service',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        runbook: '../runbooks/test.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain("must have required property 'name'");
    });

    it('should validate minimal two character service name', () => {
      const validService = {
        name: 'ab',
        purpose: 'Minimal two character service name',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        runbook: '../runbooks/ab.md'
      };

      const result = validator.schemas.serviceCatalog(validService);
      expect(result).toBe(true);
      expect(validator.schemas.serviceCatalog.errors).toBeNull();
    });

    it('should reject single character service name', () => {
      const invalidService = {
        name: 'a',
        purpose: 'Single character service name',
        owner: 'Alice @oncall-123',
        health: '/healthz',
        runbook: '../runbooks/a.md'
      };

      const result = validator.schemas.serviceCatalog(invalidService);
      expect(result).toBe(false);
      expect(validator.schemas.serviceCatalog.errors[0].message).toContain('must match pattern');
    });
  });
});
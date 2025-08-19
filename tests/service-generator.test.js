import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import ServiceCatalogGenerator from '../scripts/generate-service-catalog.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('Service Catalog Generator', () => {
  let generator;
  let testDir;

  beforeEach(() => {
    generator = new ServiceCatalogGenerator();
    testDir = path.join(__dirname, 'temp-generator-test');
    
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

  describe('Service Detection', () => {
    it('should detect service classes in Swift files', async () => {
      const swiftContent = `
import Foundation

// MARK: - Test Service
class TestService: ObservableObject {
    func performAction() {
        // Implementation
    }
}`;

      const testFile = path.join(testDir, 'TestService.swift');
      fs.writeFileSync(testFile, swiftContent);

      const patterns = [
        { pattern: /class\s+(\w*Service)\s*:/, type: 'service' }
      ];

      await generator.scanDirectory(path.relative(generator.projectRoot, testDir), patterns, '.swift');
      
      expect(generator.services).toHaveLength(1);
      expect(generator.services[0].name).toBe('test-service');
      expect(generator.services[0]._metadata.originalName).toBe('TestService');
      expect(generator.services[0]._metadata.type).toBe('service');
    });

    it('should detect manager classes in Swift files', async () => {
      const swiftContent = `
import Foundation

class DataManager: ObservableObject {
    private let storage = UserDefaults.standard
}`;

      const testFile = path.join(testDir, 'DataManager.swift');
      fs.writeFileSync(testFile, swiftContent);

      const patterns = [
        { pattern: /class\s+(\w*Manager)\s*:/, type: 'manager' }
      ];

      await generator.scanDirectory(path.relative(generator.projectRoot, testDir), patterns, '.swift');
      
      expect(generator.services).toHaveLength(1);
      expect(generator.services[0].name).toBe('data-manager');
      expect(generator.services[0]._metadata.type).toBe('manager');
    });

    it('should extract purpose from MARK comments', async () => {
      const swiftContent = `import Foundation

// MARK: - Authentication Service
class AuthService: ObservableObject {
    func login() {}
}`;

      const testFile = path.join(testDir, 'AuthService.swift');
      fs.writeFileSync(testFile, swiftContent);

      const patterns = [
        { pattern: /class\s+(\w*Service)\s*:/, type: 'service' }
      ];

      await generator.scanDirectory(path.relative(generator.projectRoot, testDir), patterns, '.swift');
      
      expect(generator.services).toHaveLength(1);
      expect(generator.services[0].purpose).toBe('Authentication Service');
    });

    it('should extract dependencies from import statements', async () => {
      const swiftContent = `
import Foundation
import DataManager
import NetworkService

class TestService: ObservableObject {
    private let dataManager = DataManager.shared
    private let networkService = NetworkService()
}`;

      const testFile = path.join(testDir, 'TestService.swift');
      fs.writeFileSync(testFile, swiftContent);

      const patterns = [
        { pattern: /class\s+(\w*Service)\s*:/, type: 'service' }
      ];

      await generator.scanDirectory(path.relative(generator.projectRoot, testDir), patterns, '.swift');
      
      expect(generator.services).toHaveLength(1);
      expect(generator.services[0].depends_on).toContain('data-manager');
      expect(generator.services[0].depends_on).toContain('network-service');
    });
  });

  describe('YAML Generation', () => {
    it('should generate valid YAML for a service', () => {
      const service = {
        name: 'test-service',
        purpose: 'Test service for validation',
        owner: 'Test Team @test-oncall',
        health: '/health',
        depends_on: ['data-manager', 'auth-service'],
        runbook: '../runbooks/test-service.md'
      };

      const yaml = generator.generateServiceYaml(service);
      
      expect(yaml).toContain('name: test-service');
      expect(yaml).toContain('purpose: Test service for validation');
      expect(yaml).toContain('owner: Test Team @test-oncall');
      expect(yaml).toContain('health: /health');
      expect(yaml).toContain('depends_on:');
      expect(yaml).toContain('  - data-manager');
      expect(yaml).toContain('  - auth-service');
      expect(yaml).toContain('runbook: ../runbooks/test-service.md');
    });

    it('should generate YAML without depends_on when no dependencies', () => {
      const service = {
        name: 'standalone-service',
        purpose: 'Standalone service',
        owner: 'Test Team @test-oncall',
        health: '/health',
        depends_on: [],
        runbook: '../runbooks/standalone-service.md'
      };

      const yaml = generator.generateServiceYaml(service);
      
      expect(yaml).toContain('name: standalone-service');
      expect(yaml).not.toContain('depends_on:');
    });

    it('should include optional fields when present', () => {
      const service = {
        name: 'api-service',
        purpose: 'API service with contracts',
        owner: 'API Team @api-oncall',
        health: '/health',
        openapi: '../contracts/http/api-service.openapi.yaml',
        asyncapi: '../contracts/events/api-service.asyncapi.yaml',
        depends_on: [],
        runbook: '../runbooks/api-service.md'
      };

      const yaml = generator.generateServiceYaml(service);
      
      expect(yaml).toContain('openapi: ../contracts/http/api-service.openapi.yaml');
      expect(yaml).toContain('asyncapi: ../contracts/events/api-service.asyncapi.yaml');
    });
  });

  describe('String Sanitization', () => {
    it('should sanitize YAML strings with special characters', () => {
      const input = 'Test: "Service" with \\n newlines\\t and tabs';
      const sanitized = generator.sanitizeYamlString(input);
      
      expect(sanitized).toBe('Test Service with newlines and tabs');
      expect(sanitized).not.toContain(':');
      expect(sanitized).not.toContain('"');
      expect(sanitized).not.toContain('\\n');
      expect(sanitized).not.toContain('\\t');
    });

    it('should handle empty and null strings', () => {
      expect(generator.sanitizeYamlString('')).toBe('');
      expect(generator.sanitizeYamlString(null)).toBe(null);
      expect(generator.sanitizeYamlString(undefined)).toBe(undefined);
    });

    it('should normalize multiple spaces', () => {
      const input = 'Test    service   with    spaces';
      const sanitized = generator.sanitizeYamlString(input);
      
      expect(sanitized).toBe('Test service with spaces');
    });
  });

  describe('Utility Functions', () => {
    it('should convert PascalCase to kebab-case', () => {
      expect(generator.toKebabCase('TestService')).toBe('test-service');
      expect(generator.toKebabCase('DataManager')).toBe('data-manager');
      expect(generator.toKebabCase('APIGateway')).toBe('api-gateway');
      expect(generator.toKebabCase('HTTPClient')).toBe('http-client');
    });

    it('should handle single words', () => {
      expect(generator.toKebabCase('Service')).toBe('service');
      expect(generator.toKebabCase('service')).toBe('service');
    });

    it('should handle numbers in names', () => {
      expect(generator.toKebabCase('Service2')).toBe('service2');
      expect(generator.toKebabCase('V2Service')).toBe('v2-service');
    });
  });

  describe('Runbook Generation', () => {
    it('should generate comprehensive runbook content', () => {
      const service = {
        name: 'test-service',
        purpose: 'Test service for validation',
        owner: 'Test Team @test-oncall',
        health: '/health',
        depends_on: ['data-manager'],
        runbook: '../runbooks/test-service.md'
      };

      const runbook = generator.generateRunbookContent(service);
      
      expect(runbook).toContain('# test-service Runbook');
      expect(runbook).toContain('**Name:** test-service');
      expect(runbook).toContain('**Purpose:** Test service for validation');
      expect(runbook).toContain('**Owner:** Test Team @test-oncall');
      expect(runbook).toContain('**Health Check:** /health');
      expect(runbook).toContain('- data-manager');
      expect(runbook).toContain('## Common Issues');
      expect(runbook).toContain('## Monitoring');
      expect(runbook).toContain('## Escalation');
    });

    it('should handle services with no dependencies', () => {
      const service = {
        name: 'standalone-service',
        purpose: 'Standalone service',
        owner: 'Test Team @test-oncall',
        health: '/health',
        depends_on: [],
        runbook: '../runbooks/standalone-service.md'
      };

      const runbook = generator.generateRunbookContent(service);
      
      expect(runbook).toContain('No dependencies');
    });
  });

  describe('Error Handling', () => {
    it('should handle missing directories gracefully', async () => {
      const nonExistentDir = path.join(testDir, 'does-not-exist');
      
      const patterns = [
        { pattern: /class\s+(\w*Service)\s*:/, type: 'service' }
      ];

      // Should not throw an error
      await expect(
        generator.scanDirectory(path.relative(generator.projectRoot, nonExistentDir), patterns, '.swift')
      ).resolves.not.toThrow();
    });

    it('should handle malformed files gracefully', async () => {
      const malformedContent = 'This is not valid Swift code {{{';
      const testFile = path.join(testDir, 'Malformed.swift');
      fs.writeFileSync(testFile, malformedContent);

      const patterns = [
        { pattern: /class\s+(\w*Service)\s*:/, type: 'service' }
      ];

      // Should not throw an error and should not find any services
      await generator.scanDirectory(path.relative(generator.projectRoot, testDir), patterns, '.swift');
      
      // Should not have found any services in malformed file
      const malformedServices = generator.services.filter(s => s._metadata?.fileName === 'Malformed.swift');
      expect(malformedServices).toHaveLength(0);
    });
  });
});
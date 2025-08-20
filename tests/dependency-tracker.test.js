import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import DependencyTracker from '../scripts/dependency-tracker.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('Dependency Tracker', () => {
  let tempDir;
  let dependenciesDir;
  let servicesDir;
  let contractsDir;
  let schemaPath;
  let tracker;

  beforeEach(() => {
    // Create temporary directories for testing
    tempDir = path.join(__dirname, 'temp-dep-test');
    dependenciesDir = path.join(tempDir, 'dependencies');
    servicesDir = path.join(tempDir, 'services');
    contractsDir = path.join(tempDir, 'contracts');
    schemaPath = path.join(tempDir, 'dependency.schema.json');
    
    // Clean up and create directories
    if (fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true });
    }
    fs.mkdirSync(dependenciesDir, { recursive: true });
    fs.mkdirSync(servicesDir, { recursive: true });
    fs.mkdirSync(path.join(contractsDir, 'http'), { recursive: true });
    fs.mkdirSync(path.join(contractsDir, 'events'), { recursive: true });

    // Copy schema file
    const originalSchema = fs.readFileSync('schemas/dependency.schema.json', 'utf8');
    fs.writeFileSync(schemaPath, originalSchema);

    tracker = new DependencyTracker(dependenciesDir, servicesDir, contractsDir, schemaPath);
  });

  afterEach(() => {
    // Clean up
    if (fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true });
    }
  });

  describe('Schema Loading', () => {
    it('should load dependency schema successfully', () => {
      expect(() => tracker.loadSchema()).not.toThrow();
      expect(tracker.schema).toBeDefined();
      expect(tracker.schema.title).toBe('Fine-grained Dependency Schema');
    });

    it('should throw error if schema file not found', () => {
      const invalidTracker = new DependencyTracker(
        dependenciesDir, servicesDir, contractsDir, 'nonexistent.json'
      );
      expect(() => invalidTracker.loadSchema()).toThrow('Dependency schema not found');
    });
  });

  describe('Dependency Loading', () => {
    beforeEach(() => {
      tracker.loadSchema();
    });

    it('should load valid dependency files', () => {
      // Create test dependency
      const dependency = {
        from: 'service-a POST /api/orders',
        to: {
          endpoint: 'service-b GET /api/inventory',
          contract: {
            required: ['productId', 'quantity'],
            errors: [404, 409],
            auth: 'bearer',
            timeout_ms: 5000
          }
        },
        description: 'Order processing dependency',
        critical_path: true
      };

      fs.writeFileSync(
        path.join(dependenciesDir, 'order-inventory.yaml'),
        `from: service-a POST /api/orders
to:
  endpoint: service-b GET /api/inventory
  contract:
    required: [productId, quantity]
    errors: [404, 409]
    auth: bearer
    timeout_ms: 5000
description: Order processing dependency
critical_path: true`
      );

      tracker.loadDependencies();

      expect(tracker.dependencies.size).toBe(1);
      expect(tracker.dependencies.has('order-inventory.yaml')).toBe(true);
    });

    it('should handle invalid YAML files gracefully', () => {
      fs.writeFileSync(
        path.join(dependenciesDir, 'invalid.yaml'),
        'invalid: yaml: content: ['
      );

      fs.writeFileSync(
        path.join(dependenciesDir, 'valid.yaml'),
        `from: service-a GET /api/test
to:
  endpoint: service-b POST /api/test`
      );

      const originalWarn = console.warn;
      const warnCalls = [];
      console.warn = (...args) => warnCalls.push(args.join(' '));

      tracker.loadDependencies();

      expect(tracker.dependencies.size).toBe(1);
      expect(warnCalls.some(call => call.includes('Warning: Failed to parse invalid.yaml'))).toBe(true);

      console.warn = originalWarn;
    });
  });

  describe('Service and Contract Loading', () => {
    beforeEach(() => {
      tracker.loadSchema();
    });

    it('should load service catalog files', () => {
      fs.writeFileSync(
        path.join(servicesDir, 'service-a.yaml'),
        `name: service-a
purpose: Test service A
owner: Team A
health: /health
runbook: ../runbooks/service-a.md`
      );

      fs.writeFileSync(
        path.join(servicesDir, 'service-b.yaml'),
        `name: service-b
purpose: Test service B
owner: Team B
health: /health
runbook: ../runbooks/service-b.md`
      );

      tracker.loadServices();

      expect(tracker.services.size).toBe(2);
      expect(tracker.services.has('service-a')).toBe(true);
      expect(tracker.services.has('service-b')).toBe(true);
    });

    it('should load contract files', () => {
      fs.writeFileSync(
        path.join(contractsDir, 'http', 'service-a.openapi.yaml'),
        'openapi: 3.0.0\ninfo:\n  title: Service A\n  version: 1.0.0'
      );

      fs.writeFileSync(
        path.join(contractsDir, 'events', 'service-events.asyncapi.yaml'),
        'asyncapi: 2.0.0\ninfo:\n  title: Service Events\n  version: 1.0.0'
      );

      tracker.loadContracts();

      expect(tracker.contracts.size).toBe(2);
      expect(tracker.contracts.has('service-a')).toBe(true);
      expect(tracker.contracts.has('service-events')).toBe(true);
    });
  });

  describe('Dependency Validation', () => {
    beforeEach(() => {
      tracker.loadSchema();
      
      // Create test services
      fs.writeFileSync(
        path.join(servicesDir, 'service-a.yaml'),
        `name: service-a
purpose: Test service A
owner: Team A
health: /health
runbook: ../runbooks/service-a.md`
      );

      fs.writeFileSync(
        path.join(servicesDir, 'service-b.yaml'),
        `name: service-b
purpose: Test service B
owner: Team B
health: /health
runbook: ../runbooks/service-b.md`
      );

      tracker.loadServices();
      tracker.loadContracts();
    });

    it('should validate correct dependency files', () => {
      fs.writeFileSync(
        path.join(dependenciesDir, 'valid-dep.yaml'),
        `from: service-a POST /api/orders
to:
  endpoint: service-b GET /api/inventory
  contract:
    required: [productId]
    auth: bearer
    timeout_ms: 5000`
      );

      tracker.loadDependencies();
      const validation = tracker.validateDependencies();

      expect(validation.valid).toBe(true);
      expect(validation.summary.valid).toBe(1);
      expect(validation.summary.invalid).toBe(0);
    });

    it('should detect schema validation errors', () => {
      fs.writeFileSync(
        path.join(dependenciesDir, 'invalid-schema.yaml'),
        `from: invalid-format
to:
  endpoint: also-invalid
  contract:
    timeout_ms: "not-a-number"`
      );

      tracker.loadDependencies();
      const validation = tracker.validateDependencies();

      expect(validation.valid).toBe(false);
      expect(validation.summary.invalid).toBe(1);
      expect(validation.results[0].issues.length).toBeGreaterThan(0);
    });

    it('should detect missing service references', () => {
      fs.writeFileSync(
        path.join(dependenciesDir, 'missing-service.yaml'),
        `from: nonexistent-service POST /api/test
to:
  endpoint: another-missing GET /api/test`
      );

      tracker.loadDependencies();
      const validation = tracker.validateDependencies();

      expect(validation.valid).toBe(false);
      const result = validation.results[0];
      expect(result.issues.some(issue => 
        issue.includes("Source service 'nonexistent-service' not found")
      )).toBe(true);
      expect(result.issues.some(issue => 
        issue.includes("Target service 'another-missing' not found")
      )).toBe(true);
    });
  });

  describe('Critical Path Analysis', () => {
    beforeEach(() => {
      tracker.loadSchema();
      tracker.loadServices();
      tracker.loadContracts();
    });

    it('should identify critical paths', () => {
      fs.writeFileSync(
        path.join(dependenciesDir, 'critical-path.yaml'),
        `from: service-a POST /api/orders
to:
  endpoint: service-b GET /api/inventory
critical_path: true
description: Critical order processing flow`
      );

      fs.writeFileSync(
        path.join(dependenciesDir, 'non-critical.yaml'),
        `from: service-a GET /api/health
to:
  endpoint: service-b GET /api/health
critical_path: false`
      );

      tracker.loadDependencies();
      const analysis = tracker.analyzeCriticalPaths();

      expect(analysis.stats.total).toBe(2);
      expect(analysis.stats.critical).toBe(1);
      expect(analysis.stats.nonCritical).toBe(1);
      expect(analysis.criticalPaths[0].description).toBe('Critical order processing flow');
    });
  });

  describe('Service Name Extraction', () => {
    it('should extract service names from endpoint strings', () => {
      expect(tracker.extractServiceName('service-a POST /api/orders')).toBe('service-a');
      expect(tracker.extractServiceName('user-service GET /users/123')).toBe('user-service');
      expect(tracker.extractServiceName('api-gateway PUT /api/v1/resources')).toBe('api-gateway');
    });

    it('should extract target services from to field', () => {
      const singleTarget = {
        endpoint: 'service-b GET /api/test'
      };
      expect(tracker.extractToServices(singleTarget)).toEqual(['service-b']);

      const multipleTargets = [
        { endpoint: 'service-b GET /api/test' },
        { endpoint: 'service-c POST /api/data' }
      ];
      expect(tracker.extractToServices(multipleTargets)).toEqual(['service-b', 'service-c']);
    });
  });

  describe('Report Generation', () => {
    beforeEach(() => {
      tracker.loadSchema();
      
      // Create minimal test data
      fs.writeFileSync(
        path.join(servicesDir, 'service-a.yaml'),
        `name: service-a
purpose: Test service A
owner: Team A
health: /health
runbook: ../runbooks/service-a.md`
      );

      fs.writeFileSync(
        path.join(dependenciesDir, 'test-dep.yaml'),
        `from: service-a POST /api/test
to:
  endpoint: service-a GET /api/test
critical_path: true
description: Test dependency`
      );

      tracker.loadServices();
      tracker.loadContracts();
      tracker.loadDependencies();
    });

    it('should generate analysis report', () => {
      const report = tracker.generateAnalysisReport();

      expect(report).toContain('# Dependency Analysis Report');
      expect(report).toContain('## Validation Summary');
      expect(report).toContain('## Critical Path Analysis');
      expect(report).toContain('Total Dependencies: 1');
      expect(report).toContain('Critical Paths: 1');
    });
  });
});
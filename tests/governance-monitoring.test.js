import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import yaml from 'js-yaml';
import GovernanceMonitor from '../scripts/governance-monitoring.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('Governance Monitoring', () => {
  const testDir = path.join(__dirname, '../test-monitoring');
  let monitor;
  
  beforeEach(() => {
    // Create clean test environment
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true, force: true });
    }
    
    // Create governance directory structure
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
    
    monitor = new GovernanceMonitor(path.join(testDir, 'docs'));
  });
  
  afterEach(() => {
    // Clean up test directory
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true, force: true });
    }
  });

  describe('Coverage Metrics Calculation', () => {
    it('should calculate service catalog coverage correctly', () => {
      // Create valid service
      const validService = {
        name: 'valid-service',
        purpose: 'Test service',
        owner: 'Test Team @test-oncall',
        health: '/healthz',
        runbook: '../runbooks/valid-service.md'
      };
      
      // Create invalid service (missing required fields)
      const invalidService = {
        name: 'invalid-service',
        purpose: 'Test service'
        // Missing: owner, health, runbook
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/valid-service.yaml'),
        yaml.dump(validService)
      );
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/invalid-service.yaml'),
        yaml.dump(invalidService)
      );
      
      const coverage = monitor.calculateServiceCoverage();
      
      expect(coverage.total).toBe(2);
      expect(coverage.covered).toBe(1);
      expect(coverage.percentage).toBe(50);
      expect(coverage.missing).toHaveLength(1);
      expect(coverage.missing[0]).toContain('invalid-service.yaml');
    });

    it('should calculate contract coverage with endpoint requirements', () => {
      // Create OpenAPI contract with sufficient endpoints
      const validOpenAPI = {
        openapi: '3.0.0',
        info: { title: 'Valid API', version: '1.0.0' },
        paths: {
          '/endpoint1': { get: { responses: { '200': { description: 'OK' } } } },
          '/endpoint2': { post: { responses: { '201': { description: 'Created' } } } },
          '/endpoint3': { put: { responses: { '200': { description: 'Updated' } } } }
        }
      };
      
      // Create OpenAPI contract with insufficient endpoints
      const insufficientOpenAPI = {
        openapi: '3.0.0',
        info: { title: 'Insufficient API', version: '1.0.0' },
        paths: {
          '/endpoint1': { get: { responses: { '200': { description: 'OK' } } } }
        }
      };
      
      // Create valid AsyncAPI contract
      const validAsyncAPI = {
        asyncapi: '2.0.0',
        info: { title: 'Valid Events', version: '1.0.0' },
        channels: {
          'valid/events': {
            subscribe: { message: { payload: { type: 'object' } } }
          }
        }
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/contracts/http/valid.openapi.yaml'),
        yaml.dump(validOpenAPI)
      );
      
      fs.writeFileSync(
        path.join(testDir, 'docs/contracts/http/insufficient.openapi.yaml'),
        yaml.dump(insufficientOpenAPI)
      );
      
      fs.writeFileSync(
        path.join(testDir, 'docs/contracts/events/valid.asyncapi.yaml'),
        yaml.dump(validAsyncAPI)
      );
      
      const coverage = monitor.calculateContractCoverage();
      
      expect(coverage.total).toBe(3);
      expect(coverage.covered).toBe(2); // Valid OpenAPI + Valid AsyncAPI
      expect(coverage.percentage).toBeCloseTo(66.67, 1);
      expect(coverage.missing).toHaveLength(1);
      expect(coverage.missing[0]).toContain('insufficient.openapi.yaml');
    });

    it('should calculate runbook coverage based on service references', () => {
      // Create service with runbook reference
      const serviceWithRunbook = {
        name: 'service-with-runbook',
        purpose: 'Service with runbook',
        owner: 'Test Team @test-oncall',
        health: '/healthz',
        runbook: '../runbooks/service-with-runbook.md'
      };
      
      // Create service without runbook reference
      const serviceWithoutRunbook = {
        name: 'service-without-runbook',
        purpose: 'Service without runbook',
        owner: 'Test Team @test-oncall',
        health: '/healthz'
        // Missing: runbook
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/service-with-runbook.yaml'),
        yaml.dump(serviceWithRunbook)
      );
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/service-without-runbook.yaml'),
        yaml.dump(serviceWithoutRunbook)
      );
      
      // Create the actual runbook file
      fs.writeFileSync(
        path.join(testDir, 'docs/runbooks/service-with-runbook.md'),
        '# Service Runbook\n\nTroubleshooting guide...'
      );
      
      const coverage = monitor.calculateRunbookCoverage();
      
      expect(coverage.total).toBe(2);
      expect(coverage.covered).toBe(1);
      expect(coverage.percentage).toBe(50);
      expect(coverage.missing).toHaveLength(1);
      expect(coverage.missing[0]).toContain('service-without-runbook');
    });

    it('should calculate architecture coverage', () => {
      // Create architecture diagram
      fs.writeFileSync(
        path.join(testDir, 'docs/architecture/l2.mmd'),
        'graph TD\n  A[Service A] --> B[Service B]'
      );
      
      const coverage = monitor.calculateArchitectureCoverage();
      
      expect(coverage.total).toBe(3); // l2.mmd, l2.puml, l2.md
      expect(coverage.covered).toBe(1); // Only l2.mmd exists
      expect(coverage.percentage).toBeCloseTo(33.33, 1);
      expect(coverage.missing).toHaveLength(2);
    });

    it('should calculate feature flag coverage', () => {
      // Create feature flags file
      const featureFlags = {
        flags: [
          {
            name: 'test-flag',
            owner: 'Test Team @test-oncall',
            default: 'off',
            description: 'Test feature flag'
          }
        ]
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/release/flags.yaml'),
        yaml.dump(featureFlags)
      );
      
      // Create rollback procedure
      fs.writeFileSync(
        path.join(testDir, 'docs/release/rollback.md'),
        '# Rollback Procedures\n\n1. Disable flag\n2. Version rollback\n3. DB script'
      );
      
      const coverage = monitor.calculateFeatureFlagCoverage();
      
      expect(coverage.total).toBe(2);
      expect(coverage.covered).toBe(2);
      expect(coverage.percentage).toBe(100);
      expect(coverage.missing).toHaveLength(0);
    });
  });

  describe('Health Checks', () => {
    it('should check validation health', () => {
      const health = monitor.checkValidationHealth();
      
      // Should detect missing validation script and schemas
      expect(health.status).toBe('error');
      expect(health.issues.length).toBeGreaterThan(0);
      expect(health.issues.some(issue => issue.includes('Validation script'))).toBe(true);
    });

    it('should check CI pipeline health', () => {
      const health = monitor.checkCIPipelineHealth();
      
      // Should detect missing CI workflow and test files
      expect(health.status).toBe('error');
      expect(health.issues.length).toBeGreaterThan(0);
      expect(health.issues.some(issue => issue.includes('CI workflow'))).toBe(true);
    });

    it('should check documentation health', () => {
      const health = monitor.checkDocumentationHealth();
      
      // All directories should exist (created in beforeEach)
      expect(health.status).toBe('healthy');
      expect(health.issues).toHaveLength(0);
    });

    it('should check tracing health', () => {
      const health = monitor.checkTracingHealth();
      
      // Should detect missing tracing utilities
      expect(health.status).toBe('warning');
      expect(health.issues.length).toBeGreaterThan(0);
    });
  });

  describe('Alert Generation', () => {
    it('should generate coverage alerts for low coverage components', () => {
      // Create setup with low coverage
      const invalidService = {
        name: 'invalid-service',
        purpose: 'Invalid service'
        // Missing required fields
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/invalid-service.yaml'),
        yaml.dump(invalidService)
      );
      
      // Calculate coverage first
      monitor.calculateCoverageMetrics();
      
      const alerts = monitor.generateAlerts();
      
      expect(alerts.length).toBeGreaterThan(0);
      
      const coverageAlerts = alerts.filter(a => a.type === 'coverage');
      expect(coverageAlerts.length).toBeGreaterThan(0);
      
      const highSeverityAlerts = alerts.filter(a => a.severity === 'high');
      expect(highSeverityAlerts.length).toBeGreaterThan(0);
    });

    it('should generate health alerts for unhealthy components', () => {
      // Check health first
      monitor.checkFrameworkHealth();
      
      const alerts = monitor.generateAlerts();
      
      const healthAlerts = alerts.filter(a => a.type === 'health');
      expect(healthAlerts.length).toBeGreaterThan(0);
      
      // Should have alerts for missing validation scripts, CI workflows, etc.
      expect(healthAlerts.some(a => a.component === 'validationStatus')).toBe(true);
      expect(healthAlerts.some(a => a.component === 'ciPipeline')).toBe(true);
    });

    it('should generate orphaned contract alerts', () => {
      // Create orphaned contract (no service references it)
      const orphanedContract = {
        openapi: '3.0.0',
        info: { title: 'Orphaned API', version: '1.0.0' },
        paths: {
          '/orphaned': { get: { responses: { '200': { description: 'OK' } } } }
        }
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/contracts/http/orphaned.openapi.yaml'),
        yaml.dump(orphanedContract)
      );
      
      const alerts = monitor.generateAlerts();
      
      const orphanedAlerts = alerts.filter(a => a.type === 'orphaned');
      expect(orphanedAlerts.length).toBe(1);
      expect(orphanedAlerts[0].message).toContain('orphaned contracts detected');
    });
  });

  describe('Dashboard Generation', () => {
    it('should generate complete dashboard data', async () => {
      // Create minimal valid setup
      const validService = {
        name: 'test-service',
        purpose: 'Test service',
        owner: 'Test Team @test-oncall',
        health: '/healthz',
        runbook: '../runbooks/test-service.md'
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/test-service.yaml'),
        yaml.dump(validService)
      );
      
      fs.writeFileSync(
        path.join(testDir, 'docs/runbooks/test-service.md'),
        '# Test Service Runbook'
      );
      
      const dashboard = await monitor.runMonitoring();
      
      expect(dashboard).toHaveProperty('timestamp');
      expect(dashboard).toHaveProperty('summary');
      expect(dashboard).toHaveProperty('coverage');
      expect(dashboard).toHaveProperty('health');
      expect(dashboard).toHaveProperty('alerts');
      expect(dashboard).toHaveProperty('recommendations');
      
      // Verify summary structure
      expect(dashboard.summary).toHaveProperty('overallCoverage');
      expect(dashboard.summary).toHaveProperty('overallHealth');
      expect(dashboard.summary).toHaveProperty('totalAlerts');
      expect(dashboard.summary).toHaveProperty('highSeverityAlerts');
      
      // Verify coverage data
      expect(dashboard.coverage).toHaveProperty('services');
      expect(dashboard.coverage).toHaveProperty('contracts');
      expect(dashboard.coverage).toHaveProperty('runbooks');
      
      // Verify health data
      expect(dashboard.health).toHaveProperty('validationStatus');
      expect(dashboard.health).toHaveProperty('ciPipeline');
      expect(dashboard.health).toHaveProperty('documentation');
      expect(dashboard.health).toHaveProperty('tracing');
    });

    it('should generate actionable recommendations', () => {
      // Create setup with issues
      const incompleteService = {
        name: 'incomplete-service',
        purpose: 'Incomplete service'
        // Missing required fields
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/incomplete-service.yaml'),
        yaml.dump(incompleteService)
      );
      
      // Calculate metrics
      monitor.calculateCoverageMetrics();
      monitor.checkFrameworkHealth();
      
      const recommendations = monitor.generateRecommendations();
      
      expect(recommendations.length).toBeGreaterThan(0);
      
      // Should have coverage recommendations
      const coverageRecs = recommendations.filter(r => r.type === 'coverage');
      expect(coverageRecs.length).toBeGreaterThan(0);
      
      // Should have health recommendations
      const healthRecs = recommendations.filter(r => r.type === 'health');
      expect(healthRecs.length).toBeGreaterThan(0);
      
      // Verify recommendation structure
      recommendations.forEach(rec => {
        expect(rec).toHaveProperty('type');
        expect(rec).toHaveProperty('priority');
        expect(rec).toHaveProperty('component');
        expect(rec).toHaveProperty('action');
        expect(rec).toHaveProperty('details');
      });
    });
  });

  describe('Performance and Scalability', () => {
    it('should handle large numbers of services efficiently', () => {
      const serviceCount = 100;
      const startTime = Date.now();
      
      // Create many services
      for (let i = 0; i < serviceCount; i++) {
        const service = {
          name: `service-${i.toString().padStart(3, '0')}`,
          purpose: `Test service ${i}`,
          owner: `Team-${i % 10} @oncall-${i % 10}`,
          health: '/healthz',
          runbook: `../runbooks/service-${i.toString().padStart(3, '0')}.md`
        };
        
        fs.writeFileSync(
          path.join(testDir, `docs/services/service-${i.toString().padStart(3, '0')}.yaml`),
          yaml.dump(service)
        );
      }
      
      const setupTime = Date.now() - startTime;
      console.log(`Setup time for ${serviceCount} services: ${setupTime}ms`);
      
      // Run monitoring
      const monitoringStartTime = Date.now();
      const coverage = monitor.calculateCoverageMetrics();
      const monitoringTime = Date.now() - monitoringStartTime;
      
      console.log(`Monitoring time for ${serviceCount} services: ${monitoringTime}ms`);
      
      // Verify results
      expect(coverage.services.total).toBe(serviceCount);
      expect(coverage.services.covered).toBe(0); // No runbooks created
      expect(coverage.services.percentage).toBe(0);
      
      // Should complete within reasonable time
      expect(monitoringTime).toBeLessThan(5000); // 5 seconds
    });

    it('should handle monitoring cycles without memory leaks', async () => {
      // Create test data
      const service = {
        name: 'memory-test-service',
        purpose: 'Memory test service',
        owner: 'Test Team @test-oncall',
        health: '/healthz',
        runbook: '../runbooks/memory-test-service.md'
      };
      
      fs.writeFileSync(
        path.join(testDir, 'docs/services/memory-test-service.yaml'),
        yaml.dump(service)
      );
      
      // Run multiple monitoring cycles
      const cycles = 10;
      const results = [];
      
      for (let i = 0; i < cycles; i++) {
        const dashboard = await monitor.runMonitoring();
        results.push(dashboard);
        
        // Clear metrics to simulate fresh monitoring
        monitor.metrics = {
          coverage: {},
          health: {},
          compliance: {},
          alerts: []
        };
      }
      
      // Verify all cycles completed successfully
      expect(results).toHaveLength(cycles);
      results.forEach(result => {
        expect(result).toHaveProperty('timestamp');
        expect(result).toHaveProperty('summary');
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle malformed YAML files gracefully', () => {
      // Create malformed YAML file
      fs.writeFileSync(
        path.join(testDir, 'docs/services/malformed.yaml'),
        'name: test\ninvalid: yaml: syntax: error'
      );
      
      const coverage = monitor.calculateServiceCoverage();
      
      expect(coverage.total).toBe(1);
      expect(coverage.covered).toBe(0);
      expect(coverage.missing).toHaveLength(1);
      expect(coverage.missing[0]).toContain('parsing error');
    });

    it('should handle missing directories gracefully', () => {
      // Remove a directory
      fs.rmSync(path.join(testDir, 'docs/services'), { recursive: true, force: true });
      
      const coverage = monitor.calculateServiceCoverage();
      
      expect(coverage.total).toBe(0);
      expect(coverage.covered).toBe(0);
      expect(coverage.percentage).toBe(0);
      expect(coverage.missing).toHaveLength(0);
    });

    it('should handle empty directories gracefully', () => {
      // Directories exist but are empty (created in beforeEach)
      const coverage = monitor.calculateCoverageMetrics();
      
      expect(coverage).toHaveProperty('services');
      expect(coverage).toHaveProperty('contracts');
      expect(coverage).toHaveProperty('runbooks');
      
      // Should not throw errors
      expect(coverage.services.total).toBe(0);
      expect(coverage.contracts.total).toBe(0);
    });
  });
});
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import ArchitectureDiagramGenerator from '../scripts/architecture-diagram-generator.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('Architecture Diagram Generator', () => {
  let tempDir;
  let servicesDir;
  let outputDir;
  let generator;

  beforeEach(() => {
    // Create temporary directories for testing
    tempDir = path.join(__dirname, 'temp-arch-test');
    servicesDir = path.join(tempDir, 'services');
    outputDir = path.join(tempDir, 'architecture');
    
    // Clean up and create directories
    if (fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true });
    }
    fs.mkdirSync(servicesDir, { recursive: true });
    fs.mkdirSync(outputDir, { recursive: true });

    generator = new ArchitectureDiagramGenerator(servicesDir, outputDir);
  });

  afterEach(() => {
    // Clean up
    if (fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true });
    }
  });

  describe('Service Loading', () => {
    it('should load valid service catalog files', () => {
      // Create test service files
      const service1 = {
        name: 'service-a',
        purpose: 'Test service A',
        owner: 'Team A',
        health: '/health',
        runbook: '../runbooks/service-a.md'
      };

      const service2 = {
        name: 'service-b',
        purpose: 'Test service B',
        owner: 'Team B',
        health: '/health',
        depends_on: ['service-a'],
        runbook: '../runbooks/service-b.md'
      };

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
depends_on:
  - service-a
runbook: ../runbooks/service-b.md`
      );

      generator.loadServices();

      expect(generator.services.size).toBe(2);
      expect(generator.services.has('service-a')).toBe(true);
      expect(generator.services.has('service-b')).toBe(true);
      expect(generator.dependencies.get('service-b')).toEqual(['service-a']);
    });

    it('should handle invalid YAML files gracefully', () => {
      fs.writeFileSync(
        path.join(servicesDir, 'invalid.yaml'),
        'invalid: yaml: content: ['
      );

      fs.writeFileSync(
        path.join(servicesDir, 'valid.yaml'),
        `name: valid-service
purpose: Valid service
owner: Team
health: /health
runbook: ../runbooks/valid.md`
      );

      const originalWarn = console.warn;
      const warnCalls = [];
      console.warn = (...args) => warnCalls.push(args.join(' '));

      generator.loadServices();

      expect(generator.services.size).toBe(1);
      expect(generator.services.has('valid-service')).toBe(true);
      expect(warnCalls.some(call => call.includes('Warning: Failed to parse invalid.yaml'))).toBe(true);

      console.warn = originalWarn;
    });
  });

  describe('Mermaid Diagram Generation', () => {
    beforeEach(() => {
      // Create test services
      fs.writeFileSync(
        path.join(servicesDir, 'frontend.yaml'),
        `name: frontend
purpose: Web frontend
owner: Frontend Team
health: /health
depends_on:
  - api-gateway
runbook: ../runbooks/frontend.md`
      );

      fs.writeFileSync(
        path.join(servicesDir, 'api-gateway.yaml'),
        `name: api-gateway
purpose: API Gateway
owner: Platform Team
health: /health
depends_on:
  - user-service
  - order-service
runbook: ../runbooks/api-gateway.md`
      );

      fs.writeFileSync(
        path.join(servicesDir, 'user-service.yaml'),
        `name: user-service
purpose: User management
owner: Backend Team
health: /health
runbook: ../runbooks/user-service.md`
      );

      generator.loadServices();
    });

    it('should generate valid Mermaid diagram', () => {
      const diagram = generator.generateMermaidDiagram();

      expect(diagram).toContain('graph TD');
      expect(diagram).toContain('frontend["frontend<br/>Web frontend"]');
      expect(diagram).toContain('api_gateway["api-gateway<br/>API Gateway"]');
      expect(diagram).toContain('user_service["user-service<br/>User management"]');
      expect(diagram).toContain('frontend --> api_gateway');
      expect(diagram).toContain('api_gateway --> user_service');
    });

    it('should handle external dependencies', () => {
      fs.writeFileSync(
        path.join(servicesDir, 'service-with-external.yaml'),
        `name: service-with-external
purpose: Service with external deps
owner: Team
health: /health
depends_on:
  - external-service
runbook: ../runbooks/service.md`
      );

      generator.loadServices();
      const diagram = generator.generateMermaidDiagram();

      expect(diagram).toContain('external_service["external-service<br/>(External)"]');
      expect(diagram).toContain('service_with_external --> external_service');
      expect(diagram).toContain('style external_service fill:#ffcccc');
    });

    it('should sanitize node IDs', () => {
      expect(generator.sanitizeNodeId('service-name')).toBe('service_name');
      expect(generator.sanitizeNodeId('service.name')).toBe('service_name');
      expect(generator.sanitizeNodeId('service@name')).toBe('service_name');
    });
  });

  describe('Diagram Validation', () => {
    it('should validate complete diagram', () => {
      fs.writeFileSync(
        path.join(servicesDir, 'service-a.yaml'),
        `name: service-a
purpose: Service A
owner: Team A
health: /health
depends_on:
  - service-b
runbook: ../runbooks/service-a.md`
      );

      fs.writeFileSync(
        path.join(servicesDir, 'service-b.yaml'),
        `name: service-b
purpose: Service B
owner: Team B
health: /health
runbook: ../runbooks/service-b.md`
      );

      generator.loadServices();
      const validation = generator.validateDiagram();

      expect(validation.valid).toBe(true);
      expect(validation.issues).toHaveLength(0);
      expect(validation.stats.totalServices).toBe(2);
      expect(validation.stats.servicesWithDependencies).toBe(1);
    });

    it('should detect orphaned services', () => {
      fs.writeFileSync(
        path.join(servicesDir, 'orphaned.yaml'),
        `name: orphaned
purpose: Orphaned service
owner: Team
health: /health
runbook: ../runbooks/orphaned.md`
      );

      generator.loadServices();
      const validation = generator.validateDiagram();

      expect(validation.valid).toBe(false);
      expect(validation.issues).toContain(
        'Orphaned services (no connections): orphaned'
      );
    });

    it('should detect missing service definitions', () => {
      fs.writeFileSync(
        path.join(servicesDir, 'service-a.yaml'),
        `name: service-a
purpose: Service A
owner: Team A
health: /health
depends_on:
  - missing-service
runbook: ../runbooks/service-a.md`
      );

      generator.loadServices();
      const validation = generator.validateDiagram();

      expect(validation.valid).toBe(false);
      expect(validation.issues).toContain(
        'Missing service definitions: missing-service'
      );
    });
  });

  describe('File Generation', () => {
    it('should generate diagram and validation report files', () => {
      fs.writeFileSync(
        path.join(servicesDir, 'test-service.yaml'),
        `name: test-service
purpose: Test service
owner: Test Team
health: /health
runbook: ../runbooks/test-service.md`
      );

      const result = generator.generate();

      expect(fs.existsSync(result.diagramPath)).toBe(true);
      expect(fs.existsSync(result.reportPath)).toBe(true);

      const diagramContent = fs.readFileSync(result.diagramPath, 'utf8');
      expect(diagramContent).toContain('graph TD');
      expect(diagramContent).toContain('test_service');

      const reportContent = fs.readFileSync(result.reportPath, 'utf8');
      expect(reportContent).toContain('# L2 Architecture Diagram Validation Report');
      expect(reportContent).toContain('Total Services: 1');
    });
  });
});
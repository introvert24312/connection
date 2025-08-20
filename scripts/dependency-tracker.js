#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import Ajv from 'ajv';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Fine-grained Dependency Tracker
 * Manages endpoint-to-endpoint dependency mapping and validation
 */
class DependencyTracker {
  constructor(
    dependenciesDir = 'docs/dependencies',
    servicesDir = 'docs/services',
    contractsDir = 'docs/contracts',
    schemaPath = 'schemas/dependency.schema.json'
  ) {
    this.dependenciesDir = dependenciesDir;
    this.servicesDir = servicesDir;
    this.contractsDir = contractsDir;
    this.schemaPath = schemaPath;
    
    this.dependencies = new Map();
    this.services = new Map();
    this.contracts = new Map();
    this.ajv = new Ajv({ allErrors: true });
    this.schema = null;
  }

  /**
   * Load dependency schema
   */
  loadSchema() {
    if (!fs.existsSync(this.schemaPath)) {
      throw new Error(`Dependency schema not found: ${this.schemaPath}`);
    }

    const schemaContent = fs.readFileSync(this.schemaPath, 'utf8');
    this.schema = JSON.parse(schemaContent);
    this.ajv.addSchema(this.schema, 'dependency');
    
    console.log('Dependency schema loaded');
  }

  /**
   * Load all dependency files
   */
  loadDependencies() {
    if (!fs.existsSync(this.dependenciesDir)) {
      console.warn(`Dependencies directory not found: ${this.dependenciesDir}`);
      return;
    }

    const files = fs.readdirSync(this.dependenciesDir)
      .filter(file => file.endsWith('.yaml') && file !== '.gitkeep');

    for (const file of files) {
      const filePath = path.join(this.dependenciesDir, file);
      try {
        const content = fs.readFileSync(filePath, 'utf8');
        const dependency = yaml.load(content);
        
        if (dependency) {
          this.dependencies.set(file, {
            file: file,
            path: filePath,
            data: dependency
          });
        }
      } catch (error) {
        console.warn(`Warning: Failed to parse ${file}: ${error.message}`);
      }
    }

    console.log(`Loaded ${this.dependencies.size} dependency files`);
  }

  /**
   * Load service catalog for validation
   */
  loadServices() {
    if (!fs.existsSync(this.servicesDir)) {
      console.warn(`Services directory not found: ${this.servicesDir}`);
      return;
    }

    const files = fs.readdirSync(this.servicesDir)
      .filter(file => file.endsWith('.yaml') && file !== '.gitkeep');

    for (const file of files) {
      const filePath = path.join(this.servicesDir, file);
      try {
        const content = fs.readFileSync(filePath, 'utf8');
        const service = yaml.load(content);
        
        if (service && service.name) {
          this.services.set(service.name, service);
        }
      } catch (error) {
        console.warn(`Warning: Failed to parse service ${file}: ${error.message}`);
      }
    }

    console.log(`Loaded ${this.services.size} services for validation`);
  }

  /**
   * Load contract files for validation
   */
  loadContracts() {
    const httpDir = path.join(this.contractsDir, 'http');
    const eventsDir = path.join(this.contractsDir, 'events');

    // Load HTTP contracts
    if (fs.existsSync(httpDir)) {
      const httpFiles = fs.readdirSync(httpDir)
        .filter(file => file.endsWith('.openapi.yaml'));
      
      for (const file of httpFiles) {
        const contractName = file.replace('.openapi.yaml', '');
        this.contracts.set(contractName, {
          type: 'openapi',
          path: path.join(httpDir, file)
        });
      }
    }

    // Load Event contracts
    if (fs.existsSync(eventsDir)) {
      const eventFiles = fs.readdirSync(eventsDir)
        .filter(file => file.endsWith('.asyncapi.yaml'));
      
      for (const file of eventFiles) {
        const contractName = file.replace('.asyncapi.yaml', '');
        this.contracts.set(contractName, {
          type: 'asyncapi',
          path: path.join(eventsDir, file)
        });
      }
    }

    console.log(`Loaded ${this.contracts.size} contracts for validation`);
  }

  /**
   * Validate all dependency files
   */
  validateDependencies() {
    const results = [];

    for (const [fileName, dep] of this.dependencies) {
      const result = this.validateSingleDependency(fileName, dep.data);
      results.push(result);
    }

    return {
      valid: results.every(r => r.valid),
      results: results,
      summary: {
        total: results.length,
        valid: results.filter(r => r.valid).length,
        invalid: results.filter(r => !r.valid).length
      }
    };
  }

  /**
   * Validate a single dependency file
   */
  validateSingleDependency(fileName, dependency) {
    const issues = [];

    // Schema validation
    const valid = this.ajv.validate('dependency', dependency);
    if (!valid) {
      issues.push(...this.ajv.errors.map(err => 
        `Schema error at ${err.instancePath}: ${err.message}`
      ));
    }

    // Service existence validation
    const fromService = this.extractServiceName(dependency.from);
    const toServices = this.extractToServices(dependency.to);

    if (!this.services.has(fromService)) {
      issues.push(`Source service '${fromService}' not found in service catalog`);
    }

    for (const toService of toServices) {
      if (!this.services.has(toService)) {
        issues.push(`Target service '${toService}' not found in service catalog`);
      }
    }

    // Contract reference validation
    const contractRefs = this.extractContractReferences(dependency.to);
    for (const contractRef of contractRefs) {
      if (contractRef && !this.contracts.has(contractRef)) {
        issues.push(`Contract reference '${contractRef}' not found`);
      }
    }

    return {
      file: fileName,
      valid: issues.length === 0,
      issues: issues,
      dependency: dependency
    };
  }

  /**
   * Extract service name from endpoint string
   */
  extractServiceName(endpoint) {
    const parts = endpoint.split(' ');
    return parts[0];
  }

  /**
   * Extract target services from 'to' field
   */
  extractToServices(to) {
    const services = [];
    
    if (Array.isArray(to)) {
      for (const target of to) {
        if (target.endpoint) {
          services.push(this.extractServiceName(target.endpoint));
        }
      }
    } else if (to.endpoint) {
      services.push(this.extractServiceName(to.endpoint));
    }

    return services;
  }

  /**
   * Extract contract references from 'to' field
   */
  extractContractReferences(to) {
    const refs = [];
    
    if (Array.isArray(to)) {
      for (const target of to) {
        if (target.contract) {
          if (target.contract.openapi_ref) {
            refs.push(path.basename(target.contract.openapi_ref, '.openapi.yaml'));
          }
          if (target.contract.asyncapi_ref) {
            refs.push(path.basename(target.contract.asyncapi_ref, '.asyncapi.yaml'));
          }
        }
      }
    } else if (to.contract) {
      if (to.contract.openapi_ref) {
        refs.push(path.basename(to.contract.openapi_ref, '.openapi.yaml'));
      }
      if (to.contract.asyncapi_ref) {
        refs.push(path.basename(to.contract.asyncapi_ref, '.asyncapi.yaml'));
      }
    }

    return refs;
  }

  /**
   * Analyze critical paths
   */
  analyzeCriticalPaths() {
    const criticalPaths = [];
    const allPaths = [];

    for (const [fileName, dep] of this.dependencies) {
      const dependency = dep.data;
      const isCritical = dependency.critical_path === true;
      
      const pathInfo = {
        file: fileName,
        from: dependency.from,
        to: dependency.to,
        critical: isCritical,
        description: dependency.description,
        sla: dependency.sla
      };

      allPaths.push(pathInfo);
      
      if (isCritical) {
        criticalPaths.push(pathInfo);
      }
    }

    return {
      criticalPaths: criticalPaths,
      allPaths: allPaths,
      stats: {
        total: allPaths.length,
        critical: criticalPaths.length,
        nonCritical: allPaths.length - criticalPaths.length
      }
    };
  }

  /**
   * Generate dependency analysis report
   */
  generateAnalysisReport() {
    const validation = this.validateDependencies();
    const pathAnalysis = this.analyzeCriticalPaths();

    const lines = [];
    lines.push('# Dependency Analysis Report');
    lines.push('');
    lines.push(`Generated: ${new Date().toISOString()}`);
    lines.push('');

    // Validation Summary
    lines.push('## Validation Summary');
    lines.push(`- Total Dependencies: ${validation.summary.total}`);
    lines.push(`- Valid: ${validation.summary.valid}`);
    lines.push(`- Invalid: ${validation.summary.invalid}`);
    lines.push(`- Status: ${validation.valid ? '✅ ALL VALID' : '❌ VALIDATION ERRORS'}`);
    lines.push('');

    // Critical Path Analysis
    lines.push('## Critical Path Analysis');
    lines.push(`- Total Paths: ${pathAnalysis.stats.total}`);
    lines.push(`- Critical Paths: ${pathAnalysis.stats.critical}`);
    lines.push(`- Non-Critical Paths: ${pathAnalysis.stats.nonCritical}`);
    lines.push('');

    if (pathAnalysis.criticalPaths.length > 0) {
      lines.push('### Critical Paths');
      for (const path of pathAnalysis.criticalPaths) {
        lines.push(`- **${path.from}** → **${this.formatToEndpoints(path.to)}**`);
        if (path.description) {
          lines.push(`  - Description: ${path.description}`);
        }
        if (path.sla) {
          lines.push(`  - SLA: ${JSON.stringify(path.sla)}`);
        }
      }
      lines.push('');
    }

    // Validation Issues
    if (!validation.valid) {
      lines.push('## Validation Issues');
      for (const result of validation.results) {
        if (!result.valid) {
          lines.push(`### ${result.file}`);
          for (const issue of result.issues) {
            lines.push(`- ${issue}`);
          }
          lines.push('');
        }
      }
    }

    // Service Dependency Matrix
    lines.push('## Service Dependency Matrix');
    const matrix = this.buildDependencyMatrix();
    for (const [service, deps] of matrix) {
      if (deps.length > 0) {
        lines.push(`- **${service}** depends on: ${deps.join(', ')}`);
      }
    }

    return lines.join('\n');
  }

  /**
   * Format 'to' endpoints for display
   */
  formatToEndpoints(to) {
    if (Array.isArray(to)) {
      return to.map(t => t.endpoint).join(', ');
    } else if (to.endpoint) {
      return to.endpoint;
    }
    return 'Unknown';
  }

  /**
   * Build service dependency matrix
   */
  buildDependencyMatrix() {
    const matrix = new Map();

    for (const [fileName, dep] of this.dependencies) {
      const dependency = dep.data;
      const fromService = this.extractServiceName(dependency.from);
      const toServices = this.extractToServices(dependency.to);

      if (!matrix.has(fromService)) {
        matrix.set(fromService, []);
      }

      const existing = matrix.get(fromService);
      for (const toService of toServices) {
        if (!existing.includes(toService)) {
          existing.push(toService);
        }
      }
    }

    return matrix;
  }

  /**
   * Run complete dependency analysis
   */
  analyze() {
    this.loadSchema();
    this.loadServices();
    this.loadContracts();
    this.loadDependencies();

    const validation = this.validateDependencies();
    const pathAnalysis = this.analyzeCriticalPaths();
    const report = this.generateAnalysisReport();

    // Write report
    const reportPath = path.join(this.dependenciesDir, 'analysis-report.md');
    fs.writeFileSync(reportPath, report);

    console.log(`Dependency analysis report generated: ${reportPath}`);

    return {
      validation: validation,
      pathAnalysis: pathAnalysis,
      reportPath: reportPath
    };
  }
}

// CLI interface
if (import.meta.url === `file://${process.argv[1]}`) {
  const tracker = new DependencyTracker();
  
  try {
    const result = tracker.analyze();
    
    if (result.validation.valid) {
      console.log('✅ All dependencies are valid');
      process.exit(0);
    } else {
      console.log('❌ Dependency validation failed');
      process.exit(1);
    }
  } catch (error) {
    console.error('❌ Failed to analyze dependencies:', error.message);
    process.exit(1);
  }
}

export default DependencyTracker;
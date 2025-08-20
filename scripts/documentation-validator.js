#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Comprehensive Documentation Validator
 * Validates cross-references and consistency across all documentation components
 */
class DocumentationValidator {
  constructor(docsDir = 'docs') {
    this.docsDir = docsDir;
    this.services = new Map();
    this.contracts = new Map();
    this.dependencies = new Map();
    this.runbooks = new Map();
    this.architectureDiagrams = new Map();
    this.validationResults = [];
  }

  /**
   * Load all documentation components
   */
  loadAllDocumentation() {
    this.loadServices();
    this.loadContracts();
    this.loadDependencies();
    this.loadRunbooks();
    this.loadArchitectureDiagrams();
  }

  /**
   * Load service catalog files
   */
  loadServices() {
    const servicesDir = path.join(this.docsDir, 'services');
    if (!fs.existsSync(servicesDir)) {
      this.addValidationResult('error', 'Services directory not found', servicesDir);
      return;
    }

    const files = fs.readdirSync(servicesDir)
      .filter(file => file.endsWith('.yaml') && file !== '.gitkeep');

    for (const file of files) {
      const filePath = path.join(servicesDir, file);
      try {
        const content = fs.readFileSync(filePath, 'utf8');
        const service = yaml.load(content);
        
        if (service && service.name) {
          this.services.set(service.name, {
            file: file,
            path: filePath,
            data: service
          });
        }
      } catch (error) {
        this.addValidationResult('error', `Failed to parse service file: ${error.message}`, filePath);
      }
    }

    console.log(`Loaded ${this.services.size} services`);
  }

  /**
   * Load contract files
   */
  loadContracts() {
    const httpDir = path.join(this.docsDir, 'contracts', 'http');
    const eventsDir = path.join(this.docsDir, 'contracts', 'events');

    // Load HTTP contracts
    if (fs.existsSync(httpDir)) {
      const httpFiles = fs.readdirSync(httpDir)
        .filter(file => file.endsWith('.openapi.yaml'));
      
      for (const file of httpFiles) {
        const contractName = file.replace('.openapi.yaml', '');
        const filePath = path.join(httpDir, file);
        this.contracts.set(contractName, {
          type: 'openapi',
          file: file,
          path: filePath
        });
      }
    }

    // Load Event contracts
    if (fs.existsSync(eventsDir)) {
      const eventFiles = fs.readdirSync(eventsDir)
        .filter(file => file.endsWith('.asyncapi.yaml'));
      
      for (const file of eventFiles) {
        const contractName = file.replace('.asyncapi.yaml', '');
        const filePath = path.join(eventsDir, file);
        this.contracts.set(contractName, {
          type: 'asyncapi',
          file: file,
          path: filePath
        });
      }
    }

    console.log(`Loaded ${this.contracts.size} contracts`);
  }

  /**
   * Load dependency files
   */
  loadDependencies() {
    const dependenciesDir = path.join(this.docsDir, 'dependencies');
    if (!fs.existsSync(dependenciesDir)) {
      this.addValidationResult('warning', 'Dependencies directory not found', dependenciesDir);
      return;
    }

    const files = fs.readdirSync(dependenciesDir)
      .filter(file => file.endsWith('.yaml') && file !== '.gitkeep');

    for (const file of files) {
      const filePath = path.join(dependenciesDir, file);
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
        this.addValidationResult('error', `Failed to parse dependency file: ${error.message}`, filePath);
      }
    }

    console.log(`Loaded ${this.dependencies.size} dependencies`);
  }

  /**
   * Load runbook files
   */
  loadRunbooks() {
    const runbooksDir = path.join(this.docsDir, 'runbooks');
    if (!fs.existsSync(runbooksDir)) {
      this.addValidationResult('warning', 'Runbooks directory not found', runbooksDir);
      return;
    }

    const files = fs.readdirSync(runbooksDir)
      .filter(file => file.endsWith('.md') && file !== '.gitkeep');

    for (const file of files) {
      const filePath = path.join(runbooksDir, file);
      const runbookName = file.replace('.md', '');
      this.runbooks.set(runbookName, {
        file: file,
        path: filePath
      });
    }

    console.log(`Loaded ${this.runbooks.size} runbooks`);
  }

  /**
   * Load architecture diagrams
   */
  loadArchitectureDiagrams() {
    const architectureDir = path.join(this.docsDir, 'architecture');
    if (!fs.existsSync(architectureDir)) {
      this.addValidationResult('warning', 'Architecture directory not found', architectureDir);
      return;
    }

    const files = fs.readdirSync(architectureDir)
      .filter(file => file.endsWith('.mmd') || file.endsWith('.puml'));

    for (const file of files) {
      const filePath = path.join(architectureDir, file);
      const diagramName = file.replace(/\.(mmd|puml)$/, '');
      this.architectureDiagrams.set(diagramName, {
        file: file,
        path: filePath
      });
    }

    console.log(`Loaded ${this.architectureDiagrams.size} architecture diagrams`);
  }

  /**
   * Add validation result
   */
  addValidationResult(level, message, filePath = null, details = null) {
    this.validationResults.push({
      level: level, // 'error', 'warning', 'info'
      message: message,
      filePath: filePath,
      details: details,
      timestamp: new Date().toISOString()
    });
  }

  /**
   * Validate service catalog cross-references
   */
  validateServiceCrossReferences() {
    console.log('Validating service cross-references...');

    for (const [serviceName, serviceInfo] of this.services) {
      const service = serviceInfo.data;

      // Check OpenAPI reference
      if (service.openapi) {
        const contractPath = this.resolveRelativePath(serviceInfo.path, service.openapi);
        if (!fs.existsSync(contractPath)) {
          this.addValidationResult(
            'error',
            `OpenAPI reference not found: ${service.openapi}`,
            serviceInfo.path,
            { service: serviceName, reference: service.openapi }
          );
        } else {
          // Check if contract is in our loaded contracts
          const contractName = path.basename(service.openapi, '.openapi.yaml');
          if (!this.contracts.has(contractName)) {
            this.addValidationResult(
              'warning',
              `OpenAPI contract not loaded: ${contractName}`,
              serviceInfo.path,
              { service: serviceName, contract: contractName }
            );
          }
        }
      }

      // Check AsyncAPI reference
      if (service.asyncapi) {
        const contractPath = this.resolveRelativePath(serviceInfo.path, service.asyncapi);
        if (!fs.existsSync(contractPath)) {
          this.addValidationResult(
            'error',
            `AsyncAPI reference not found: ${service.asyncapi}`,
            serviceInfo.path,
            { service: serviceName, reference: service.asyncapi }
          );
        }
      }

      // Check runbook reference
      if (service.runbook) {
        const runbookPath = this.resolveRelativePath(serviceInfo.path, service.runbook);
        if (!fs.existsSync(runbookPath)) {
          this.addValidationResult(
            'error',
            `Runbook reference not found: ${service.runbook}`,
            serviceInfo.path,
            { service: serviceName, reference: service.runbook }
          );
        } else {
          // Check if runbook is in our loaded runbooks
          const runbookName = path.basename(service.runbook, '.md');
          if (!this.runbooks.has(runbookName)) {
            this.addValidationResult(
              'warning',
              `Runbook not loaded: ${runbookName}`,
              serviceInfo.path,
              { service: serviceName, runbook: runbookName }
            );
          }
        }
      }

      // Check service dependencies
      if (service.depends_on && Array.isArray(service.depends_on)) {
        for (const dependency of service.depends_on) {
          if (!this.services.has(dependency)) {
            this.addValidationResult(
              'error',
              `Service dependency not found: ${dependency}`,
              serviceInfo.path,
              { service: serviceName, dependency: dependency }
            );
          }
        }
      }
    }
  }

  /**
   * Validate dependency cross-references
   */
  validateDependencyCrossReferences() {
    console.log('Validating dependency cross-references...');

    for (const [fileName, depInfo] of this.dependencies) {
      const dependency = depInfo.data;

      // Extract service names from endpoints
      const fromService = this.extractServiceName(dependency.from);
      const toServices = this.extractToServices(dependency.to);

      // Validate source service exists
      if (!this.services.has(fromService)) {
        this.addValidationResult(
          'error',
          `Source service not found in catalog: ${fromService}`,
          depInfo.path,
          { dependency: fileName, service: fromService }
        );
      }

      // Validate target services exist
      for (const toService of toServices) {
        if (!this.services.has(toService)) {
          this.addValidationResult(
            'error',
            `Target service not found in catalog: ${toService}`,
            depInfo.path,
            { dependency: fileName, service: toService }
          );
        }
      }

      // Validate contract references
      const contractRefs = this.extractContractReferences(dependency.to);
      for (const contractRef of contractRefs) {
        if (contractRef && !this.contracts.has(contractRef)) {
          this.addValidationResult(
            'error',
            `Contract reference not found: ${contractRef}`,
            depInfo.path,
            { dependency: fileName, contract: contractRef }
          );
        }
      }
    }
  }

  /**
   * Validate architecture diagram consistency
   */
  validateArchitectureDiagramConsistency() {
    console.log('Validating architecture diagram consistency...');

    const l2DiagramPath = path.join(this.docsDir, 'architecture', 'l2.mmd');
    if (!fs.existsSync(l2DiagramPath)) {
      this.addValidationResult(
        'error',
        'L2 architecture diagram not found',
        l2DiagramPath
      );
      return;
    }

    try {
      const diagramContent = fs.readFileSync(l2DiagramPath, 'utf8');
      
      // Check if all services are represented in the diagram
      for (const serviceName of this.services.keys()) {
        const nodeId = serviceName.replace(/[^a-zA-Z0-9]/g, '_');
        if (!diagramContent.includes(nodeId)) {
          this.addValidationResult(
            'warning',
            `Service not found in L2 diagram: ${serviceName}`,
            l2DiagramPath,
            { service: serviceName }
          );
        }
      }

      // Check for orphaned nodes in diagram (services not in catalog)
      const nodeMatches = diagramContent.match(/(\w+)\["/g);
      if (nodeMatches) {
        for (const match of nodeMatches) {
          const nodeId = match.replace(/\["/, '');
          const serviceName = nodeId.replace(/_/g, '-');
          
          if (!this.services.has(serviceName) && !serviceName.includes('external')) {
            this.addValidationResult(
              'warning',
              `Diagram node not found in service catalog: ${serviceName}`,
              l2DiagramPath,
              { node: nodeId }
            );
          }
        }
      }
    } catch (error) {
      this.addValidationResult(
        'error',
        `Failed to read L2 diagram: ${error.message}`,
        l2DiagramPath
      );
    }
  }

  /**
   * Validate documentation completeness
   */
  validateDocumentationCompleteness() {
    console.log('Validating documentation completeness...');

    // Check that each service has required documentation
    for (const [serviceName, serviceInfo] of this.services) {
      const service = serviceInfo.data;

      // Check for missing required fields
      const requiredFields = ['name', 'purpose', 'owner', 'health', 'runbook'];
      for (const field of requiredFields) {
        if (!service[field]) {
          this.addValidationResult(
            'error',
            `Missing required field: ${field}`,
            serviceInfo.path,
            { service: serviceName, field: field }
          );
        }
      }

      // Check for API documentation
      if (!service.openapi && !service.asyncapi) {
        this.addValidationResult(
          'warning',
          'Service has no API documentation (OpenAPI or AsyncAPI)',
          serviceInfo.path,
          { service: serviceName }
        );
      }
    }

    // Check for orphaned contracts (contracts without corresponding services)
    for (const [contractName, contractInfo] of this.contracts) {
      let hasCorrespondingService = false;
      
      for (const [serviceName, serviceInfo] of this.services) {
        const service = serviceInfo.data;
        const openApiName = service.openapi ? 
          path.basename(service.openapi, '.openapi.yaml') : null;
        const asyncApiName = service.asyncapi ? 
          path.basename(service.asyncapi, '.asyncapi.yaml') : null;
        
        if (openApiName === contractName || asyncApiName === contractName) {
          hasCorrespondingService = true;
          break;
        }
      }

      if (!hasCorrespondingService) {
        this.addValidationResult(
          'warning',
          `Orphaned contract (no corresponding service): ${contractName}`,
          contractInfo.path,
          { contract: contractName }
        );
      }
    }

    // Check for orphaned runbooks
    for (const [runbookName, runbookInfo] of this.runbooks) {
      let hasCorrespondingService = false;
      
      for (const [serviceName, serviceInfo] of this.services) {
        const service = serviceInfo.data;
        const runbookFileName = service.runbook ? 
          path.basename(service.runbook, '.md') : null;
        
        if (runbookFileName === runbookName) {
          hasCorrespondingService = true;
          break;
        }
      }

      if (!hasCorrespondingService) {
        this.addValidationResult(
          'info',
          `Runbook not referenced by any service: ${runbookName}`,
          runbookInfo.path,
          { runbook: runbookName }
        );
      }
    }
  }

  /**
   * Resolve relative path from a base file
   */
  resolveRelativePath(basePath, relativePath) {
    const baseDir = path.dirname(basePath);
    return path.resolve(baseDir, relativePath);
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
   * Run comprehensive validation
   */
  validate() {
    console.log('Starting comprehensive documentation validation...');
    
    this.validationResults = [];
    this.loadAllDocumentation();

    this.validateServiceCrossReferences();
    this.validateDependencyCrossReferences();
    this.validateArchitectureDiagramConsistency();
    this.validateDocumentationCompleteness();

    return this.generateValidationReport();
  }

  /**
   * Generate validation report
   */
  generateValidationReport() {
    const errors = this.validationResults.filter(r => r.level === 'error');
    const warnings = this.validationResults.filter(r => r.level === 'warning');
    const infos = this.validationResults.filter(r => r.level === 'info');

    const lines = [];
    lines.push('# Comprehensive Documentation Validation Report');
    lines.push('');
    lines.push(`Generated: ${new Date().toISOString()}`);
    lines.push('');

    // Summary
    lines.push('## Summary');
    lines.push(`- Total Issues: ${this.validationResults.length}`);
    lines.push(`- Errors: ${errors.length}`);
    lines.push(`- Warnings: ${warnings.length}`);
    lines.push(`- Info: ${infos.length}`);
    lines.push(`- Status: ${errors.length === 0 ? '✅ VALID' : '❌ VALIDATION ERRORS'}`);
    lines.push('');

    // Documentation Statistics
    lines.push('## Documentation Statistics');
    lines.push(`- Services: ${this.services.size}`);
    lines.push(`- Contracts: ${this.contracts.size}`);
    lines.push(`- Dependencies: ${this.dependencies.size}`);
    lines.push(`- Runbooks: ${this.runbooks.size}`);
    lines.push(`- Architecture Diagrams: ${this.architectureDiagrams.size}`);
    lines.push('');

    // Errors
    if (errors.length > 0) {
      lines.push('## Errors');
      for (const error of errors) {
        lines.push(`- **${error.message}**`);
        if (error.filePath) {
          lines.push(`  - File: ${error.filePath}`);
        }
        if (error.details) {
          lines.push(`  - Details: ${JSON.stringify(error.details)}`);
        }
      }
      lines.push('');
    }

    // Warnings
    if (warnings.length > 0) {
      lines.push('## Warnings');
      for (const warning of warnings) {
        lines.push(`- **${warning.message}**`);
        if (warning.filePath) {
          lines.push(`  - File: ${warning.filePath}`);
        }
        if (warning.details) {
          lines.push(`  - Details: ${JSON.stringify(warning.details)}`);
        }
      }
      lines.push('');
    }

    // Info
    if (infos.length > 0) {
      lines.push('## Information');
      for (const info of infos) {
        lines.push(`- **${info.message}**`);
        if (info.filePath) {
          lines.push(`  - File: ${info.filePath}`);
        }
        if (info.details) {
          lines.push(`  - Details: ${JSON.stringify(info.details)}`);
        }
      }
      lines.push('');
    }

    const report = lines.join('\n');
    
    // Write report
    const reportPath = path.join(this.docsDir, 'validation-report.md');
    fs.writeFileSync(reportPath, report);

    console.log(`Comprehensive validation report generated: ${reportPath}`);

    return {
      valid: errors.length === 0,
      errors: errors,
      warnings: warnings,
      infos: infos,
      reportPath: reportPath,
      stats: {
        services: this.services.size,
        contracts: this.contracts.size,
        dependencies: this.dependencies.size,
        runbooks: this.runbooks.size,
        architectureDiagrams: this.architectureDiagrams.size
      }
    };
  }
}

// CLI interface
if (import.meta.url === `file://${process.argv[1]}`) {
  const validator = new DocumentationValidator();
  
  try {
    const result = validator.validate();
    
    if (result.valid) {
      console.log('✅ All documentation is valid');
      process.exit(0);
    } else {
      console.log('❌ Documentation validation failed');
      process.exit(1);
    }
  } catch (error) {
    console.error('❌ Failed to validate documentation:', error.message);
    process.exit(1);
  }
}

export default DocumentationValidator;
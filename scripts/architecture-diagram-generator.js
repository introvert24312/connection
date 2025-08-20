#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Architecture Diagram Generator
 * Generates Mermaid L2 architecture diagrams from service catalog
 */
class ArchitectureDiagramGenerator {
  constructor(servicesDir = 'docs/services', outputDir = 'docs/architecture') {
    this.servicesDir = servicesDir;
    this.outputDir = outputDir;
    this.services = new Map();
    this.dependencies = new Map();
  }

  /**
   * Load all service catalog files
   */
  loadServices() {
    if (!fs.existsSync(this.servicesDir)) {
      throw new Error(`Services directory not found: ${this.servicesDir}`);
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
          
          // Track dependencies
          if (service.depends_on && Array.isArray(service.depends_on)) {
            this.dependencies.set(service.name, service.depends_on);
          }
        }
      } catch (error) {
        console.warn(`Warning: Failed to parse ${file}: ${error.message}`);
      }
    }

    console.log(`Loaded ${this.services.size} services`);
  }

  /**
   * Generate Mermaid diagram content
   */
  generateMermaidDiagram() {
    const lines = [];
    lines.push('graph TD');
    lines.push('    %% L2 Architecture Diagram - Generated from Service Catalog');
    lines.push('');

    // Add service nodes
    for (const [serviceName, service] of this.services) {
      const nodeId = this.sanitizeNodeId(serviceName);
      const displayName = service.purpose ? 
        `${serviceName}<br/>${service.purpose}` : 
        serviceName;
      
      lines.push(`    ${nodeId}["${displayName}"]`);
    }

    lines.push('');

    // Add dependency relationships
    for (const [serviceName, deps] of this.dependencies) {
      const sourceId = this.sanitizeNodeId(serviceName);
      
      for (const dep of deps) {
        const targetId = this.sanitizeNodeId(dep);
        
        // Check if target service exists
        if (this.services.has(dep)) {
          lines.push(`    ${sourceId} --> ${targetId}`);
        } else {
          // Create external dependency node
          lines.push(`    ${targetId}["${dep}<br/>(External)"]`);
          lines.push(`    ${sourceId} --> ${targetId}`);
          lines.push(`    style ${targetId} fill:#ffcccc`);
        }
      }
    }

    lines.push('');
    lines.push('    %% Styling');
    lines.push('    classDef default fill:#e1f5fe,stroke:#01579b,stroke-width:2px');
    lines.push('    classDef external fill:#ffcccc,stroke:#d32f2f,stroke-width:2px');

    return lines.join('\n');
  }

  /**
   * Sanitize service name for use as Mermaid node ID
   */
  sanitizeNodeId(serviceName) {
    return serviceName.replace(/[^a-zA-Z0-9]/g, '_');
  }

  /**
   * Validate that all services and connections are represented
   */
  validateDiagram() {
    const issues = [];

    // Check for orphaned services (no dependencies and not depended upon)
    const dependedUpon = new Set();
    for (const deps of this.dependencies.values()) {
      deps.forEach(dep => dependedUpon.add(dep));
    }

    const orphanedServices = [];
    for (const serviceName of this.services.keys()) {
      const hasDependencies = this.dependencies.has(serviceName);
      const isDependedUpon = dependedUpon.has(serviceName);
      
      if (!hasDependencies && !isDependedUpon) {
        orphanedServices.push(serviceName);
      }
    }

    if (orphanedServices.length > 0) {
      issues.push(`Orphaned services (no connections): ${orphanedServices.join(', ')}`);
    }

    // Check for missing service definitions
    const missingServices = [];
    for (const deps of this.dependencies.values()) {
      for (const dep of deps) {
        if (!this.services.has(dep)) {
          missingServices.push(dep);
        }
      }
    }

    if (missingServices.length > 0) {
      const uniqueMissing = [...new Set(missingServices)];
      issues.push(`Missing service definitions: ${uniqueMissing.join(', ')}`);
    }

    return {
      valid: issues.length === 0,
      issues,
      stats: {
        totalServices: this.services.size,
        servicesWithDependencies: this.dependencies.size,
        totalDependencies: Array.from(this.dependencies.values()).flat().length,
        orphanedServices: orphanedServices.length,
        missingServices: [...new Set(missingServices)].length
      }
    };
  }

  /**
   * Generate architecture diagram file
   */
  generate() {
    // Ensure output directory exists
    if (!fs.existsSync(this.outputDir)) {
      fs.mkdirSync(this.outputDir, { recursive: true });
    }

    // Load services
    this.loadServices();

    // Generate diagram
    const diagramContent = this.generateMermaidDiagram();

    // Validate diagram
    const validation = this.validateDiagram();

    // Write diagram file
    const outputPath = path.join(this.outputDir, 'l2.mmd');
    fs.writeFileSync(outputPath, diagramContent);

    // Generate validation report
    const reportContent = this.generateValidationReport(validation);
    const reportPath = path.join(this.outputDir, 'l2-validation-report.md');
    fs.writeFileSync(reportPath, reportContent);

    console.log(`Architecture diagram generated: ${outputPath}`);
    console.log(`Validation report generated: ${reportPath}`);

    if (!validation.valid) {
      console.warn('Validation issues found:');
      validation.issues.forEach(issue => console.warn(`  - ${issue}`));
    }

    return {
      diagramPath: outputPath,
      reportPath: reportPath,
      validation
    };
  }

  /**
   * Generate validation report
   */
  generateValidationReport(validation) {
    const lines = [];
    lines.push('# L2 Architecture Diagram Validation Report');
    lines.push('');
    lines.push(`Generated: ${new Date().toISOString()}`);
    lines.push('');
    
    lines.push('## Statistics');
    lines.push(`- Total Services: ${validation.stats.totalServices}`);
    lines.push(`- Services with Dependencies: ${validation.stats.servicesWithDependencies}`);
    lines.push(`- Total Dependencies: ${validation.stats.totalDependencies}`);
    lines.push(`- Orphaned Services: ${validation.stats.orphanedServices}`);
    lines.push(`- Missing Services: ${validation.stats.missingServices}`);
    lines.push('');

    lines.push('## Validation Status');
    lines.push(`Status: ${validation.valid ? '✅ VALID' : '❌ ISSUES FOUND'}`);
    lines.push('');

    if (validation.issues.length > 0) {
      lines.push('## Issues');
      validation.issues.forEach(issue => {
        lines.push(`- ${issue}`);
      });
      lines.push('');
    }

    lines.push('## Service List');
    for (const [serviceName, service] of this.services) {
      const deps = this.dependencies.get(serviceName) || [];
      lines.push(`- **${serviceName}**: ${service.purpose || 'No description'}`);
      if (deps.length > 0) {
        lines.push(`  - Dependencies: ${deps.join(', ')}`);
      }
    }

    return lines.join('\n');
  }
}

// CLI interface
if (import.meta.url === `file://${process.argv[1]}`) {
  const generator = new ArchitectureDiagramGenerator();
  
  try {
    const result = generator.generate();
    
    if (result.validation.valid) {
      console.log('✅ Architecture diagram generated successfully');
      process.exit(0);
    } else {
      console.log('⚠️  Architecture diagram generated with validation issues');
      process.exit(1);
    }
  } catch (error) {
    console.error('❌ Failed to generate architecture diagram:', error.message);
    process.exit(1);
  }
}

export default ArchitectureDiagramGenerator;
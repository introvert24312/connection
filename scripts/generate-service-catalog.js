#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

class ServiceCatalogGenerator {
  constructor() {
    this.services = [];
    this.projectRoot = path.resolve(__dirname, '..');
  }

  // Scan the codebase for service-like components
  async scanForServices() {
    console.log('🔍 Scanning codebase for services...');
    
    // Define patterns that indicate a service
    const servicePatterns = [
      { pattern: /class\s+(\w*Service)\s*:/, type: 'service' },
      { pattern: /class\s+(\w*Manager)\s*:/, type: 'manager' },
      { pattern: /class\s+(\w*API)\s*:/, type: 'api' },
      { pattern: /class\s+(\w*Client)\s*:/, type: 'client' },
      { pattern: /class\s+(\w*Gateway)\s*:/, type: 'gateway' },
      { pattern: /class\s+(\w*Controller)\s*:/, type: 'controller' }
    ];

    // Scan Swift files
    await this.scanDirectory('WordTagger', servicePatterns, '.swift');
    
    // Scan JavaScript/Node.js files
    await this.scanDirectory('scripts', servicePatterns, '.js');
    
    // Add the main application as a service
    this.addMainApplicationService();
    
    // Add validation service (this governance framework)
    this.addGovernanceValidationService();

    console.log(`✅ Found ${this.services.length} services`);
    return this.services;
  }

  async scanDirectory(dirPath, patterns, extension) {
    const fullDirPath = path.join(this.projectRoot, dirPath);
    
    if (!fs.existsSync(fullDirPath)) {
      console.log(`⚠️ Directory not found: ${dirPath}`);
      return;
    }

    const files = fs.readdirSync(fullDirPath)
      .filter(file => file.endsWith(extension))
      .filter(file => !file.startsWith('.'));

    for (const file of files) {
      const filePath = path.join(fullDirPath, file);
      await this.analyzeFile(filePath, patterns, dirPath);
    }
  }

  async analyzeFile(filePath, patterns, baseDir) {
    try {
      const content = fs.readFileSync(filePath, 'utf8');
      const fileName = path.basename(filePath);
      
      for (const { pattern, type } of patterns) {
        const matches = content.match(pattern);
        if (matches) {
          const serviceName = matches[1];
          const service = this.extractServiceInfo(serviceName, content, fileName, type, baseDir);
          if (service) {
            this.services.push(service);
            console.log(`  📦 Found ${type}: ${serviceName} in ${fileName}`);
          }
        }
      }
    } catch (error) {
      console.error(`❌ Error analyzing file ${filePath}:`, error.message);
    }
  }

  extractServiceInfo(serviceName, content, fileName, type, baseDir) {
    // Convert service name to kebab-case for consistency
    const kebabName = this.toKebabCase(serviceName);
    
    // Extract purpose from comments or class documentation
    const purpose = this.extractPurpose(content, serviceName) || this.generateDefaultPurpose(serviceName, type);
    
    // Determine health endpoint (if applicable)
    const health = this.extractHealthEndpoint(content) || '/health';
    
    // Extract dependencies
    const dependencies = this.extractDependencies(content);
    
    // Determine owner based on file location and content
    const owner = this.determineOwner(baseDir, fileName);

    return {
      name: kebabName,
      purpose: purpose,
      owner: owner,
      health: health,
      depends_on: dependencies,
      runbook: `../runbooks/${kebabName}.md`,
      // Additional metadata for generation
      _metadata: {
        originalName: serviceName,
        fileName: fileName,
        type: type,
        baseDir: baseDir
      }
    };
  }

  extractPurpose(content, serviceName) {
    // Look for MARK comments first (they're more descriptive)
    const markRegex = /\/\/\s*MARK:\s*-\s*([^\n\r]+)/g;
    let markMatch;
    while ((markMatch = markRegex.exec(content)) !== null) {
      const markText = markMatch[1].trim();
      if (markText.toLowerCase().includes(serviceName.toLowerCase()) || 
          markText.toLowerCase().includes('service') ||
          markText.toLowerCase().includes('manager')) {
        return this.sanitizeYamlString(markText);
      }
    }

    // Look for comments above the class declaration
    const classRegex = new RegExp(`//.*\\n.*class\\s+${serviceName}`, 'i');
    const match = content.match(classRegex);
    if (match) {
      const comment = match[0].split('//')[1]?.split('\\n')[0]?.trim();
      if (comment && comment.length > 0) {
        return this.sanitizeYamlString(comment);
      }
    }

    return null;
  }

  // Sanitize strings for YAML compatibility
  sanitizeYamlString(str) {
    if (!str) return str;
    
    // Remove problematic characters and normalize
    return str
      .replace(/\\n/g, ' ')       // Replace literal \n with spaces
      .replace(/\\t/g, ' ')       // Replace literal \t with spaces
      .replace(/[\r\n\t]/g, ' ')  // Replace actual newlines and tabs with spaces
      .replace(/[:"'`]/g, '')     // Remove YAML special characters
      .replace(/\s+/g, ' ')       // Normalize multiple spaces
      .trim();
  }

  generateDefaultPurpose(serviceName, type) {
    const typeDescriptions = {
      'service': 'Provides core business logic and functionality',
      'manager': 'Manages and coordinates system resources',
      'api': 'Handles API requests and responses',
      'client': 'Interfaces with external systems',
      'gateway': 'Routes and manages service communications',
      'controller': 'Controls application flow and user interactions'
    };

    const baseDescription = typeDescriptions[type] || 'Handles application functionality';
    return `${serviceName} - ${baseDescription}`;
  }

  extractHealthEndpoint(content) {
    // Look for health-related endpoints or methods
    const healthPatterns = [
      /["']\/health["']/,
      /["']\/healthz["']/,
      /["']\/status["']/,
      /["']\/ping["']/,
      /func\s+health/i,
      /func\s+status/i
    ];

    for (const pattern of healthPatterns) {
      const match = content.match(pattern);
      if (match) {
        if (match[0].includes('/')) {
          return match[0].replace(/["']/g, '');
        } else {
          return '/health'; // Default if we found a health function
        }
      }
    }

    return null;
  }

  extractDependencies(content) {
    const dependencies = [];
    
    // Look for import statements and service references
    const importPatterns = [
      /import\s+(\w+Service)/g,
      /import\s+(\w+Manager)/g,
      /import\s+(\w+Client)/g
    ];

    for (const pattern of importPatterns) {
      let match;
      while ((match = pattern.exec(content)) !== null) {
        const depName = this.toKebabCase(match[1]);
        if (!dependencies.includes(depName)) {
          dependencies.push(depName);
        }
      }
    }

    // Look for property declarations that reference other services
    const propertyPatterns = [
      /private\s+let\s+\w*\s*=\s*(\w+Service)/g,
      /private\s+let\s+\w*\s*=\s*(\w+Manager)/g,
      /@\w+\s+private\s+var\s+\w*:\s*(\w+Service)/g
    ];

    for (const pattern of propertyPatterns) {
      let match;
      while ((match = pattern.exec(content)) !== null) {
        const depName = this.toKebabCase(match[1]);
        if (!dependencies.includes(depName)) {
          dependencies.push(depName);
        }
      }
    }

    return dependencies;
  }

  determineOwner(baseDir, fileName) {
    // Default owner based on directory structure
    const ownerMap = {
      'WordTagger': 'WordTagger Team @wordtagger-oncall',
      'scripts': 'Platform Team @platform-oncall',
      'tests': 'QA Team @qa-oncall'
    };

    return ownerMap[baseDir] || 'Development Team @dev-oncall';
  }

  addMainApplicationService() {
    this.services.push({
      name: 'wordtagger-app',
      purpose: 'Main WordTagger macOS application for word and node management',
      owner: 'WordTagger Team @wordtagger-oncall',
      health: '/app/status',
      depends_on: ['external-data-service', 'git-service', 'graph-service', 'search-service'],
      runbook: '../runbooks/wordtagger-app.md'
    });
  }

  addGovernanceValidationService() {
    this.services.push({
      name: 'governance-validation',
      purpose: 'Engineering governance framework validation and compliance checking',
      owner: 'Platform Team @platform-oncall',
      health: '/validate/health',
      depends_on: [],
      runbook: '../runbooks/governance-validation.md'
    });
  }

  // Generate YAML files for discovered services
  async generateServiceCatalogFiles() {
    console.log('\\n📝 Generating service catalog YAML files...');
    
    const servicesDir = path.join(this.projectRoot, 'docs', 'services');
    
    // Ensure services directory exists
    if (!fs.existsSync(servicesDir)) {
      fs.mkdirSync(servicesDir, { recursive: true });
      console.log(`✅ Created services directory: ${servicesDir}`);
    }

    for (const service of this.services) {
      const fileName = `${service.name}.yaml`;
      const filePath = path.join(servicesDir, fileName);
      
      const yamlContent = this.generateServiceYaml(service);
      
      fs.writeFileSync(filePath, yamlContent);
      console.log(`  ✅ Generated: ${fileName}`);
    }

    console.log(`\\n🎉 Generated ${this.services.length} service catalog files in docs/services/`);
  }

  generateServiceYaml(service) {
    let yaml = `name: ${service.name}\n`;
    yaml += `purpose: ${this.sanitizeYamlString(service.purpose)}\n`;
    yaml += `owner: ${service.owner}\n`;
    yaml += `health: ${service.health}\n`;
    
    // Add optional fields if they exist
    if (service.openapi) {
      yaml += `openapi: ${service.openapi}\n`;
    }
    
    if (service.asyncapi) {
      yaml += `asyncapi: ${service.asyncapi}\n`;
    }
    
    if (service.depends_on && service.depends_on.length > 0) {
      yaml += `depends_on:\n`;
      for (const dep of service.depends_on) {
        yaml += `  - ${dep}\n`;
      }
    }
    
    yaml += `runbook: ${service.runbook}\n`;
    
    return yaml;
  }

  // Generate basic runbook files
  async generateRunbookFiles() {
    console.log('\\n📚 Generating basic runbook files...');
    
    const runbooksDir = path.join(this.projectRoot, 'docs', 'runbooks');
    
    // Ensure runbooks directory exists
    if (!fs.existsSync(runbooksDir)) {
      fs.mkdirSync(runbooksDir, { recursive: true });
      console.log(`✅ Created runbooks directory: ${runbooksDir}`);
    }

    for (const service of this.services) {
      const fileName = `${service.name}.md`;
      const filePath = path.join(runbooksDir, fileName);
      
      // Only create if file doesn't exist
      if (!fs.existsSync(filePath)) {
        const runbookContent = this.generateRunbookContent(service);
        fs.writeFileSync(filePath, runbookContent);
        console.log(`  ✅ Generated: ${fileName}`);
      } else {
        console.log(`  ⏭️ Skipped (exists): ${fileName}`);
      }
    }
  }

  generateRunbookContent(service) {
    return `# ${service.name} Runbook

## Service Overview

**Name:** ${service.name}  
**Purpose:** ${service.purpose}  
**Owner:** ${service.owner}  
**Health Check:** ${service.health}  

## Dependencies

${service.depends_on && service.depends_on.length > 0 
  ? service.depends_on.map(dep => `- ${dep}`).join('\n')
  : 'No dependencies'
}

## Common Issues

### Service Not Responding

**Symptoms:**
- Health check endpoint returns 5xx errors
- Service appears unresponsive

**Troubleshooting Steps:**
1. Check service logs for errors
2. Verify dependencies are healthy
3. Check system resources (CPU, memory, disk)
4. Restart service if necessary

### Performance Issues

**Symptoms:**
- Slow response times
- High resource usage

**Troubleshooting Steps:**
1. Monitor service metrics
2. Check for resource bottlenecks
3. Review recent changes
4. Scale service if needed

## Monitoring

- **Health Check:** ${service.health}
- **Logs:** Check application logs for errors and warnings
- **Metrics:** Monitor key performance indicators

## Escalation

For issues that cannot be resolved using this runbook:
1. Contact ${service.owner}
2. Create incident ticket with detailed information
3. Follow standard escalation procedures

## Recent Changes

<!-- Document recent changes that might affect service behavior -->

---
*Last updated: ${new Date().toISOString().split('T')[0]}*
*Generated by service catalog generator*
`;
  }

  // Utility function to convert PascalCase to kebab-case
  toKebabCase(str) {
    return str
      .replace(/([A-Z])([A-Z][a-z])/g, '$1-$2')  // Handle consecutive capitals like "HTTPClient" -> "HTTP-Client"
      .replace(/([a-z0-9])([A-Z])/g, '$1-$2')    // Handle normal camelCase
      .toLowerCase();
  }

  // Main execution method
  async generate() {
    console.log('🚀 Starting service catalog generation...\\n');
    
    try {
      await this.scanForServices();
      await this.generateServiceCatalogFiles();
      await this.generateRunbookFiles();
      
      console.log('\\n✅ Service catalog generation completed successfully!');
      console.log('\\n📋 Summary:');
      console.log(`   - Services discovered: ${this.services.length}`);
      console.log(`   - YAML files generated: ${this.services.length}`);
      console.log(`   - Runbook files generated: ${this.services.length}`);
      console.log('\\n💡 Next steps:');
      console.log('   1. Review generated service catalog files in docs/services/');
      console.log('   2. Update service descriptions and metadata as needed');
      console.log('   3. Complete runbook documentation in docs/runbooks/');
      console.log('   4. Run validation: npm run validate:services');
      
    } catch (error) {
      console.error('❌ Service catalog generation failed:', error);
      process.exit(1);
    }
  }
}

// CLI usage
if (import.meta.url === `file://${process.argv[1]}`) {
  const generator = new ServiceCatalogGenerator();
  generator.generate();
}

export default ServiceCatalogGenerator;
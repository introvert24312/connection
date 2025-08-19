#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import Ajv from 'ajv';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

class GovernanceValidator {
  constructor() {
    this.ajv = new Ajv({ allErrors: true });
    this.schemas = {};
    this.loadSchemas();
  }

  loadSchemas() {
    try {
      // Load service catalog schema
      const serviceCatalogSchema = JSON.parse(
        fs.readFileSync(path.join(__dirname, '../schemas/service-catalog.schema.json'), 'utf8')
      );
      this.schemas.serviceCatalog = this.ajv.compile(serviceCatalogSchema);

      // Load dependency schema
      const dependencySchema = JSON.parse(
        fs.readFileSync(path.join(__dirname, '../schemas/dependency.schema.json'), 'utf8')
      );
      this.schemas.dependency = this.ajv.compile(dependencySchema);

      console.log('✓ Schemas loaded successfully');
    } catch (error) {
      console.error('✗ Failed to load schemas:', error.message);
      process.exit(1);
    }
  }

  validateYamlFile(filePath, schemaType) {
    try {
      // Check if file exists
      if (!fs.existsSync(filePath)) {
        return { valid: false, errors: [`File not found: ${filePath}`] };
      }

      // Read and parse YAML
      const fileContent = fs.readFileSync(filePath, 'utf8');
      const data = yaml.load(fileContent);

      // Validate against schema
      const validator = this.schemas[schemaType];
      if (!validator) {
        return { valid: false, errors: [`Unknown schema type: ${schemaType}`] };
      }

      const valid = validator(data);
      if (!valid) {
        const errors = validator.errors.map(err => 
          `${err.instancePath || 'root'}: ${err.message}`
        );
        return { valid: false, errors };
      }

      return { valid: true, errors: [] };
    } catch (error) {
      return { valid: false, errors: [`YAML parsing error: ${error.message}`] };
    }
  }

  validateServiceCatalog(servicesDir = 'docs/services') {
    console.log('\n=== Validating Service Catalog ===');
    
    if (!fs.existsSync(servicesDir)) {
      console.log(`⚠ Services directory not found: ${servicesDir}`);
      return true; // Not an error if directory doesn't exist yet
    }

    const files = fs.readdirSync(servicesDir)
      .filter(file => file.endsWith('.yaml') || file.endsWith('.yml'))
      .filter(file => !file.startsWith('.'));

    if (files.length === 0) {
      console.log('⚠ No service catalog files found');
      return true;
    }

    console.log(`📋 Found ${files.length} service catalog files to validate`);
    
    let allValid = true;
    let validCount = 0;
    let errorCount = 0;
    const detailedErrors = [];

    for (const file of files) {
      const filePath = path.join(servicesDir, file);
      const result = this.validateYamlFile(filePath, 'serviceCatalog');
      
      if (result.valid) {
        console.log(`✓ ${file}`);
        validCount++;
      } else {
        console.log(`✗ ${file}:`);
        result.errors.forEach((error, index) => {
          console.log(`  - ${error}`);
          detailedErrors.push({
            file: file,
            filePath: filePath,
            error: error,
            errorIndex: index + 1
          });
        });
        errorCount += result.errors.length;
        allValid = false;
      }
    }

    // Print detailed summary
    console.log('\n📊 Validation Summary:');
    console.log(`   ✅ Valid files: ${validCount}/${files.length}`);
    if (errorCount > 0) {
      console.log(`   ❌ Files with errors: ${files.length - validCount}`);
      console.log(`   🔍 Total errors: ${errorCount}`);
      
      // Group errors by type for better reporting
      const errorsByType = this.groupErrorsByType(detailedErrors);
      console.log('\n🔍 Error Breakdown:');
      for (const [errorType, errors] of Object.entries(errorsByType)) {
        console.log(`   ${errorType}: ${errors.length} occurrences`);
        if (errors.length <= 3) {
          errors.forEach(err => console.log(`     - ${err.file}: ${err.error}`));
        } else {
          errors.slice(0, 2).forEach(err => console.log(`     - ${err.file}: ${err.error}`));
          console.log(`     ... and ${errors.length - 2} more`);
        }
      }
    }

    return allValid;
  }

  // Group errors by type for better reporting
  groupErrorsByType(detailedErrors) {
    const groups = {};
    
    for (const errorDetail of detailedErrors) {
      let errorType = 'Other';
      
      if (errorDetail.error.includes('required property')) {
        errorType = 'Missing Required Fields';
      } else if (errorDetail.error.includes('must match pattern')) {
        errorType = 'Invalid Format';
      } else if (errorDetail.error.includes('YAML parsing error')) {
        errorType = 'YAML Syntax Errors';
      } else if (errorDetail.error.includes('additional properties')) {
        errorType = 'Extra Fields';
      } else if (errorDetail.error.includes('must be string')) {
        errorType = 'Type Errors';
      } else if (errorDetail.error.includes('must NOT have fewer than')) {
        errorType = 'Empty Fields';
      } else if (errorDetail.error.includes('must NOT have more than')) {
        errorType = 'Field Too Long';
      } else if (errorDetail.error.includes('duplicate items')) {
        errorType = 'Duplicate Values';
      }
      
      if (!groups[errorType]) {
        groups[errorType] = [];
      }
      groups[errorType].push(errorDetail);
    }
    
    return groups;
  }

  validateDependencies(dependenciesDir = 'docs/dependencies') {
    console.log('\n=== Validating Dependencies ===');
    
    if (!fs.existsSync(dependenciesDir)) {
      console.log(`⚠ Dependencies directory not found: ${dependenciesDir}`);
      return true; // Not an error if directory doesn't exist yet
    }

    const files = fs.readdirSync(dependenciesDir)
      .filter(file => file.endsWith('.yaml') || file.endsWith('.yml'))
      .filter(file => !file.startsWith('.'));

    if (files.length === 0) {
      console.log('⚠ No dependency files found');
      return true;
    }

    let allValid = true;
    for (const file of files) {
      const filePath = path.join(dependenciesDir, file);
      const result = this.validateYamlFile(filePath, 'dependency');
      
      if (result.valid) {
        console.log(`✓ ${file}`);
      } else {
        console.log(`✗ ${file}:`);
        result.errors.forEach(error => console.log(`  - ${error}`));
        allValid = false;
      }
    }

    return allValid;
  }

  validateOpenAPI(contractsDir = 'docs/contracts/http') {
    console.log('\n=== Validating OpenAPI Contracts ===');
    
    if (!fs.existsSync(contractsDir)) {
      console.log(`⚠ OpenAPI contracts directory not found: ${contractsDir}`);
      return true;
    }

    const files = fs.readdirSync(contractsDir)
      .filter(file => file.endsWith('.openapi.yaml') || file.endsWith('.openapi.yml'))
      .filter(file => !file.startsWith('.'));

    if (files.length === 0) {
      console.log('⚠ No OpenAPI contract files found');
      return true;
    }

    console.log(`📋 Found ${files.length} OpenAPI contract files to validate`);
    
    let allValid = true;
    for (const file of files) {
      const filePath = path.join(contractsDir, file);
      try {
        const fileContent = fs.readFileSync(filePath, 'utf8');
        const data = yaml.load(fileContent);
        
        // Check if YAML was parsed successfully
        if (!data || typeof data !== 'object') {
          console.log(`✗ ${file}: Invalid YAML structure`);
          allValid = false;
          continue;
        }
        
        // Basic OpenAPI validation
        if (!data.openapi || !data.info || !data.paths) {
          console.log(`✗ ${file}: Missing required OpenAPI fields (openapi, info, paths)`);
          allValid = false;
        } else {
          console.log(`✓ ${file}`);
        }
      } catch (error) {
        console.log(`✗ ${file}: YAML parsing error - ${error.message}`);
        allValid = false;
      }
    }

    return allValid;
  }

  validateAsyncAPI(contractsDir = 'docs/contracts/events') {
    console.log('\n=== Validating AsyncAPI Contracts ===');
    
    if (!fs.existsSync(contractsDir)) {
      console.log(`⚠ AsyncAPI contracts directory not found: ${contractsDir}`);
      return true;
    }

    const files = fs.readdirSync(contractsDir)
      .filter(file => file.endsWith('.asyncapi.yaml') || file.endsWith('.asyncapi.yml'))
      .filter(file => !file.startsWith('.'));

    if (files.length === 0) {
      console.log('⚠ No AsyncAPI contract files found');
      return true;
    }

    console.log(`📋 Found ${files.length} AsyncAPI contract files to validate`);
    
    let allValid = true;
    for (const file of files) {
      const filePath = path.join(contractsDir, file);
      try {
        const fileContent = fs.readFileSync(filePath, 'utf8');
        const data = yaml.load(fileContent);
        
        // Basic AsyncAPI validation
        if (!data.asyncapi || !data.info || !data.channels) {
          console.log(`✗ ${file}: Missing required AsyncAPI fields (asyncapi, info, channels)`);
          allValid = false;
        } else {
          console.log(`✓ ${file}`);
        }
      } catch (error) {
        console.log(`✗ ${file}: YAML parsing error - ${error.message}`);
        allValid = false;
      }
    }

    return allValid;
  }

  checkContractDiff(baseBranch = 'origin/main') {
    console.log('\n=== Checking Contract Breaking Changes ===');
    
    try {
      // Use the enhanced contract diff analyzer
      const result = execSync(`node scripts/contract-diff-analyzer.js --base=${baseBranch}`, { 
        encoding: 'utf8',
        stdio: 'pipe'
      });
      
      console.log(result);
      return true; // If no exception, analysis passed
      
    } catch (error) {
      // If the analyzer exits with non-zero code, there were breaking changes
      if (error.stdout) {
        console.log(error.stdout);
      }
      if (error.stderr) {
        console.error(error.stderr);
      }
      
      return false; // Breaking changes detected
    }
  }

  checkDocumentationSync() {
    console.log('\n=== Checking Contract-Service Synchronization ===');
    
    const servicesDir = 'docs/services';
    const httpContractsDir = 'docs/contracts/http';
    const eventContractsDir = 'docs/contracts/events';
    
    let allSynced = true;
    
    // Check if services reference existing contracts
    if (fs.existsSync(servicesDir)) {
      const serviceFiles = fs.readdirSync(servicesDir)
        .filter(file => file.endsWith('.yaml') || file.endsWith('.yml'));
      
      for (const file of serviceFiles) {
        const filePath = path.join(servicesDir, file);
        try {
          const content = fs.readFileSync(filePath, 'utf8');
          const data = yaml.load(content);
          
          // Check OpenAPI reference
          if (data.openapi) {
            const contractPath = path.resolve(servicesDir, data.openapi);
            if (!fs.existsSync(contractPath)) {
              console.log(`✗ ${file}: Referenced OpenAPI contract not found: ${data.openapi}`);
              allSynced = false;
            }
          }
          
          // Check AsyncAPI reference
          if (data.asyncapi) {
            const contractPath = path.resolve(servicesDir, data.asyncapi);
            if (!fs.existsSync(contractPath)) {
              console.log(`✗ ${file}: Referenced AsyncAPI contract not found: ${data.asyncapi}`);
              allSynced = false;
            }
          }
          
        } catch (error) {
          console.log(`✗ ${file}: Could not parse service file - ${error.message}`);
          allSynced = false;
        }
      }
    }
    
    if (allSynced) {
      console.log('✓ All service-contract references are valid');
    }
    
    return allSynced;
  }

  checkOrphanedContracts() {
    console.log('\n=== Checking for Orphaned Contracts ===');
    
    const servicesDir = 'docs/services';
    const httpContractsDir = 'docs/contracts/http';
    const eventContractsDir = 'docs/contracts/events';
    
    let hasOrphans = false;
    const referencedContracts = new Set();
    
    // Collect all contract references from service files
    if (fs.existsSync(servicesDir)) {
      const serviceFiles = fs.readdirSync(servicesDir)
        .filter(file => file.endsWith('.yaml') || file.endsWith('.yml'));
      
      for (const file of serviceFiles) {
        const filePath = path.join(servicesDir, file);
        try {
          const content = fs.readFileSync(filePath, 'utf8');
          const data = yaml.load(content);
          
          if (data.openapi) {
            referencedContracts.add(path.resolve(servicesDir, data.openapi));
          }
          if (data.asyncapi) {
            referencedContracts.add(path.resolve(servicesDir, data.asyncapi));
          }
        } catch (error) {
          // Skip files that can't be parsed
        }
      }
    }
    
    // Check HTTP contracts
    if (fs.existsSync(httpContractsDir)) {
      const contractFiles = fs.readdirSync(httpContractsDir)
        .filter(file => file.endsWith('.openapi.yaml') || file.endsWith('.openapi.yml'));
      
      for (const file of contractFiles) {
        const fullPath = path.resolve(httpContractsDir, file);
        if (!referencedContracts.has(fullPath)) {
          console.log(`⚠ Orphaned HTTP contract: ${file}`);
          hasOrphans = true;
        }
      }
    }
    
    // Check Event contracts
    if (fs.existsSync(eventContractsDir)) {
      const contractFiles = fs.readdirSync(eventContractsDir)
        .filter(file => file.endsWith('.asyncapi.yaml') || file.endsWith('.asyncapi.yml'));
      
      for (const file of contractFiles) {
        const fullPath = path.resolve(eventContractsDir, file);
        if (!referencedContracts.has(fullPath)) {
          console.log(`⚠ Orphaned Event contract: ${file}`);
          hasOrphans = true;
        }
      }
    }
    
    if (!hasOrphans) {
      console.log('✓ No orphaned contracts found');
    }
    
    return !hasOrphans;
  }

  checkCompleteness() {
    console.log('\n=== Checking Service Catalog Completeness ===');
    
    // This is a placeholder for checking if all running services have catalog entries
    // In a real implementation, this would scan for actual services in the codebase
    console.log('✓ Service catalog completeness check passed (placeholder)');
    return true;
  }

  validateAll() {
    console.log('🔍 Starting governance documentation validation...\n');
    
    const serviceCatalogValid = this.validateServiceCatalog();
    const dependenciesValid = this.validateDependencies();
    
    const allValid = serviceCatalogValid && dependenciesValid;
    
    console.log('\n=== Validation Summary ===');
    if (allValid) {
      console.log('✅ All governance documentation is valid');
      process.exit(0);
    } else {
      console.log('❌ Governance documentation validation failed');
      process.exit(1);
    }
  }
}

// CLI usage
if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  
  // Parse flags
  const flags = {
    catalog: args.includes('--catalog'),
    openapi: args.includes('--openapi'),
    asyncapi: args.includes('--asyncapi'),
    diff: args.includes('--diff'),
    sync: args.includes('--sync'),
    orphans: args.includes('--orphans'),
    completeness: args.includes('--completeness'),
    verbose: args.includes('--verbose') || args.includes('-v'),
    quiet: args.includes('--quiet') || args.includes('-q'),
    help: args.includes('--help') || args.includes('-h')
  };
  
  const baseBranch = args.find(arg => arg.startsWith('--base='))?.split('=')[1] || 'origin/main';
  const customPath = args.find(arg => arg.startsWith('--path='))?.split('=')[1];
  
  if (flags.help) {
    console.log(`
🔍 Governance Validation Tool

Usage: node validate-governance.js [flags] [options]

Validation Flags:
  --catalog         Validate service catalog files only
  --openapi         Validate OpenAPI contract files only
  --asyncapi        Validate AsyncAPI contract files only
  --diff            Check for breaking changes in contracts
  --sync            Check contract-service synchronization
  --orphans         Check for orphaned contracts
  --completeness    Check service catalog completeness

Options:
  --base=<branch>   Base branch for diff comparison (default: origin/main)
  --verbose, -v     Show detailed validation information
  --quiet, -q       Show only errors and summary
  --path=<path>     Use custom path for validation
  --help, -h        Show this help message

Examples:
  node validate-governance.js --catalog
  node validate-governance.js --openapi --verbose
  node validate-governance.js --diff --base=origin/develop
  node validate-governance.js --sync --orphans
`);
    process.exit(0);
  }
  
  const validator = new GovernanceValidator();
  let allValid = true;
  
  // Execute requested validations
  if (flags.catalog) {
    const servicesPath = customPath ? `${customPath}/services` : 'docs/services';
    allValid = validator.validateServiceCatalog(servicesPath) && allValid;
  }
  
  if (flags.openapi) {
    const httpPath = customPath ? `${customPath}/contracts/http` : 'docs/contracts/http';
    allValid = validator.validateOpenAPI(httpPath) && allValid;
  }
  
  if (flags.asyncapi) {
    const eventsPath = customPath ? `${customPath}/contracts/events` : 'docs/contracts/events';
    allValid = validator.validateAsyncAPI(eventsPath) && allValid;
  }
  
  if (flags.diff) {
    allValid = validator.checkContractDiff(baseBranch) && allValid;
  }
  
  if (flags.sync) {
    allValid = validator.checkDocumentationSync() && allValid;
  }
  
  if (flags.orphans) {
    allValid = validator.checkOrphanedContracts() && allValid;
  }
  
  if (flags.completeness) {
    allValid = validator.checkCompleteness() && allValid;
  }
  
  // If no specific flags, run legacy command-based interface
  if (!flags.catalog && !flags.openapi && !flags.asyncapi && !flags.diff && 
      !flags.sync && !flags.orphans && !flags.completeness) {
    const command = args[0];
    
    switch (command) {
      case 'services':
        const servicesPath = customPath ? `${customPath}/services` : 'docs/services';
        allValid = validator.validateServiceCatalog(servicesPath);
        break;
      case 'dependencies':
        const dependenciesPath = customPath ? `${customPath}/dependencies` : 'docs/dependencies';
        allValid = validator.validateDependencies(dependenciesPath);
        break;
      case 'all':
      default:
        validator.validateAll();
        process.exit(0); // validateAll() handles its own exit
    }
  }
  
  // Exit with appropriate code
  process.exit(allValid ? 0 : 1);
}

export default GovernanceValidator;
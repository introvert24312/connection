#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import Ajv from 'ajv';
import { fileURLToPath } from 'url';

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
  const command = process.argv[2];
  const options = process.argv.slice(3);
  
  // Parse options
  const verbose = options.includes('--verbose') || options.includes('-v');
  const quiet = options.includes('--quiet') || options.includes('-q');
  const customPath = options.find(opt => opt.startsWith('--path='))?.split('=')[1];
  
  if (options.includes('--help') || options.includes('-h') || command === '--help' || command === '-h') {
    console.log(`
🔍 Governance Validation Tool

Usage: node validate-governance.js [command] [options]

Commands:
  services      Validate service catalog files only
  dependencies  Validate dependency files only  
  all           Validate all governance files (default)

Options:
  --verbose, -v     Show detailed validation information
  --quiet, -q       Show only errors and summary
  --path=<path>     Use custom path for validation
  --help, -h        Show this help message

Examples:
  node validate-governance.js services
  node validate-governance.js services --verbose
  node validate-governance.js all --path=custom/docs
`);
    process.exit(0);
  }
  
  const validator = new GovernanceValidator();
  
  switch (command) {
    case 'services':
      const servicesPath = customPath ? `${customPath}/services` : 'docs/services';
      validator.validateServiceCatalog(servicesPath) ? process.exit(0) : process.exit(1);
      break;
    case 'dependencies':
      const dependenciesPath = customPath ? `${customPath}/dependencies` : 'docs/dependencies';
      validator.validateDependencies(dependenciesPath) ? process.exit(0) : process.exit(1);
      break;
    case 'all':
    default:
      validator.validateAll();
      break;
  }
}

export default GovernanceValidator;
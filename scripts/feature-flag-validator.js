#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import Ajv from 'ajv';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

class FeatureFlagValidator {
  constructor() {
    this.ajv = new Ajv({ allErrors: true });
    this.schema = this.loadSchema();
  }

  loadSchema() {
    const schemaPath = path.join(__dirname, '..', 'schemas', 'feature-flags.schema.json');
    if (!fs.existsSync(schemaPath)) {
      throw new Error(`Feature flags schema not found at ${schemaPath}`);
    }
    return JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
  }

  validateFile(filePath) {
    try {
      if (!fs.existsSync(filePath)) {
        return {
          valid: false,
          errors: [`Feature flags file not found: ${filePath}`]
        };
      }

      const content = fs.readFileSync(filePath, 'utf8');
      const data = yaml.load(content);

      return this.validateData(data, filePath);
    } catch (error) {
      return {
        valid: false,
        errors: [`Failed to parse ${filePath}: ${error.message}`]
      };
    }
  }

  validateData(data, filePath = 'data') {
    const validate = this.ajv.compile(this.schema);
    const schemaValid = validate(data);
    
    let errors = [];

    // Schema validation errors
    if (!schemaValid) {
      errors = validate.errors.map(error => {
        const path = error.instancePath || 'root';
        return `${filePath}${path}: ${error.message}`;
      });
    }

    // Additional business logic validation (always run if schema is valid)
    if (schemaValid) {
      const businessValidation = this.validateBusinessRules(data);
      if (!businessValidation.valid) {
        errors = errors.concat(businessValidation.errors);
      }
    }

    return { 
      valid: errors.length === 0, 
      errors 
    };
  }

  validateBusinessRules(data) {
    const errors = [];
    const flagNames = new Set();

    // Check for duplicate flag names
    data.flags.forEach((flag, index) => {
      if (flagNames.has(flag.name)) {
        errors.push(`Duplicate flag name '${flag.name}' at index ${index}`);
      }
      flagNames.add(flag.name);
    });

    // Validate flag naming conventions
    data.flags.forEach((flag, index) => {
      if (flag.name.includes('-')) {
        errors.push(`Flag name '${flag.name}' at index ${index} should use underscores, not hyphens`);
      }
    });

    // Warn about flags that default to "on" (should be rare)
    data.flags.forEach((flag, index) => {
      if (flag.default === 'on') {
        console.warn(`Warning: Flag '${flag.name}' at index ${index} defaults to 'on' - consider defaulting to 'off'`);
      }
    });

    return {
      valid: errors.length === 0,
      errors
    };
  }

  validateDirectory(dirPath = 'docs/release') {
    const flagsPath = path.join(dirPath, 'flags.yaml');
    return this.validateFile(flagsPath);
  }
}

// CLI usage
if (import.meta.url === `file://${process.argv[1]}`) {
  const validator = new FeatureFlagValidator();
  const filePath = process.argv[2] || 'docs/release/flags.yaml';
  
  const result = validator.validateFile(filePath);
  
  if (result.valid) {
    console.log('✅ Feature flags validation passed');
    process.exit(0);
  } else {
    console.error('❌ Feature flags validation failed:');
    result.errors.forEach(error => console.error(`  - ${error}`));
    process.exit(1);
  }
}

export default FeatureFlagValidator;
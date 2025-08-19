#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import SwaggerParser from '@apidevtools/swagger-parser';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Contract validation utilities for OpenAPI and AsyncAPI specifications
 */
class ContractValidator {
  constructor() {
    this.parser = new SwaggerParser();
  }

  /**
   * Validate OpenAPI 3.0+ specification
   * @param {string} filePath - Path to OpenAPI specification file
   * @returns {Promise<{valid: boolean, errors: string[], warnings: string[], spec?: object}>}
   */
  async validateOpenAPI(filePath) {
    try {
      // Check if file exists
      if (!fs.existsSync(filePath)) {
        return { 
          valid: false, 
          errors: [`File not found: ${filePath}`],
          warnings: []
        };
      }

      // Read and parse the specification
      const fileContent = fs.readFileSync(filePath, 'utf8');
      let spec;
      
      try {
        if (filePath.endsWith('.yaml') || filePath.endsWith('.yml')) {
          spec = yaml.load(fileContent);
        } else {
          spec = JSON.parse(fileContent);
        }
      } catch (parseError) {
        return {
          valid: false,
          errors: [`Failed to parse specification: ${parseError.message}`],
          warnings: []
        };
      }

      // Validate OpenAPI version
      if (!spec.openapi) {
        return {
          valid: false,
          errors: ['Missing required field: openapi'],
          warnings: []
        };
      }

      if (!spec.openapi.startsWith('3.')) {
        return {
          valid: false,
          errors: [`Unsupported OpenAPI version: ${spec.openapi}. Only OpenAPI 3.0+ is supported.`],
          warnings: []
        };
      }

      // Use swagger-parser for comprehensive validation
      const validatedSpec = await this.parser.validate(spec);
      
      // Additional custom validations
      const customValidation = this.validateOpenAPICustomRules(validatedSpec);
      
      return {
        valid: customValidation.errors.length === 0,
        errors: customValidation.errors,
        warnings: customValidation.warnings,
        spec: validatedSpec
      };

    } catch (error) {
      return {
        valid: false,
        errors: [`Validation error: ${error.message}`],
        warnings: []
      };
    }
  }

  /**
   * Apply custom validation rules for OpenAPI specifications
   * @param {object} spec - Parsed OpenAPI specification
   * @returns {{errors: string[], warnings: string[]}}
   */
  validateOpenAPICustomRules(spec) {
    const errors = [];
    const warnings = [];

    // Check required top-level fields
    const requiredFields = ['info', 'paths'];
    for (const field of requiredFields) {
      if (!spec[field]) {
        errors.push(`Missing required field: ${field}`);
      }
    }

    // Validate info section
    if (spec.info) {
      if (!spec.info.title) {
        errors.push('Missing required field: info.title');
      }
      if (!spec.info.version) {
        errors.push('Missing required field: info.version');
      }
    }

    // Validate paths
    if (spec.paths) {
      const pathCount = Object.keys(spec.paths).length;
      if (pathCount === 0) {
        warnings.push('No paths defined in specification');
      } else if (pathCount < 3) {
        warnings.push(`Only ${pathCount} paths defined. Consider documenting at least 3 critical endpoints.`);
      }

      // Check each path for required elements
      for (const [pathName, pathItem] of Object.entries(spec.paths)) {
        if (!pathItem || typeof pathItem !== 'object') {
          continue;
        }

        const methods = Object.keys(pathItem).filter(key => 
          ['get', 'post', 'put', 'delete', 'patch', 'head', 'options', 'trace'].includes(key.toLowerCase())
        );

        for (const method of methods) {
          const operation = pathItem[method];
          if (!operation) continue;

          const operationId = `${method.toUpperCase()} ${pathName}`;

          // Check for responses
          if (!operation.responses || Object.keys(operation.responses).length === 0) {
            errors.push(`${operationId}: Missing responses definition`);
          } else {
            // Check for success response
            const hasSuccessResponse = Object.keys(operation.responses).some(code => 
              code.startsWith('2') || code === 'default'
            );
            if (!hasSuccessResponse) {
              warnings.push(`${operationId}: No success response (2xx) defined`);
            }

            // Check for error responses
            const hasErrorResponse = Object.keys(operation.responses).some(code => 
              code.startsWith('4') || code.startsWith('5')
            );
            if (!hasErrorResponse) {
              warnings.push(`${operationId}: Consider adding error responses (4xx/5xx)`);
            }
          }

          // Check for operation description
          if (!operation.summary && !operation.description) {
            warnings.push(`${operationId}: Missing operation description`);
          }

          // Check for request body validation on POST/PUT/PATCH
          if (['post', 'put', 'patch'].includes(method.toLowerCase())) {
            if (!operation.requestBody) {
              warnings.push(`${operationId}: Consider adding requestBody for ${method.toUpperCase()} operation`);
            }
          }
        }
      }
    }

    // Check for security definitions
    if (!spec.security && !spec.components?.securitySchemes) {
      warnings.push('No security schemes defined. Consider adding authentication requirements.');
    }

    return { errors, warnings };
  }

  /**
   * Validate AsyncAPI 2.0+ specification
   * @param {string} filePath - Path to AsyncAPI specification file
   * @returns {Promise<{valid: boolean, errors: string[], warnings: string[], spec?: object}>}
   */
  async validateAsyncAPI(filePath) {
    try {
      // Check if file exists
      if (!fs.existsSync(filePath)) {
        return { 
          valid: false, 
          errors: [`File not found: ${filePath}`],
          warnings: []
        };
      }

      // Read and parse the specification
      const fileContent = fs.readFileSync(filePath, 'utf8');
      let spec;
      
      try {
        if (filePath.endsWith('.yaml') || filePath.endsWith('.yml')) {
          spec = yaml.load(fileContent);
        } else {
          spec = JSON.parse(fileContent);
        }
      } catch (parseError) {
        return {
          valid: false,
          errors: [`Failed to parse specification: ${parseError.message}`],
          warnings: []
        };
      }

      // Validate AsyncAPI version
      if (!spec.asyncapi) {
        return {
          valid: false,
          errors: ['Missing required field: asyncapi'],
          warnings: []
        };
      }

      if (!spec.asyncapi.startsWith('2.')) {
        return {
          valid: false,
          errors: [`Unsupported AsyncAPI version: ${spec.asyncapi}. Only AsyncAPI 2.0+ is supported.`],
          warnings: []
        };
      }

      // Apply custom validation rules
      const customValidation = this.validateAsyncAPICustomRules(spec);
      
      return {
        valid: customValidation.errors.length === 0,
        errors: customValidation.errors,
        warnings: customValidation.warnings,
        spec: spec
      };

    } catch (error) {
      return {
        valid: false,
        errors: [`Validation error: ${error.message}`],
        warnings: []
      };
    }
  }

  /**
   * Apply custom validation rules for AsyncAPI specifications
   * @param {object} spec - Parsed AsyncAPI specification
   * @returns {{errors: string[], warnings: string[]}}
   */
  validateAsyncAPICustomRules(spec) {
    const errors = [];
    const warnings = [];

    // Check required top-level fields
    const requiredFields = ['info', 'channels'];
    for (const field of requiredFields) {
      if (!spec[field]) {
        errors.push(`Missing required field: ${field}`);
      }
    }

    // Validate info section
    if (spec.info) {
      if (!spec.info.title) {
        errors.push('Missing required field: info.title');
      }
      if (!spec.info.version) {
        errors.push('Missing required field: info.version');
      }
    }

    // Validate channels
    if (spec.channels) {
      const channelCount = Object.keys(spec.channels).length;
      if (channelCount === 0) {
        warnings.push('No channels defined in specification');
      } else if (channelCount < 1) {
        warnings.push('Consider documenting at least 1 main topic/channel.');
      }

      // Check each channel for required elements
      for (const [channelName, channelItem] of Object.entries(spec.channels)) {
        if (!channelItem || typeof channelItem !== 'object') {
          continue;
        }

        // Check for publish or subscribe operations
        if (!channelItem.publish && !channelItem.subscribe) {
          warnings.push(`Channel ${channelName}: No publish or subscribe operations defined`);
        }

        // Validate publish operation
        if (channelItem.publish) {
          if (!channelItem.publish.message) {
            errors.push(`Channel ${channelName} publish: Missing message definition`);
          }
        }

        // Validate subscribe operation
        if (channelItem.subscribe) {
          if (!channelItem.subscribe.message) {
            errors.push(`Channel ${channelName} subscribe: Missing message definition`);
          }
        }

        // Check for channel description
        if (!channelItem.description) {
          warnings.push(`Channel ${channelName}: Missing description`);
        }
      }
    }

    // Check for message schemas
    if (spec.components?.messages) {
      for (const [messageName, message] of Object.entries(spec.components.messages)) {
        if (!message.payload) {
          warnings.push(`Message ${messageName}: Missing payload schema`);
        }
      }
    }

    return { errors, warnings };
  }

  /**
   * Validate all OpenAPI contracts in a directory
   * @param {string} contractsDir - Directory containing OpenAPI specifications
   * @returns {Promise<{valid: boolean, results: Array}>}
   */
  async validateOpenAPIDirectory(contractsDir = 'docs/contracts/http') {
    console.log('\n=== Validating OpenAPI Contracts ===');
    
    if (!fs.existsSync(contractsDir)) {
      console.log(`⚠ OpenAPI contracts directory not found: ${contractsDir}`);
      return { valid: true, results: [] }; // Not an error if directory doesn't exist yet
    }

    const files = fs.readdirSync(contractsDir)
      .filter(file => 
        file.endsWith('.yaml') || 
        file.endsWith('.yml') || 
        file.endsWith('.json') ||
        file.includes('.openapi.')
      )
      .filter(file => !file.startsWith('.'));

    if (files.length === 0) {
      console.log('⚠ No OpenAPI contract files found');
      return { valid: true, results: [] };
    }

    console.log(`📋 Found ${files.length} OpenAPI contract files to validate`);
    
    let allValid = true;
    const results = [];

    for (const file of files) {
      const filePath = path.join(contractsDir, file);
      const result = await this.validateOpenAPI(filePath);
      
      results.push({
        file,
        filePath,
        ...result
      });

      if (result.valid) {
        console.log(`✓ ${file}`);
        if (result.warnings.length > 0) {
          result.warnings.forEach(warning => {
            console.log(`  ⚠ ${warning}`);
          });
        }
      } else {
        console.log(`✗ ${file}:`);
        result.errors.forEach(error => {
          console.log(`  - ${error}`);
        });
        allValid = false;
      }
    }

    return { valid: allValid, results };
  }

  /**
   * Validate all AsyncAPI contracts in a directory
   * @param {string} contractsDir - Directory containing AsyncAPI specifications
   * @returns {Promise<{valid: boolean, results: Array}>}
   */
  async validateAsyncAPIDirectory(contractsDir = 'docs/contracts/events') {
    console.log('\n=== Validating AsyncAPI Contracts ===');
    
    if (!fs.existsSync(contractsDir)) {
      console.log(`⚠ AsyncAPI contracts directory not found: ${contractsDir}`);
      return { valid: true, results: [] }; // Not an error if directory doesn't exist yet
    }

    const files = fs.readdirSync(contractsDir)
      .filter(file => 
        file.endsWith('.yaml') || 
        file.endsWith('.yml') || 
        file.endsWith('.json') ||
        file.includes('.asyncapi.')
      )
      .filter(file => !file.startsWith('.'));

    if (files.length === 0) {
      console.log('⚠ No AsyncAPI contract files found');
      return { valid: true, results: [] };
    }

    console.log(`📋 Found ${files.length} AsyncAPI contract files to validate`);
    
    let allValid = true;
    const results = [];

    for (const file of files) {
      const filePath = path.join(contractsDir, file);
      const result = await this.validateAsyncAPI(filePath);
      
      results.push({
        file,
        filePath,
        ...result
      });

      if (result.valid) {
        console.log(`✓ ${file}`);
        if (result.warnings.length > 0) {
          result.warnings.forEach(warning => {
            console.log(`  ⚠ ${warning}`);
          });
        }
      } else {
        console.log(`✗ ${file}:`);
        result.errors.forEach(error => {
          console.log(`  - ${error}`);
        });
        allValid = false;
      }
    }

    return { valid: allValid, results };
  }

  /**
   * Validate all contracts (both OpenAPI and AsyncAPI)
   * @returns {Promise<boolean>}
   */
  async validateAllContracts() {
    console.log('🔍 Starting contract validation...\n');
    
    const openAPIResult = await this.validateOpenAPIDirectory();
    const asyncAPIResult = await this.validateAsyncAPIDirectory();
    
    const allValid = openAPIResult.valid && asyncAPIResult.valid;
    
    console.log('\n=== Contract Validation Summary ===');
    if (allValid) {
      console.log('✅ All contracts are valid');
    } else {
      console.log('❌ Contract validation failed');
    }
    
    return allValid;
  }
}

// CLI usage
if (import.meta.url === `file://${process.argv[1]}`) {
  const command = process.argv[2];
  const options = process.argv.slice(3);
  
  if (options.includes('--help') || options.includes('-h') || command === '--help' || command === '-h') {
    console.log(`
🔍 Contract Validation Tool

Usage: node contract-validator.js [command] [options]

Commands:
  openapi       Validate OpenAPI contracts only
  asyncapi      Validate AsyncAPI contracts only  
  all           Validate all contracts (default)

Options:
  --path=<path>     Use custom path for validation
  --help, -h        Show this help message

Examples:
  node contract-validator.js openapi
  node contract-validator.js asyncapi
  node contract-validator.js all --path=custom/docs
`);
    process.exit(0);
  }
  
  const customPath = options.find(opt => opt.startsWith('--path='))?.split('=')[1];
  const validator = new ContractValidator();
  
  try {
    let result;
    switch (command) {
      case 'openapi':
        const openAPIPath = customPath ? `${customPath}/contracts/http` : 'docs/contracts/http';
        result = await validator.validateOpenAPIDirectory(openAPIPath);
        process.exit(result.valid ? 0 : 1);
        break;
      case 'asyncapi':
        const asyncAPIPath = customPath ? `${customPath}/contracts/events` : 'docs/contracts/events';
        result = await validator.validateAsyncAPIDirectory(asyncAPIPath);
        process.exit(result.valid ? 0 : 1);
        break;
      case 'all':
      default:
        const allValid = await validator.validateAllContracts();
        process.exit(allValid ? 0 : 1);
        break;
    }
  } catch (error) {
    console.error('❌ Validation failed:', error.message);
    process.exit(1);
  }
}

export default ContractValidator;
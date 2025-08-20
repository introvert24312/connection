#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Contract diff analyzer for detecting breaking changes in OpenAPI and AsyncAPI specifications
 */
class ContractDiffAnalyzer {
  constructor() {
    this.breakingChanges = [];
    this.nonBreakingChanges = [];
    this.warnings = [];
  }

  /**
   * Compare two OpenAPI specifications and detect breaking changes
   * @param {string} oldSpecPath - Path to the old specification
   * @param {string} newSpecPath - Path to the new specification
   * @returns {Promise<{breakingChanges: Array, nonBreakingChanges: Array, warnings: Array}>}
   */
  async compareOpenAPISpecs(oldSpecPath, newSpecPath) {
    try {
      const oldSpec = this.loadSpec(oldSpecPath);
      const newSpec = this.loadSpec(newSpecPath);

      this.breakingChanges = [];
      this.nonBreakingChanges = [];
      this.warnings = [];

      // Compare API versions
      this.compareVersions(oldSpec, newSpec);

      // Compare paths and operations
      this.compareOpenAPIPaths(oldSpec.paths || {}, newSpec.paths || {});

      // Compare components/schemas
      this.compareSchemas(oldSpec.components?.schemas || {}, newSpec.components?.schemas || {});

      // Compare security requirements
      this.compareSecurity(oldSpec.security || [], newSpec.security || []);

      return {
        breakingChanges: this.breakingChanges,
        nonBreakingChanges: this.nonBreakingChanges,
        warnings: this.warnings
      };

    } catch (error) {
      throw new Error(`Failed to compare OpenAPI specs: ${error.message}`);
    }
  }

  /**
   * Compare two AsyncAPI specifications and detect breaking changes
   * @param {string} oldSpecPath - Path to the old specification
   * @param {string} newSpecPath - Path to the new specification
   * @returns {Promise<{breakingChanges: Array, nonBreakingChanges: Array, warnings: Array}>}
   */
  async compareAsyncAPISpecs(oldSpecPath, newSpecPath) {
    try {
      const oldSpec = this.loadSpec(oldSpecPath);
      const newSpec = this.loadSpec(newSpecPath);

      this.breakingChanges = [];
      this.nonBreakingChanges = [];
      this.warnings = [];

      // Compare API versions
      this.compareVersions(oldSpec, newSpec);

      // Compare channels
      this.compareAsyncAPIChannels(oldSpec.channels || {}, newSpec.channels || {});

      // Compare message schemas
      this.compareMessages(oldSpec.components?.messages || {}, newSpec.components?.messages || {});

      return {
        breakingChanges: this.breakingChanges,
        nonBreakingChanges: this.nonBreakingChanges,
        warnings: this.warnings
      };

    } catch (error) {
      throw new Error(`Failed to compare AsyncAPI specs: ${error.message}`);
    }
  }

  /**
   * Load and parse a specification file
   * @param {string} specPath - Path to the specification file
   * @returns {object} Parsed specification
   */
  loadSpec(specPath) {
    if (!fs.existsSync(specPath)) {
      throw new Error(`Specification file not found: ${specPath}`);
    }

    const content = fs.readFileSync(specPath, 'utf8');
    
    if (specPath.endsWith('.yaml') || specPath.endsWith('.yml')) {
      return yaml.load(content);
    } else {
      return JSON.parse(content);
    }
  }

  /**
   * Compare API versions between specifications
   * @param {object} oldSpec - Old specification
   * @param {object} newSpec - New specification
   */
  compareVersions(oldSpec, newSpec) {
    const oldVersion = oldSpec.info?.version;
    const newVersion = newSpec.info?.version;

    if (oldVersion && newVersion && oldVersion !== newVersion) {
      // Check if it's a major version change (potentially breaking)
      const oldMajor = this.extractMajorVersion(oldVersion);
      const newMajor = this.extractMajorVersion(newVersion);

      if (newMajor > oldMajor) {
        this.warnings.push(`Major version change detected: ${oldVersion} → ${newVersion}. Review for breaking changes.`);
      } else if (newMajor < oldMajor) {
        this.breakingChanges.push(`Version downgrade detected: ${oldVersion} → ${newVersion}. This is typically a breaking change.`);
      } else {
        this.nonBreakingChanges.push(`Version updated: ${oldVersion} → ${newVersion}`);
      }
    }
  }

  /**
   * Extract major version number from version string
   * @param {string} version - Version string (e.g., "1.2.3")
   * @returns {number} Major version number
   */
  extractMajorVersion(version) {
    const match = version.match(/^(\d+)/);
    return match ? parseInt(match[1], 10) : 0;
  }

  /**
   * Compare OpenAPI paths and operations
   * @param {object} oldPaths - Old paths object
   * @param {object} newPaths - New paths object
   */
  compareOpenAPIPaths(oldPaths, newPaths) {
    const oldPathKeys = Object.keys(oldPaths);
    const newPathKeys = Object.keys(newPaths);

    // Check for removed paths (breaking change)
    for (const pathKey of oldPathKeys) {
      if (!newPathKeys.includes(pathKey)) {
        this.breakingChanges.push(`Removed endpoint: ${pathKey}`);
      }
    }

    // Check for added paths (non-breaking change)
    for (const pathKey of newPathKeys) {
      if (!oldPathKeys.includes(pathKey)) {
        this.nonBreakingChanges.push(`Added endpoint: ${pathKey}`);
      }
    }

    // Compare existing paths
    for (const pathKey of oldPathKeys) {
      if (newPathKeys.includes(pathKey)) {
        this.comparePathOperations(pathKey, oldPaths[pathKey], newPaths[pathKey]);
      }
    }
  }

  /**
   * Compare operations within a path
   * @param {string} pathKey - Path key (e.g., "/users/{id}")
   * @param {object} oldPath - Old path object
   * @param {object} newPath - New path object
   */
  comparePathOperations(pathKey, oldPath, newPath) {
    const httpMethods = ['get', 'post', 'put', 'delete', 'patch', 'head', 'options', 'trace'];
    
    for (const method of httpMethods) {
      const oldOperation = oldPath[method];
      const newOperation = newPath[method];

      if (oldOperation && !newOperation) {
        this.breakingChanges.push(`Removed operation: ${method.toUpperCase()} ${pathKey}`);
      } else if (!oldOperation && newOperation) {
        this.nonBreakingChanges.push(`Added operation: ${method.toUpperCase()} ${pathKey}`);
      } else if (oldOperation && newOperation) {
        this.compareOperation(pathKey, method, oldOperation, newOperation);
      }
    }
  }

  /**
   * Compare individual operations
   * @param {string} pathKey - Path key
   * @param {string} method - HTTP method
   * @param {object} oldOperation - Old operation object
   * @param {object} newOperation - New operation object
   */
  compareOperation(pathKey, method, oldOperation, newOperation) {
    const operationId = `${method.toUpperCase()} ${pathKey}`;

    // Compare parameters
    this.compareParameters(operationId, oldOperation.parameters || [], newOperation.parameters || []);

    // Compare request body
    this.compareRequestBody(operationId, oldOperation.requestBody, newOperation.requestBody);

    // Compare responses
    this.compareResponses(operationId, oldOperation.responses || {}, newOperation.responses || {});
  }

  /**
   * Compare operation parameters
   * @param {string} operationId - Operation identifier
   * @param {Array} oldParams - Old parameters array
   * @param {Array} newParams - New parameters array
   */
  compareParameters(operationId, oldParams, newParams) {
    // Check for removed required parameters (breaking change)
    for (const oldParam of oldParams) {
      if (oldParam.required) {
        const newParam = newParams.find(p => p.name === oldParam.name && p.in === oldParam.in);
        if (!newParam) {
          this.breakingChanges.push(`${operationId}: Removed required parameter '${oldParam.name}' (${oldParam.in})`);
        } else if (!newParam.required) {
          this.breakingChanges.push(`${operationId}: Parameter '${oldParam.name}' is no longer required`);
        }
      }
    }

    // Check for new required parameters (breaking change)
    for (const newParam of newParams) {
      if (newParam.required) {
        const oldParam = oldParams.find(p => p.name === newParam.name && p.in === newParam.in);
        if (!oldParam) {
          this.breakingChanges.push(`${operationId}: Added new required parameter '${newParam.name}' (${newParam.in})`);
        } else if (!oldParam.required) {
          this.breakingChanges.push(`${operationId}: Parameter '${newParam.name}' is now required`);
        }
      }
    }

    // Check for added optional parameters (non-breaking change)
    for (const newParam of newParams) {
      if (!newParam.required) {
        const oldParam = oldParams.find(p => p.name === newParam.name && p.in === newParam.in);
        if (!oldParam) {
          this.nonBreakingChanges.push(`${operationId}: Added optional parameter '${newParam.name}' (${newParam.in})`);
        }
      }
    }
  }

  /**
   * Compare request bodies
   * @param {string} operationId - Operation identifier
   * @param {object} oldRequestBody - Old request body
   * @param {object} newRequestBody - New request body
   */
  compareRequestBody(operationId, oldRequestBody, newRequestBody) {
    if (oldRequestBody && !newRequestBody) {
      this.breakingChanges.push(`${operationId}: Removed request body`);
    } else if (!oldRequestBody && newRequestBody && newRequestBody.required) {
      this.breakingChanges.push(`${operationId}: Added required request body`);
    } else if (!oldRequestBody && newRequestBody && !newRequestBody.required) {
      this.nonBreakingChanges.push(`${operationId}: Added optional request body`);
    } else if (oldRequestBody && newRequestBody) {
      // Compare content types
      const oldContentTypes = Object.keys(oldRequestBody.content || {});
      const newContentTypes = Object.keys(newRequestBody.content || {});

      for (const contentType of oldContentTypes) {
        if (!newContentTypes.includes(contentType)) {
          this.breakingChanges.push(`${operationId}: Removed request content type '${contentType}'`);
        }
      }

      for (const contentType of newContentTypes) {
        if (!oldContentTypes.includes(contentType)) {
          this.nonBreakingChanges.push(`${operationId}: Added request content type '${contentType}'`);
        }
      }
    }
  }

  /**
   * Compare responses
   * @param {string} operationId - Operation identifier
   * @param {object} oldResponses - Old responses object
   * @param {object} newResponses - New responses object
   */
  compareResponses(operationId, oldResponses, newResponses) {
    const oldStatusCodes = Object.keys(oldResponses);
    const newStatusCodes = Object.keys(newResponses);

    // Check for removed success responses (breaking change)
    for (const statusCode of oldStatusCodes) {
      if (statusCode.startsWith('2') && !newStatusCodes.includes(statusCode)) {
        this.breakingChanges.push(`${operationId}: Removed success response ${statusCode}`);
      }
    }

    // Check for added responses (generally non-breaking)
    for (const statusCode of newStatusCodes) {
      if (!oldStatusCodes.includes(statusCode)) {
        if (statusCode.startsWith('2')) {
          this.nonBreakingChanges.push(`${operationId}: Added success response ${statusCode}`);
        } else {
          this.nonBreakingChanges.push(`${operationId}: Added error response ${statusCode}`);
        }
      }
    }
  }

  /**
   * Compare schemas/components
   * @param {object} oldSchemas - Old schemas object
   * @param {object} newSchemas - New schemas object
   */
  compareSchemas(oldSchemas, newSchemas) {
    const oldSchemaNames = Object.keys(oldSchemas);
    const newSchemaNames = Object.keys(newSchemas);

    // Check for removed schemas (breaking change)
    for (const schemaName of oldSchemaNames) {
      if (!newSchemaNames.includes(schemaName)) {
        this.breakingChanges.push(`Removed schema: ${schemaName}`);
      }
    }

    // Check for added schemas (non-breaking change)
    for (const schemaName of newSchemaNames) {
      if (!oldSchemaNames.includes(schemaName)) {
        this.nonBreakingChanges.push(`Added schema: ${schemaName}`);
      }
    }

    // Compare existing schemas
    for (const schemaName of oldSchemaNames) {
      if (newSchemaNames.includes(schemaName)) {
        this.compareSchemaProperties(schemaName, oldSchemas[schemaName], newSchemas[schemaName]);
      }
    }
  }

  /**
   * Compare schema properties
   * @param {string} schemaName - Schema name
   * @param {object} oldSchema - Old schema object
   * @param {object} newSchema - New schema object
   */
  compareSchemaProperties(schemaName, oldSchema, newSchema) {
    const oldRequired = oldSchema.required || [];
    const newRequired = newSchema.required || [];
    const oldProperties = Object.keys(oldSchema.properties || {});
    const newProperties = Object.keys(newSchema.properties || {});

    // Check for removed required fields (breaking change)
    for (const field of oldRequired) {
      if (!newRequired.includes(field)) {
        this.breakingChanges.push(`Schema ${schemaName}: Field '${field}' is no longer required`);
      }
    }

    // Check for new required fields (breaking change)
    for (const field of newRequired) {
      if (!oldRequired.includes(field)) {
        this.breakingChanges.push(`Schema ${schemaName}: Field '${field}' is now required`);
      }
    }

    // Check for removed properties (breaking change)
    for (const property of oldProperties) {
      if (!newProperties.includes(property)) {
        this.breakingChanges.push(`Schema ${schemaName}: Removed property '${property}'`);
      }
    }

    // Check for added properties (non-breaking change)
    for (const property of newProperties) {
      if (!oldProperties.includes(property)) {
        this.nonBreakingChanges.push(`Schema ${schemaName}: Added property '${property}'`);
      }
    }
  }

  /**
   * Compare security requirements
   * @param {Array} oldSecurity - Old security array
   * @param {Array} newSecurity - New security array
   */
  compareSecurity(oldSecurity, newSecurity) {
    if (oldSecurity.length === 0 && newSecurity.length > 0) {
      this.breakingChanges.push('Added security requirements to previously unsecured API');
    } else if (oldSecurity.length > 0 && newSecurity.length === 0) {
      this.breakingChanges.push('Removed all security requirements from API');
    }
  }

  /**
   * Compare AsyncAPI channels
   * @param {object} oldChannels - Old channels object
   * @param {object} newChannels - New channels object
   */
  compareAsyncAPIChannels(oldChannels, newChannels) {
    const oldChannelNames = Object.keys(oldChannels);
    const newChannelNames = Object.keys(newChannels);

    // Check for removed channels (breaking change)
    for (const channelName of oldChannelNames) {
      if (!newChannelNames.includes(channelName)) {
        this.breakingChanges.push(`Removed channel: ${channelName}`);
      }
    }

    // Check for added channels (non-breaking change)
    for (const channelName of newChannelNames) {
      if (!oldChannelNames.includes(channelName)) {
        this.nonBreakingChanges.push(`Added channel: ${channelName}`);
      }
    }

    // Compare existing channels
    for (const channelName of oldChannelNames) {
      if (newChannelNames.includes(channelName)) {
        this.compareChannelOperations(channelName, oldChannels[channelName], newChannels[channelName]);
      }
    }
  }

  /**
   * Compare channel operations (publish/subscribe)
   * @param {string} channelName - Channel name
   * @param {object} oldChannel - Old channel object
   * @param {object} newChannel - New channel object
   */
  compareChannelOperations(channelName, oldChannel, newChannel) {
    // Compare publish operations
    if (oldChannel.publish && !newChannel.publish) {
      this.breakingChanges.push(`Channel ${channelName}: Removed publish operation`);
    } else if (!oldChannel.publish && newChannel.publish) {
      this.nonBreakingChanges.push(`Channel ${channelName}: Added publish operation`);
    }

    // Compare subscribe operations
    if (oldChannel.subscribe && !newChannel.subscribe) {
      this.breakingChanges.push(`Channel ${channelName}: Removed subscribe operation`);
    } else if (!oldChannel.subscribe && newChannel.subscribe) {
      this.nonBreakingChanges.push(`Channel ${channelName}: Added subscribe operation`);
    }
  }

  /**
   * Compare message definitions
   * @param {object} oldMessages - Old messages object
   * @param {object} newMessages - New messages object
   */
  compareMessages(oldMessages, newMessages) {
    const oldMessageNames = Object.keys(oldMessages);
    const newMessageNames = Object.keys(newMessages);

    // Check for removed messages (breaking change)
    for (const messageName of oldMessageNames) {
      if (!newMessageNames.includes(messageName)) {
        this.breakingChanges.push(`Removed message: ${messageName}`);
      }
    }

    // Check for added messages (non-breaking change)
    for (const messageName of newMessageNames) {
      if (!oldMessageNames.includes(messageName)) {
        this.nonBreakingChanges.push(`Added message: ${messageName}`);
      }
    }

    // Compare existing messages
    for (const messageName of oldMessageNames) {
      if (newMessageNames.includes(messageName)) {
        this.compareMessagePayloads(messageName, oldMessages[messageName], newMessages[messageName]);
      }
    }
  }

  /**
   * Compare message payloads
   * @param {string} messageName - Message name
   * @param {object} oldMessage - Old message object
   * @param {object} newMessage - New message object
   */
  compareMessagePayloads(messageName, oldMessage, newMessage) {
    const oldPayload = oldMessage.payload;
    const newPayload = newMessage.payload;

    if (oldPayload && newPayload) {
      // Compare payload schemas similar to regular schemas
      this.compareSchemaProperties(`Message ${messageName}`, oldPayload, newPayload);
    } else if (oldPayload && !newPayload) {
      this.breakingChanges.push(`Message ${messageName}: Removed payload schema`);
    } else if (!oldPayload && newPayload) {
      this.nonBreakingChanges.push(`Message ${messageName}: Added payload schema`);
    }
  }

  /**
   * Generate a diff report
   * @param {object} diffResult - Result from comparison
   * @returns {string} Formatted diff report
   */
  generateReport(diffResult) {
    let report = '# Contract Diff Report\n\n';

    if (diffResult.breakingChanges.length > 0) {
      report += '## 🚨 Breaking Changes\n\n';
      for (const change of diffResult.breakingChanges) {
        report += `- ❌ ${change}\n`;
      }
      report += '\n';
    }

    if (diffResult.nonBreakingChanges.length > 0) {
      report += '## ✅ Non-Breaking Changes\n\n';
      for (const change of diffResult.nonBreakingChanges) {
        report += `- ✅ ${change}\n`;
      }
      report += '\n';
    }

    if (diffResult.warnings.length > 0) {
      report += '## ⚠️ Warnings\n\n';
      for (const warning of diffResult.warnings) {
        report += `- ⚠️ ${warning}\n`;
      }
      report += '\n';
    }

    if (diffResult.breakingChanges.length === 0 && diffResult.nonBreakingChanges.length === 0 && diffResult.warnings.length === 0) {
      report += '## ✅ No Changes Detected\n\nThe specifications are identical.\n';
    }

    return report;
  }
}

// CLI usage
if (import.meta.url === `file://${process.argv[1]}`) {
  const command = process.argv[2];
  const oldSpec = process.argv[3];
  const newSpec = process.argv[4];
  const options = process.argv.slice(5);
  
  if (options.includes('--help') || options.includes('-h') || !command || !oldSpec || !newSpec) {
    console.log(`
🔍 Contract Diff Analyzer

Usage: node contract-diff-analyzer.js [command] <old-spec> <new-spec> [options]

Commands:
  openapi       Compare OpenAPI specifications
  asyncapi      Compare AsyncAPI specifications

Arguments:
  <old-spec>    Path to the old specification file
  <new-spec>    Path to the new specification file

Options:
  --output=<file>   Save report to file
  --format=<type>   Output format (text, json) [default: text]
  --help, -h        Show this help message

Examples:
  node contract-diff-analyzer.js openapi old-api.yaml new-api.yaml
  node contract-diff-analyzer.js asyncapi old-events.yaml new-events.yaml --output=diff-report.md
`);
    process.exit(0);
  }
  
  const outputFile = options.find(opt => opt.startsWith('--output='))?.split('=')[1];
  const format = options.find(opt => opt.startsWith('--format='))?.split('=')[1] || 'text';
  
  const analyzer = new ContractDiffAnalyzer();
  
  try {
    let result;
    switch (command) {
      case 'openapi':
        result = await analyzer.compareOpenAPISpecs(oldSpec, newSpec);
        break;
      case 'asyncapi':
        result = await analyzer.compareAsyncAPISpecs(oldSpec, newSpec);
        break;
      default:
        console.error(`Unknown command: ${command}`);
        process.exit(1);
    }

    if (format === 'json') {
      const output = JSON.stringify(result, null, 2);
      if (outputFile) {
        fs.writeFileSync(outputFile, output);
        console.log(`Diff report saved to ${outputFile}`);
      } else {
        console.log(output);
      }
    } else {
      const report = analyzer.generateReport(result);
      if (outputFile) {
        fs.writeFileSync(outputFile, report);
        console.log(`Diff report saved to ${outputFile}`);
      } else {
        console.log(report);
      }
    }

    // Exit with error code if breaking changes detected
    process.exit(result.breakingChanges.length > 0 ? 1 : 0);

  } catch (error) {
    console.error('❌ Diff analysis failed:', error.message);
    process.exit(1);
  }
}

export default ContractDiffAnalyzer;
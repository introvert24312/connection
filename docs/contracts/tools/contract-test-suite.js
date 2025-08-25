#!/usr/bin/env node

/**
 * WordTagger Contract Validation Test Suite
 * 
 * This JavaScript tool validates various contract files including:
 * - AsyncAPI specifications
 * - JSON Schema definitions  
 * - OpenAPI specifications
 * - Contract consistency across different formats
 */

const fs = require('fs');
const path = require('path');
const yaml = require('yaml');
const Ajv = require('ajv');
const addFormats = require('ajv-formats');

// Initialize JSON Schema validator
const ajv = new Ajv({ allErrors: true, verbose: true });
addFormats(ajv);

class ContractTestSuite {
    constructor(contractsDir) {
        this.contractsDir = contractsDir;
        this.results = {
            totalTests: 0,
            passedTests: 0,
            failedTests: 0,
            errors: [],
            warnings: []
        };
    }

    async runAllTests() {
        console.log('🚀 Starting WordTagger Contract Validation Test Suite\n');
        
        try {
            await this.testJSONSchemas();
            await this.testAsyncAPISpecs();
            await this.testOpenAPISpecs();
            await this.testContractConsistency();
            await this.testExampleValidation();
            
            this.generateReport();
            
        } catch (error) {
            console.error('❌ Test suite failed with error:', error);
            process.exit(1);
        }
    }

    async testJSONSchemas() {
        console.log('📋 Testing JSON Schema definitions...');
        
        const schemaDir = path.join(this.contractsDir, 'schemas');
        if (!fs.existsSync(schemaDir)) {
            this.addError('schemas', 'Schema directory not found');
            return;
        }

        const schemaFiles = fs.readdirSync(schemaDir).filter(file => file.endsWith('.json'));
        
        for (const schemaFile of schemaFiles) {
            await this.testJSONSchema(path.join(schemaDir, schemaFile));
        }
    }

    async testJSONSchema(schemaPath) {
        const schemaName = path.basename(schemaPath);
        this.results.totalTests++;
        
        try {
            const schemaContent = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
            
            // Validate schema structure
            if (!schemaContent.$schema) {
                this.addError(schemaName, 'Missing $schema property');
                return;
            }
            
            if (!schemaContent.$id) {
                this.addError(schemaName, 'Missing $id property');
                return;
            }
            
            if (!schemaContent.title) {
                this.addError(schemaName, 'Missing title property');
                return;
            }
            
            // Try to compile schema
            try {
                ajv.compile(schemaContent);
                this.addSuccess(schemaName, 'Schema is valid and compilable');
            } catch (compileError) {
                this.addError(schemaName, `Schema compilation failed: ${compileError.message}`);
                return;
            }
            
            // Test examples if present
            if (schemaContent.examples && Array.isArray(schemaContent.examples)) {
                const validate = ajv.compile(schemaContent);
                
                schemaContent.examples.forEach((example, index) => {
                    if (!validate(example)) {
                        this.addError(schemaName, 
                            `Example ${index + 1} failed validation: ${ajv.errorsText(validate.errors)}`);
                    } else {
                        this.addSuccess(schemaName, `Example ${index + 1} validated successfully`);
                    }
                });
            }
            
        } catch (error) {
            this.addError(schemaName, `Failed to parse schema: ${error.message}`);
        }
    }

    async testAsyncAPISpecs() {
        console.log('📡 Testing AsyncAPI specifications...');
        
        const eventsDir = path.join(this.contractsDir, 'events');
        if (!fs.existsSync(eventsDir)) {
            this.addError('events', 'Events directory not found');
            return;
        }

        const asyncAPIFiles = fs.readdirSync(eventsDir).filter(file => 
            file.endsWith('.asyncapi.yaml') || file.endsWith('.asyncapi.yml'));
        
        for (const asyncAPIFile of asyncAPIFiles) {
            await this.testAsyncAPISpec(path.join(eventsDir, asyncAPIFile));
        }
    }

    async testAsyncAPISpec(specPath) {
        const specName = path.basename(specPath);
        this.results.totalTests++;
        
        try {
            const specContent = yaml.parse(fs.readFileSync(specPath, 'utf8'));
            
            // Validate AsyncAPI structure
            if (!specContent.asyncapi) {
                this.addError(specName, 'Missing asyncapi version');
                return;
            }
            
            if (!specContent.info) {
                this.addError(specName, 'Missing info section');
                return;
            }
            
            if (!specContent.channels) {
                this.addError(specName, 'Missing channels section');
                return;
            }
            
            if (!specContent.components || !specContent.components.messages) {
                this.addError(specName, 'Missing components/messages section');
                return;
            }
            
            // Test channel structure
            for (const [channelName, channelSpec] of Object.entries(specContent.channels)) {
                this.testAsyncAPIChannel(specName, channelName, channelSpec);
            }
            
            // Test message schemas
            for (const [messageName, messageSpec] of Object.entries(specContent.components.messages)) {
                this.testAsyncAPIMessage(specName, messageName, messageSpec);
            }
            
            this.addSuccess(specName, 'AsyncAPI specification structure is valid');
            
        } catch (error) {
            this.addError(specName, `Failed to parse AsyncAPI spec: ${error.message}`);
        }
    }

    testAsyncAPIChannel(specName, channelName, channelSpec) {
        if (!channelSpec.description) {
            this.addWarning(specName, `Channel ${channelName} missing description`);
        }
        
        if (!channelSpec.publish && !channelSpec.subscribe) {
            this.addError(specName, `Channel ${channelName} has neither publish nor subscribe operation`);
        }
        
        // Test bindings consistency
        const operation = channelSpec.publish || channelSpec.subscribe;
        if (operation && operation.bindings) {
            if (channelName.includes('.') && !operation.bindings.notificationcenter) {
                this.addWarning(specName, 
                    `Channel ${channelName} appears to be NotificationCenter-based but lacks binding info`);
            }
        }
    }

    testAsyncAPIMessage(specName, messageName, messageSpec) {
        if (!messageSpec.contentType) {
            this.addWarning(specName, `Message ${messageName} missing contentType`);
        }
        
        if (!messageSpec.payload) {
            this.addError(specName, `Message ${messageName} missing payload schema`);
        }
        
        if (!messageSpec.examples || messageSpec.examples.length === 0) {
            this.addWarning(specName, `Message ${messageName} missing examples`);
        }
    }

    async testOpenAPISpecs() {
        console.log('🌐 Testing OpenAPI specifications...');
        
        const httpDir = path.join(this.contractsDir, 'http');
        if (!fs.existsSync(httpDir)) {
            this.addError('http', 'HTTP directory not found');
            return;
        }

        const openAPIFiles = fs.readdirSync(httpDir).filter(file => 
            file.endsWith('.openapi.yaml') || file.endsWith('.openapi.yml'));
        
        for (const openAPIFile of openAPIFiles) {
            await this.testOpenAPISpec(path.join(httpDir, openAPIFile));
        }
    }

    async testOpenAPISpec(specPath) {
        const specName = path.basename(specPath);
        this.results.totalTests++;
        
        try {
            const specContent = yaml.parse(fs.readFileSync(specPath, 'utf8'));
            
            // Basic OpenAPI validation
            if (!specContent.openapi) {
                this.addError(specName, 'Missing openapi version');
                return;
            }
            
            if (!specContent.info) {
                this.addError(specName, 'Missing info section');
                return;
            }
            
            if (!specContent.paths) {
                this.addError(specName, 'Missing paths section');
                return;
            }
            
            this.addSuccess(specName, 'OpenAPI specification structure is valid');
            
        } catch (error) {
            this.addError(specName, `Failed to parse OpenAPI spec: ${error.message}`);
        }
    }

    async testContractConsistency() {
        console.log('🔗 Testing contract consistency...');
        this.results.totalTests++;
        
        try {
            // Test that referenced schemas exist
            await this.testSchemaReferences();
            
            // Test that event messages match schema definitions
            await this.testEventSchemaConsistency();
            
            // Test that Swift protocols align with schemas
            await this.testSwiftProtocolConsistency();
            
            this.addSuccess('consistency', 'Contract consistency checks passed');
            
        } catch (error) {
            this.addError('consistency', `Consistency check failed: ${error.message}`);
        }
    }

    async testSchemaReferences() {
        const schemaDir = path.join(this.contractsDir, 'schemas');
        const eventsDir = path.join(this.contractsDir, 'events');
        
        // Get all available schemas
        const availableSchemas = fs.readdirSync(schemaDir)
            .filter(file => file.endsWith('.json'))
            .map(file => file.replace('.json', ''));
        
        // Check AsyncAPI specs for schema references
        const asyncAPIFiles = fs.readdirSync(eventsDir)
            .filter(file => file.endsWith('.asyncapi.yaml'));
        
        for (const asyncAPIFile of asyncAPIFiles) {
            const specContent = yaml.parse(fs.readFileSync(path.join(eventsDir, asyncAPIFile), 'utf8'));
            
            // Check for schema references in components
            if (specContent.components && specContent.components.schemas) {
                for (const schemaRef of Object.keys(specContent.components.schemas)) {
                    if (!availableSchemas.includes(schemaRef) && !schemaRef.includes('Payload')) {
                        this.addWarning('schema-refs', 
                            `AsyncAPI spec ${asyncAPIFile} references missing schema: ${schemaRef}`);
                    }
                }
            }
        }
    }

    async testEventSchemaConsistency() {
        // Test that event payload schemas match the defined JSON schemas
        const eventsDir = path.join(this.contractsDir, 'events');
        const schemaDir = path.join(this.contractsDir, 'schemas');
        
        // Load node schema for validation
        const nodeSchemaPath = path.join(schemaDir, 'node.schema.json');
        if (fs.existsSync(nodeSchemaPath)) {
            const nodeSchema = JSON.parse(fs.readFileSync(nodeSchemaPath, 'utf8'));
            const validateNode = ajv.compile(nodeSchema);
            
            // Check AsyncAPI examples against node schema
            const wordTaggerEventsPath = path.join(eventsDir, 'wordtagger-events.asyncapi.yaml');
            if (fs.existsSync(wordTaggerEventsPath)) {
                const eventsSpec = yaml.parse(fs.readFileSync(wordTaggerEventsPath, 'utf8'));
                
                // Validate node examples in event messages
                if (eventsSpec.components && eventsSpec.components.messages) {
                    for (const [messageName, messageSpec] of Object.entries(eventsSpec.components.messages)) {
                        if (messageSpec.examples) {
                            messageSpec.examples.forEach((example, index) => {
                                if (example.payload && example.payload.data && example.payload.data.nodeId) {
                                    // This is a node-related event - validate the node structure if present
                                    const eventData = example.payload.data;
                                    if (eventData.text && eventData.layerId) {
                                        // Construct a minimal node for validation
                                        const nodeData = {
                                            id: eventData.nodeId,
                                            text: eventData.text,
                                            phonetic: eventData.phonetic || null,
                                            meaning: eventData.meaning || null,
                                            layerId: eventData.layerId,
                                            tags: eventData.tags || [],
                                            isCompound: eventData.isCompound || false,
                                            markdown: eventData.markdown || "",
                                            createdAt: new Date().toISOString(),
                                            updatedAt: new Date().toISOString()
                                        };
                                        
                                        if (!validateNode(nodeData)) {
                                            this.addWarning('event-schema-consistency',
                                                `${messageName} example ${index + 1} node data doesn't match node schema`);
                                        }
                                    }
                                }
                            });
                        }
                    }
                }
            }
        }
    }

    async testSwiftProtocolConsistency() {
        // Test that Swift protocols align with the defined contracts
        const swiftDir = path.join(this.contractsDir, 'swift');
        const protocolsFile = path.join(swiftDir, 'service-protocols.swift');
        
        if (fs.existsSync(protocolsFile)) {
            const protocolContent = fs.readFileSync(protocolsFile, 'utf8');
            
            // Basic checks for protocol completeness
            const expectedProtocols = [
                'NodeStoreProtocol',
                'SearchServiceProtocol', 
                'GitServiceProtocol',
                'KeychainManagerProtocol',
                'GraphServiceProtocol',
                'ExternalDataServiceProtocol'
            ];
            
            for (const protocolName of expectedProtocols) {
                if (!protocolContent.includes(`protocol ${protocolName}`)) {
                    this.addError('swift-protocols', `Missing protocol definition: ${protocolName}`);
                }
            }
            
            // Check for required methods in NodeStoreProtocol
            const nodeStoreRequiredMethods = [
                'addNode', 'updateNode', 'deleteNode',
                'addLayer', 'updateLayer', 'deleteLayer',
                'performSearch'
            ];
            
            const nodeStoreSection = this.extractProtocolSection(protocolContent, 'NodeStoreProtocol');
            if (nodeStoreSection) {
                for (const method of nodeStoreRequiredMethods) {
                    if (!nodeStoreSection.includes(`func ${method}`)) {
                        this.addWarning('swift-protocols', 
                            `NodeStoreProtocol missing method: ${method}`);
                    }
                }
            }
        } else {
            this.addError('swift-protocols', 'Swift protocol definitions file not found');
        }
    }

    extractProtocolSection(content, protocolName) {
        const startPattern = new RegExp(`protocol ${protocolName}[^{]*{`);
        const startMatch = content.match(startPattern);
        
        if (!startMatch) return null;
        
        const startIndex = startMatch.index + startMatch[0].length;
        let braceCount = 1;
        let endIndex = startIndex;
        
        for (let i = startIndex; i < content.length && braceCount > 0; i++) {
            if (content[i] === '{') braceCount++;
            else if (content[i] === '}') braceCount--;
            endIndex = i;
        }
        
        return content.substring(startIndex, endIndex);
    }

    async testExampleValidation() {
        console.log('✅ Testing schema examples...');
        
        const schemaDir = path.join(this.contractsDir, 'schemas');
        const schemaFiles = fs.readdirSync(schemaDir).filter(file => file.endsWith('.json'));
        
        for (const schemaFile of schemaFiles) {
            const schemaPath = path.join(schemaDir, schemaFile);
            const schemaContent = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
            
            if (schemaContent.examples) {
                const validate = ajv.compile(schemaContent);
                
                schemaContent.examples.forEach((example, index) => {
                    this.results.totalTests++;
                    
                    if (validate(example)) {
                        this.addSuccess(`${schemaFile}-example-${index + 1}`, 
                                       'Example validates against schema');
                    } else {
                        this.addError(`${schemaFile}-example-${index + 1}`, 
                                     `Example validation failed: ${ajv.errorsText(validate.errors)}`);
                    }
                });
            }
        }
    }

    addSuccess(test, message) {
        this.results.passedTests++;
        console.log(`✅ ${test}: ${message}`);
    }

    addError(test, message) {
        this.results.failedTests++;
        this.results.errors.push({ test, message });
        console.log(`❌ ${test}: ${message}`);
    }

    addWarning(test, message) {
        this.results.warnings.push({ test, message });
        console.log(`⚠️  ${test}: ${message}`);
    }

    generateReport() {
        console.log('\n' + '='.repeat(80));
        console.log('📊 WORDTAGGER CONTRACT VALIDATION REPORT');
        console.log('='.repeat(80));
        
        console.log(`\n📈 Test Summary:`);
        console.log(`   Total Tests: ${this.results.totalTests}`);
        console.log(`   Passed: ${this.results.passedTests}`);
        console.log(`   Failed: ${this.results.failedTests}`);
        console.log(`   Warnings: ${this.results.warnings.length}`);
        
        const successRate = this.results.totalTests > 0 
            ? (this.results.passedTests / this.results.totalTests * 100).toFixed(1)
            : '0.0';
        console.log(`   Success Rate: ${successRate}%`);
        
        if (this.results.errors.length > 0) {
            console.log(`\n❌ Errors (${this.results.errors.length}):`);
            this.results.errors.forEach(error => {
                console.log(`   • ${error.test}: ${error.message}`);
            });
        }
        
        if (this.results.warnings.length > 0) {
            console.log(`\n⚠️  Warnings (${this.results.warnings.length}):`);
            this.results.warnings.forEach(warning => {
                console.log(`   • ${warning.test}: ${warning.message}`);
            });
        }
        
        console.log('\n' + '='.repeat(80));
        
        if (this.results.failedTests > 0) {
            console.log('❌ Contract validation failed. Please fix the errors above.');
            process.exit(1);
        } else {
            console.log('✅ All contract validations passed!');
        }
    }
}

// CLI Interface
if (require.main === module) {
    const contractsDir = process.argv[2] || path.join(__dirname, '..');
    
    if (!fs.existsSync(contractsDir)) {
        console.error(`❌ Contracts directory not found: ${contractsDir}`);
        process.exit(1);
    }
    
    const testSuite = new ContractTestSuite(contractsDir);
    testSuite.runAllTests().catch(error => {
        console.error('❌ Test suite execution failed:', error);
        process.exit(1);
    });
}

module.exports = ContractTestSuite;
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import ContractValidator from '../scripts/contract-validator.js';

describe('OpenAPI Contract Validation', () => {
  let validator;
  let testDir;

  beforeEach(() => {
    validator = new ContractValidator();
    testDir = 'test-contracts';
    
    // Create test directory
    if (!fs.existsSync(testDir)) {
      fs.mkdirSync(testDir, { recursive: true });
    }
  });

  afterEach(() => {
    // Clean up test files
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true, force: true });
    }
  });

  describe('validateOpenAPI', () => {
    it('should validate a correct OpenAPI 3.0 specification', async () => {
      const validSpec = {
        openapi: '3.0.0',
        info: {
          title: 'Test API',
          version: '1.0.0'
        },
        paths: {
          '/users': {
            get: {
              summary: 'Get users',
              responses: {
                '200': {
                  description: 'Success',
                  content: {
                    'application/json': {
                      schema: {
                        type: 'array',
                        items: {
                          type: 'object',
                          properties: {
                            id: { type: 'integer' },
                            name: { type: 'string' }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          },
          '/users/{id}': {
            get: {
              summary: 'Get user by ID',
              parameters: [
                {
                  name: 'id',
                  in: 'path',
                  required: true,
                  schema: { type: 'integer' }
                }
              ],
              responses: {
                '200': {
                  description: 'Success'
                },
                '404': {
                  description: 'User not found'
                }
              }
            }
          },
          '/users': {
            post: {
              summary: 'Create user',
              requestBody: {
                required: true,
                content: {
                  'application/json': {
                    schema: {
                      type: 'object',
                      properties: {
                        name: { type: 'string' }
                      },
                      required: ['name']
                    }
                  }
                }
              },
              responses: {
                '201': {
                  description: 'Created'
                },
                '400': {
                  description: 'Bad request'
                }
              }
            }
          }
        }
      };

      const testFile = path.join(testDir, 'valid-api.yaml');
      fs.writeFileSync(testFile, JSON.stringify(validSpec, null, 2));

      const result = await validator.validateOpenAPI(testFile);
      
      expect(result.valid).toBe(true);
      expect(result.errors).toHaveLength(0);
      expect(result.spec).toBeDefined();
    });

    it('should reject OpenAPI specification with missing required fields', async () => {
      const invalidSpec = {
        openapi: '3.0.0',
        // Missing info and paths
      };

      const testFile = path.join(testDir, 'invalid-api.yaml');
      fs.writeFileSync(testFile, JSON.stringify(invalidSpec, null, 2));

      const result = await validator.validateOpenAPI(testFile);
      
      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
      expect(result.errors.some(error => error.includes('info'))).toBe(true);
      expect(result.errors.some(error => error.includes('paths'))).toBe(true);
    });

    it('should reject unsupported OpenAPI versions', async () => {
      const invalidSpec = {
        openapi: '2.0',
        info: {
          title: 'Test API',
          version: '1.0.0'
        },
        paths: {}
      };

      const testFile = path.join(testDir, 'old-version-api.yaml');
      fs.writeFileSync(testFile, JSON.stringify(invalidSpec, null, 2));

      const result = await validator.validateOpenAPI(testFile);
      
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('Unsupported OpenAPI version'))).toBe(true);
    });

    it('should handle missing openapi field', async () => {
      const invalidSpec = {
        info: {
          title: 'Test API',
          version: '1.0.0'
        },
        paths: {}
      };

      const testFile = path.join(testDir, 'no-version-api.yaml');
      fs.writeFileSync(testFile, JSON.stringify(invalidSpec, null, 2));

      const result = await validator.validateOpenAPI(testFile);
      
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('Missing required field: openapi'))).toBe(true);
    });

    it('should handle file not found', async () => {
      const result = await validator.validateOpenAPI('non-existent-file.yaml');
      
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('File not found'))).toBe(true);
    });

    it('should handle invalid YAML syntax', async () => {
      const testFile = path.join(testDir, 'invalid-yaml.yaml');
      fs.writeFileSync(testFile, 'invalid: yaml: content: [unclosed');

      const result = await validator.validateOpenAPI(testFile);
      
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('Failed to parse specification'))).toBe(true);
    });

    it('should provide warnings for missing best practices', async () => {
      const specWithWarnings = {
        openapi: '3.0.0',
        info: {
          title: 'Test API',
          version: '1.0.0'
        },
        paths: {
          '/users': {
            get: {
              // Missing summary/description
              responses: {
                '200': {
                  description: 'Success'
                }
                // Missing error responses
              }
            }
          }
        }
      };

      const testFile = path.join(testDir, 'warnings-api.yaml');
      fs.writeFileSync(testFile, JSON.stringify(specWithWarnings, null, 2));

      const result = await validator.validateOpenAPI(testFile);
      
      expect(result.valid).toBe(true);
      expect(result.warnings.length).toBeGreaterThan(0);
      expect(result.warnings.some(warning => warning.includes('Missing operation description'))).toBe(true);
      expect(result.warnings.some(warning => warning.includes('Consider adding error responses'))).toBe(true);
    });

    it('should warn about insufficient endpoint coverage', async () => {
      const specWithFewEndpoints = {
        openapi: '3.0.0',
        info: {
          title: 'Test API',
          version: '1.0.0'
        },
        paths: {
          '/health': {
            get: {
              summary: 'Health check',
              responses: {
                '200': {
                  description: 'OK'
                }
              }
            }
          }
        }
      };

      const testFile = path.join(testDir, 'few-endpoints-api.yaml');
      fs.writeFileSync(testFile, JSON.stringify(specWithFewEndpoints, null, 2));

      const result = await validator.validateOpenAPI(testFile);
      
      expect(result.valid).toBe(true);
      expect(result.warnings.some(warning => 
        warning.includes('Consider documenting at least 3 critical endpoints')
      )).toBe(true);
    });

    it('should warn about missing security schemes', async () => {
      const specWithoutSecurity = {
        openapi: '3.0.0',
        info: {
          title: 'Test API',
          version: '1.0.0'
        },
        paths: {
          '/users': {
            get: {
              summary: 'Get users',
              responses: {
                '200': {
                  description: 'Success'
                }
              }
            }
          }
        }
      };

      const testFile = path.join(testDir, 'no-security-api.yaml');
      fs.writeFileSync(testFile, JSON.stringify(specWithoutSecurity, null, 2));

      const result = await validator.validateOpenAPI(testFile);
      
      expect(result.valid).toBe(true);
      expect(result.warnings.some(warning => 
        warning.includes('No security schemes defined')
      )).toBe(true);
    });
  });

  describe('validateOpenAPIDirectory', () => {
    it('should validate all OpenAPI files in a directory', async () => {
      const contractsDir = path.join(testDir, 'http');
      fs.mkdirSync(contractsDir, { recursive: true });

      // Create valid spec
      const validSpec = {
        openapi: '3.0.0',
        info: { title: 'Valid API', version: '1.0.0' },
        paths: {
          '/test': {
            get: {
              responses: { '200': { description: 'OK' } }
            }
          }
        }
      };

      fs.writeFileSync(
        path.join(contractsDir, 'valid.openapi.yaml'),
        JSON.stringify(validSpec, null, 2)
      );

      const result = await validator.validateOpenAPIDirectory(contractsDir);
      
      expect(result.valid).toBe(true);
      expect(result.results).toHaveLength(1);
      expect(result.results[0].valid).toBe(true);
    });

    it('should handle directory with mixed valid and invalid files', async () => {
      const contractsDir = path.join(testDir, 'http');
      fs.mkdirSync(contractsDir, { recursive: true });

      // Create valid spec
      const validSpec = {
        openapi: '3.0.0',
        info: { title: 'Valid API', version: '1.0.0' },
        paths: {
          '/test': {
            get: {
              responses: { '200': { description: 'OK' } }
            }
          }
        }
      };

      // Create invalid spec
      const invalidSpec = {
        openapi: '3.0.0'
        // Missing required fields
      };

      fs.writeFileSync(
        path.join(contractsDir, 'valid.openapi.yaml'),
        JSON.stringify(validSpec, null, 2)
      );

      fs.writeFileSync(
        path.join(contractsDir, 'invalid.openapi.yaml'),
        JSON.stringify(invalidSpec, null, 2)
      );

      const result = await validator.validateOpenAPIDirectory(contractsDir);
      
      expect(result.valid).toBe(false);
      expect(result.results).toHaveLength(2);
      expect(result.results.find(r => r.file === 'valid.openapi.yaml').valid).toBe(true);
      expect(result.results.find(r => r.file === 'invalid.openapi.yaml').valid).toBe(false);
    });

    it('should handle non-existent directory gracefully', async () => {
      const result = await validator.validateOpenAPIDirectory('non-existent-dir');
      
      expect(result.valid).toBe(true);
      expect(result.results).toHaveLength(0);
    });

    it('should handle empty directory gracefully', async () => {
      const emptyDir = path.join(testDir, 'empty');
      fs.mkdirSync(emptyDir, { recursive: true });

      const result = await validator.validateOpenAPIDirectory(emptyDir);
      
      expect(result.valid).toBe(true);
      expect(result.results).toHaveLength(0);
    });
  });
});
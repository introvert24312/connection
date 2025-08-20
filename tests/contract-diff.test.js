import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import ContractDiffAnalyzer from '../scripts/contract-diff-analyzer.js';

describe('Contract Diff Detection', () => {
  let analyzer;
  let testDir;

  beforeEach(() => {
    analyzer = new ContractDiffAnalyzer();
    testDir = 'test-diff-contracts';
    
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

  describe('OpenAPI Diff Detection', () => {
    it('should detect removed endpoints as breaking changes', async () => {
      const oldSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {
          '/users': {
            get: { responses: { '200': { description: 'OK' } } }
          },
          '/posts': {
            get: { responses: { '200': { description: 'OK' } } }
          }
        }
      };

      const newSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {
          '/users': {
            get: { responses: { '200': { description: 'OK' } } }
          }
          // /posts removed
        }
      };

      const oldFile = path.join(testDir, 'old.yaml');
      const newFile = path.join(testDir, 'new.yaml');
      
      fs.writeFileSync(oldFile, JSON.stringify(oldSpec, null, 2));
      fs.writeFileSync(newFile, JSON.stringify(newSpec, null, 2));

      const result = await analyzer.compareOpenAPISpecs(oldFile, newFile);
      
      expect(result.breakingChanges).toContain('Removed endpoint: /posts');
      expect(result.breakingChanges.length).toBeGreaterThan(0);
    });

    it('should detect added endpoints as non-breaking changes', async () => {
      const oldSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {
          '/users': {
            get: { responses: { '200': { description: 'OK' } } }
          }
        }
      };

      const newSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {
          '/users': {
            get: { responses: { '200': { description: 'OK' } } }
          },
          '/posts': {
            get: { responses: { '200': { description: 'OK' } } }
          }
        }
      };

      const oldFile = path.join(testDir, 'old.yaml');
      const newFile = path.join(testDir, 'new.yaml');
      
      fs.writeFileSync(oldFile, JSON.stringify(oldSpec, null, 2));
      fs.writeFileSync(newFile, JSON.stringify(newSpec, null, 2));

      const result = await analyzer.compareOpenAPISpecs(oldFile, newFile);
      
      expect(result.nonBreakingChanges).toContain('Added endpoint: /posts');
      expect(result.breakingChanges.length).toBe(0);
    });

    it('should detect removed operations as breaking changes', async () => {
      const oldSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {
          '/users': {
            get: { responses: { '200': { description: 'OK' } } },
            post: { responses: { '201': { description: 'Created' } } }
          }
        }
      };

      const newSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {
          '/users': {
            get: { responses: { '200': { description: 'OK' } } }
            // post operation removed
          }
        }
      };

      const oldFile = path.join(testDir, 'old.yaml');
      const newFile = path.join(testDir, 'new.yaml');
      
      fs.writeFileSync(oldFile, JSON.stringify(oldSpec, null, 2));
      fs.writeFileSync(newFile, JSON.stringify(newSpec, null, 2));

      const result = await analyzer.compareOpenAPISpecs(oldFile, newFile);
      
      expect(result.breakingChanges).toContain('Removed operation: POST /users');
    });

    it('should detect removed required parameters as breaking changes', async () => {
      const oldSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {
          '/users': {
            get: {
              parameters: [
                { name: 'id', in: 'query', required: true, schema: { type: 'string' } }
              ],
              responses: { '200': { description: 'OK' } }
            }
          }
        }
      };

      const newSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {
          '/users': {
            get: {
              parameters: [
                // id parameter removed
              ],
              responses: { '200': { description: 'OK' } }
            }
          }
        }
      };

      const oldFile = path.join(testDir, 'old.yaml');
      const newFile = path.join(testDir, 'new.yaml');
      
      fs.writeFileSync(oldFile, JSON.stringify(oldSpec, null, 2));
      fs.writeFileSync(newFile, JSON.stringify(newSpec, null, 2));

      const result = await analyzer.compareOpenAPISpecs(oldFile, newFile);
      
      expect(result.breakingChanges).toContain("GET /users: Removed required parameter 'id' (query)");
    });

    it('should detect new required parameters as breaking changes', async () => {
      const oldSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {
          '/users': {
            get: {
              parameters: [],
              responses: { '200': { description: 'OK' } }
            }
          }
        }
      };

      const newSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {
          '/users': {
            get: {
              parameters: [
                { name: 'id', in: 'query', required: true, schema: { type: 'string' } }
              ],
              responses: { '200': { description: 'OK' } }
            }
          }
        }
      };

      const oldFile = path.join(testDir, 'old.yaml');
      const newFile = path.join(testDir, 'new.yaml');
      
      fs.writeFileSync(oldFile, JSON.stringify(oldSpec, null, 2));
      fs.writeFileSync(newFile, JSON.stringify(newSpec, null, 2));

      const result = await analyzer.compareOpenAPISpecs(oldFile, newFile);
      
      expect(result.breakingChanges).toContain("GET /users: Added new required parameter 'id' (query)");
    });

    it('should detect removed success responses as breaking changes', async () => {
      const oldSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {
          '/users': {
            get: {
              responses: {
                '200': { description: 'OK' },
                '404': { description: 'Not Found' }
              }
            }
          }
        }
      };

      const newSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {
          '/users': {
            get: {
              responses: {
                '404': { description: 'Not Found' }
                // 200 response removed
              }
            }
          }
        }
      };

      const oldFile = path.join(testDir, 'old.yaml');
      const newFile = path.join(testDir, 'new.yaml');
      
      fs.writeFileSync(oldFile, JSON.stringify(oldSpec, null, 2));
      fs.writeFileSync(newFile, JSON.stringify(newSpec, null, 2));

      const result = await analyzer.compareOpenAPISpecs(oldFile, newFile);
      
      expect(result.breakingChanges).toContain('GET /users: Removed success response 200');
    });

    it('should detect schema changes as breaking changes', async () => {
      const oldSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {},
        components: {
          schemas: {
            User: {
              type: 'object',
              required: ['id', 'name'],
              properties: {
                id: { type: 'string' },
                name: { type: 'string' },
                email: { type: 'string' }
              }
            }
          }
        }
      };

      const newSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {},
        components: {
          schemas: {
            User: {
              type: 'object',
              required: ['id', 'name', 'email'], // email now required
              properties: {
                id: { type: 'string' },
                name: { type: 'string' }
                // email property removed
              }
            }
          }
        }
      };

      const oldFile = path.join(testDir, 'old.yaml');
      const newFile = path.join(testDir, 'new.yaml');
      
      fs.writeFileSync(oldFile, JSON.stringify(oldSpec, null, 2));
      fs.writeFileSync(newFile, JSON.stringify(newSpec, null, 2));

      const result = await analyzer.compareOpenAPISpecs(oldFile, newFile);
      
      expect(result.breakingChanges).toContain("Schema User: Field 'email' is now required");
      expect(result.breakingChanges).toContain("Schema User: Removed property 'email'");
    });

    it('should detect version changes correctly', async () => {
      const oldSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {}
      };

      const newSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '2.0.0' },
        paths: {}
      };

      const oldFile = path.join(testDir, 'old.yaml');
      const newFile = path.join(testDir, 'new.yaml');
      
      fs.writeFileSync(oldFile, JSON.stringify(oldSpec, null, 2));
      fs.writeFileSync(newFile, JSON.stringify(newSpec, null, 2));

      const result = await analyzer.compareOpenAPISpecs(oldFile, newFile);
      
      expect(result.warnings).toContain('Major version change detected: 1.0.0 → 2.0.0. Review for breaking changes.');
    });
  });

  describe('AsyncAPI Diff Detection', () => {
    it('should detect removed channels as breaking changes', async () => {
      const oldSpec = {
        asyncapi: '2.6.0',
        info: { title: 'Test Events', version: '1.0.0' },
        channels: {
          'user.created': {
            publish: { message: { payload: { type: 'object' } } }
          },
          'user.deleted': {
            publish: { message: { payload: { type: 'object' } } }
          }
        }
      };

      const newSpec = {
        asyncapi: '2.6.0',
        info: { title: 'Test Events', version: '1.0.0' },
        channels: {
          'user.created': {
            publish: { message: { payload: { type: 'object' } } }
          }
          // user.deleted channel removed
        }
      };

      const oldFile = path.join(testDir, 'old-events.yaml');
      const newFile = path.join(testDir, 'new-events.yaml');
      
      fs.writeFileSync(oldFile, JSON.stringify(oldSpec, null, 2));
      fs.writeFileSync(newFile, JSON.stringify(newSpec, null, 2));

      const result = await analyzer.compareAsyncAPISpecs(oldFile, newFile);
      
      expect(result.breakingChanges).toContain('Removed channel: user.deleted');
    });

    it('should detect added channels as non-breaking changes', async () => {
      const oldSpec = {
        asyncapi: '2.6.0',
        info: { title: 'Test Events', version: '1.0.0' },
        channels: {
          'user.created': {
            publish: { message: { payload: { type: 'object' } } }
          }
        }
      };

      const newSpec = {
        asyncapi: '2.6.0',
        info: { title: 'Test Events', version: '1.0.0' },
        channels: {
          'user.created': {
            publish: { message: { payload: { type: 'object' } } }
          },
          'user.updated': {
            publish: { message: { payload: { type: 'object' } } }
          }
        }
      };

      const oldFile = path.join(testDir, 'old-events.yaml');
      const newFile = path.join(testDir, 'new-events.yaml');
      
      fs.writeFileSync(oldFile, JSON.stringify(oldSpec, null, 2));
      fs.writeFileSync(newFile, JSON.stringify(newSpec, null, 2));

      const result = await analyzer.compareAsyncAPISpecs(oldFile, newFile);
      
      expect(result.nonBreakingChanges).toContain('Added channel: user.updated');
      expect(result.breakingChanges.length).toBe(0);
    });

    it('should detect removed publish operations as breaking changes', async () => {
      const oldSpec = {
        asyncapi: '2.6.0',
        info: { title: 'Test Events', version: '1.0.0' },
        channels: {
          'user.created': {
            publish: { message: { payload: { type: 'object' } } },
            subscribe: { message: { payload: { type: 'object' } } }
          }
        }
      };

      const newSpec = {
        asyncapi: '2.6.0',
        info: { title: 'Test Events', version: '1.0.0' },
        channels: {
          'user.created': {
            subscribe: { message: { payload: { type: 'object' } } }
            // publish operation removed
          }
        }
      };

      const oldFile = path.join(testDir, 'old-events.yaml');
      const newFile = path.join(testDir, 'new-events.yaml');
      
      fs.writeFileSync(oldFile, JSON.stringify(oldSpec, null, 2));
      fs.writeFileSync(newFile, JSON.stringify(newSpec, null, 2));

      const result = await analyzer.compareAsyncAPISpecs(oldFile, newFile);
      
      expect(result.breakingChanges).toContain('Channel user.created: Removed publish operation');
    });

    it('should detect message schema changes as breaking changes', async () => {
      const oldSpec = {
        asyncapi: '2.6.0',
        info: { title: 'Test Events', version: '1.0.0' },
        channels: {},
        components: {
          messages: {
            UserCreated: {
              payload: {
                type: 'object',
                required: ['id', 'name'],
                properties: {
                  id: { type: 'string' },
                  name: { type: 'string' },
                  email: { type: 'string' }
                }
              }
            }
          }
        }
      };

      const newSpec = {
        asyncapi: '2.6.0',
        info: { title: 'Test Events', version: '1.0.0' },
        channels: {},
        components: {
          messages: {
            UserCreated: {
              payload: {
                type: 'object',
                required: ['id', 'name', 'email'], // email now required
                properties: {
                  id: { type: 'string' },
                  name: { type: 'string' }
                  // email property removed
                }
              }
            }
          }
        }
      };

      const oldFile = path.join(testDir, 'old-events.yaml');
      const newFile = path.join(testDir, 'new-events.yaml');
      
      fs.writeFileSync(oldFile, JSON.stringify(oldSpec, null, 2));
      fs.writeFileSync(newFile, JSON.stringify(newSpec, null, 2));

      const result = await analyzer.compareAsyncAPISpecs(oldFile, newFile);
      
      // Check that breaking changes were detected (the exact message format may vary)
      expect(result.breakingChanges.length).toBeGreaterThan(0);
      expect(result.breakingChanges.some(change => 
        change.includes('UserCreated') && change.includes('email') && change.includes('required')
      )).toBe(true);
      expect(result.breakingChanges.some(change => 
        change.includes('UserCreated') && change.includes('email') && change.includes('Removed')
      )).toBe(true);
    });
  });

  describe('Report Generation', () => {
    it('should generate a properly formatted report', () => {
      const diffResult = {
        breakingChanges: ['Removed endpoint: /users', 'Removed required parameter: id'],
        nonBreakingChanges: ['Added endpoint: /posts', 'Added optional parameter: limit'],
        warnings: ['Major version change detected: 1.0.0 → 2.0.0']
      };

      const report = analyzer.generateReport(diffResult);
      
      expect(report).toContain('# Contract Diff Report');
      expect(report).toContain('## 🚨 Breaking Changes');
      expect(report).toContain('## ✅ Non-Breaking Changes');
      expect(report).toContain('## ⚠️ Warnings');
      expect(report).toContain('❌ Removed endpoint: /users');
      expect(report).toContain('✅ Added endpoint: /posts');
      expect(report).toContain('⚠️ Major version change detected: 1.0.0 → 2.0.0');
    });

    it('should generate report for no changes', () => {
      const diffResult = {
        breakingChanges: [],
        nonBreakingChanges: [],
        warnings: []
      };

      const report = analyzer.generateReport(diffResult);
      
      expect(report).toContain('## ✅ No Changes Detected');
      expect(report).toContain('The specifications are identical.');
    });
  });

  describe('Error Handling', () => {
    it('should handle missing files gracefully', async () => {
      await expect(
        analyzer.compareOpenAPISpecs('non-existent-old.yaml', 'non-existent-new.yaml')
      ).rejects.toThrow('Specification file not found');
    });

    it('should handle invalid JSON/YAML gracefully', async () => {
      const invalidFile = path.join(testDir, 'invalid.yaml');
      fs.writeFileSync(invalidFile, 'invalid: yaml: content: [unclosed');

      const validSpec = {
        openapi: '3.0.0',
        info: { title: 'Test API', version: '1.0.0' },
        paths: {}
      };
      const validFile = path.join(testDir, 'valid.yaml');
      fs.writeFileSync(validFile, JSON.stringify(validSpec, null, 2));

      await expect(
        analyzer.compareOpenAPISpecs(invalidFile, validFile)
      ).rejects.toThrow('Failed to compare OpenAPI specs');
    });
  });
});
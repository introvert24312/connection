import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import ContractValidator from '../scripts/contract-validator.js';

describe('AsyncAPI Contract Validation', () => {
  let validator;
  let testDir;

  beforeEach(() => {
    validator = new ContractValidator();
    testDir = 'test-async-contracts';
    
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

  describe('validateAsyncAPI', () => {
    it('should validate a correct AsyncAPI 2.0 specification', async () => {
      const validSpec = {
        asyncapi: '2.6.0',
        info: {
          title: 'User Events API',
          version: '1.0.0',
          description: 'API for user-related events'
        },
        channels: {
          'user/created': {
            description: 'Channel for user creation events',
            publish: {
              summary: 'User created event',
              message: {
                $ref: '#/components/messages/UserCreated'
              }
            }
          },
          'user/updated': {
            description: 'Channel for user update events',
            publish: {
              summary: 'User updated event',
              message: {
                $ref: '#/components/messages/UserUpdated'
              }
            }
          }
        },
        components: {
          messages: {
            UserCreated: {
              name: 'UserCreated',
              title: 'User Created',
              summary: 'A user has been created',
              payload: {
                type: 'object',
                properties: {
                  userId: {
                    type: 'string',
                    format: 'uuid'
                  },
                  email: {
                    type: 'string',
                    format: 'email'
                  },
                  createdAt: {
                    type: 'string',
                    format: 'date-time'
                  }
                },
                required: ['userId', 'email', 'createdAt']
              }
            },
            UserUpdated: {
              name: 'UserUpdated',
              title: 'User Updated',
              summary: 'A user has been updated',
              payload: {
                type: 'object',
                properties: {
                  userId: {
                    type: 'string',
                    format: 'uuid'
                  },
                  updatedFields: {
                    type: 'array',
                    items: {
                      type: 'string'
                    }
                  },
                  updatedAt: {
                    type: 'string',
                    format: 'date-time'
                  }
                },
                required: ['userId', 'updatedAt']
              }
            }
          }
        }
      };

      const testFile = path.join(testDir, 'valid-events.yaml');
      fs.writeFileSync(testFile, JSON.stringify(validSpec, null, 2));

      const result = await validator.validateAsyncAPI(testFile);
      
      expect(result.valid).toBe(true);
      expect(result.errors).toHaveLength(0);
      expect(result.spec).toBeDefined();
    });

    it('should reject AsyncAPI specification with missing required fields', async () => {
      const invalidSpec = {
        asyncapi: '2.6.0',
        // Missing info and channels
      };

      const testFile = path.join(testDir, 'invalid-events.yaml');
      fs.writeFileSync(testFile, JSON.stringify(invalidSpec, null, 2));

      const result = await validator.validateAsyncAPI(testFile);
      
      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
      expect(result.errors.some(error => error.includes('info'))).toBe(true);
      expect(result.errors.some(error => error.includes('channels'))).toBe(true);
    });

    it('should reject unsupported AsyncAPI versions', async () => {
      const invalidSpec = {
        asyncapi: '1.2.0',
        info: {
          title: 'Test Events',
          version: '1.0.0'
        },
        channels: {}
      };

      const testFile = path.join(testDir, 'old-version-events.yaml');
      fs.writeFileSync(testFile, JSON.stringify(invalidSpec, null, 2));

      const result = await validator.validateAsyncAPI(testFile);
      
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('Unsupported AsyncAPI version'))).toBe(true);
    });

    it('should handle missing asyncapi field', async () => {
      const invalidSpec = {
        info: {
          title: 'Test Events',
          version: '1.0.0'
        },
        channels: {}
      };

      const testFile = path.join(testDir, 'no-version-events.yaml');
      fs.writeFileSync(testFile, JSON.stringify(invalidSpec, null, 2));

      const result = await validator.validateAsyncAPI(testFile);
      
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('Missing required field: asyncapi'))).toBe(true);
    });

    it('should handle file not found', async () => {
      const result = await validator.validateAsyncAPI('non-existent-events.yaml');
      
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('File not found'))).toBe(true);
    });

    it('should handle invalid YAML syntax', async () => {
      const testFile = path.join(testDir, 'invalid-yaml-events.yaml');
      fs.writeFileSync(testFile, 'invalid: yaml: content: [unclosed');

      const result = await validator.validateAsyncAPI(testFile);
      
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('Failed to parse specification'))).toBe(true);
    });

    it('should provide warnings for missing best practices', async () => {
      const specWithWarnings = {
        asyncapi: '2.6.0',
        info: {
          title: 'Test Events',
          version: '1.0.0'
        },
        channels: {
          'test/channel': {
            // Missing description
            publish: {
              message: {
                payload: {
                  type: 'object'
                }
              }
            }
          }
        }
      };

      const testFile = path.join(testDir, 'warnings-events.yaml');
      fs.writeFileSync(testFile, JSON.stringify(specWithWarnings, null, 2));

      const result = await validator.validateAsyncAPI(testFile);
      
      expect(result.valid).toBe(true);
      expect(result.warnings.length).toBeGreaterThan(0);
      expect(result.warnings.some(warning => warning.includes('Missing description'))).toBe(true);
    });

    it('should warn about channels without operations', async () => {
      const specWithEmptyChannels = {
        asyncapi: '2.6.0',
        info: {
          title: 'Test Events',
          version: '1.0.0'
        },
        channels: {
          'empty/channel': {
            description: 'A channel with no operations'
            // No publish or subscribe
          }
        }
      };

      const testFile = path.join(testDir, 'empty-channels-events.yaml');
      fs.writeFileSync(testFile, JSON.stringify(specWithEmptyChannels, null, 2));

      const result = await validator.validateAsyncAPI(testFile);
      
      expect(result.valid).toBe(true);
      expect(result.warnings.some(warning => 
        warning.includes('No publish or subscribe operations defined')
      )).toBe(true);
    });

    it('should error on missing message definitions', async () => {
      const specWithMissingMessages = {
        asyncapi: '2.6.0',
        info: {
          title: 'Test Events',
          version: '1.0.0'
        },
        channels: {
          'test/channel': {
            description: 'Test channel',
            publish: {
              // Missing message definition
            }
          }
        }
      };

      const testFile = path.join(testDir, 'missing-messages-events.yaml');
      fs.writeFileSync(testFile, JSON.stringify(specWithMissingMessages, null, 2));

      const result = await validator.validateAsyncAPI(testFile);
      
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => 
        error.includes('Missing message definition')
      )).toBe(true);
    });

    it('should warn about messages without payload schemas', async () => {
      const specWithoutPayloads = {
        asyncapi: '2.6.0',
        info: {
          title: 'Test Events',
          version: '1.0.0'
        },
        channels: {
          'test/channel': {
            description: 'Test channel',
            publish: {
              message: {
                name: 'TestMessage'
                // Missing payload
              }
            }
          }
        },
        components: {
          messages: {
            TestMessage: {
              name: 'TestMessage'
              // Missing payload
            }
          }
        }
      };

      const testFile = path.join(testDir, 'no-payload-events.yaml');
      fs.writeFileSync(testFile, JSON.stringify(specWithoutPayloads, null, 2));

      const result = await validator.validateAsyncAPI(testFile);
      
      expect(result.valid).toBe(true);
      expect(result.warnings.some(warning => 
        warning.includes('Missing payload schema')
      )).toBe(true);
    });
  });

  describe('validateAsyncAPIDirectory', () => {
    it('should validate all AsyncAPI files in a directory', async () => {
      const contractsDir = path.join(testDir, 'events');
      fs.mkdirSync(contractsDir, { recursive: true });

      // Create valid spec
      const validSpec = {
        asyncapi: '2.6.0',
        info: { title: 'Valid Events', version: '1.0.0' },
        channels: {
          'test/event': {
            description: 'Test event channel',
            publish: {
              message: {
                payload: { type: 'object' }
              }
            }
          }
        }
      };

      fs.writeFileSync(
        path.join(contractsDir, 'valid.asyncapi.yaml'),
        JSON.stringify(validSpec, null, 2)
      );

      const result = await validator.validateAsyncAPIDirectory(contractsDir);
      
      expect(result.valid).toBe(true);
      expect(result.results).toHaveLength(1);
      expect(result.results[0].valid).toBe(true);
    });

    it('should handle directory with mixed valid and invalid files', async () => {
      const contractsDir = path.join(testDir, 'events');
      fs.mkdirSync(contractsDir, { recursive: true });

      // Create valid spec
      const validSpec = {
        asyncapi: '2.6.0',
        info: { title: 'Valid Events', version: '1.0.0' },
        channels: {
          'test/event': {
            description: 'Test event channel',
            publish: {
              message: {
                payload: { type: 'object' }
              }
            }
          }
        }
      };

      // Create invalid spec
      const invalidSpec = {
        asyncapi: '2.6.0'
        // Missing required fields
      };

      fs.writeFileSync(
        path.join(contractsDir, 'valid.asyncapi.yaml'),
        JSON.stringify(validSpec, null, 2)
      );

      fs.writeFileSync(
        path.join(contractsDir, 'invalid.asyncapi.yaml'),
        JSON.stringify(invalidSpec, null, 2)
      );

      const result = await validator.validateAsyncAPIDirectory(contractsDir);
      
      expect(result.valid).toBe(false);
      expect(result.results).toHaveLength(2);
      expect(result.results.find(r => r.file === 'valid.asyncapi.yaml').valid).toBe(true);
      expect(result.results.find(r => r.file === 'invalid.asyncapi.yaml').valid).toBe(false);
    });

    it('should handle non-existent directory gracefully', async () => {
      const result = await validator.validateAsyncAPIDirectory('non-existent-events-dir');
      
      expect(result.valid).toBe(true);
      expect(result.results).toHaveLength(0);
    });

    it('should handle empty directory gracefully', async () => {
      const emptyDir = path.join(testDir, 'empty-events');
      fs.mkdirSync(emptyDir, { recursive: true });

      const result = await validator.validateAsyncAPIDirectory(emptyDir);
      
      expect(result.valid).toBe(true);
      expect(result.results).toHaveLength(0);
    });
  });
});
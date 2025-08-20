import { describe, it, test, expect, beforeEach, afterEach } from 'vitest';
import FeatureFlagValidator from '../scripts/feature-flag-validator.js';
import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('FeatureFlagValidator', () => {
  let validator;
  let testDir;

  beforeEach(() => {
    validator = new FeatureFlagValidator();
    testDir = path.join(__dirname, 'temp');
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

  describe('validateData', () => {
    test('should validate correct feature flag configuration', () => {
      const validData = {
        flags: [
          {
            name: 'login_v2',
            owner: 'Alice',
            default: 'off',
            description: 'New authentication flow'
          },
          {
            name: 'payment_gateway_v3',
            owner: 'Bob @oncall-456',
            default: 'off'
          }
        ]
      };

      const result = validator.validateData(validData);
      expect(result.valid).toBe(true);
      expect(result.errors).toHaveLength(0);
    });

    test('should reject missing required fields', () => {
      const invalidData = {
        flags: [
          {
            name: 'test_flag',
            // missing owner and default
            description: 'Test flag'
          }
        ]
      };

      const result = validator.validateData(invalidData);
      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
      expect(result.errors.some(error => error.includes('owner'))).toBe(true);
      expect(result.errors.some(error => error.includes('default'))).toBe(true);
    });

    test('should reject invalid flag names', () => {
      const invalidData = {
        flags: [
          {
            name: 'invalid-flag-name',
            owner: 'Alice',
            default: 'off'
          }
        ]
      };

      const result = validator.validateData(invalidData);
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('pattern'))).toBe(true);
    });

    test('should reject invalid default values', () => {
      const invalidData = {
        flags: [
          {
            name: 'test_flag',
            owner: 'Alice',
            default: 'maybe'
          }
        ]
      };

      const result = validator.validateData(invalidData);
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('must be equal to one of the allowed values'))).toBe(true);
    });

    test('should reject duplicate flag names', () => {
      const invalidData = {
        flags: [
          {
            name: 'duplicate_flag',
            owner: 'Alice',
            default: 'off'
          },
          {
            name: 'duplicate_flag',
            owner: 'Bob',
            default: 'on'
          }
        ]
      };

      const result = validator.validateData(invalidData);
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('Duplicate flag name'))).toBe(true);
    });

    test('should reject empty flag name', () => {
      const invalidData = {
        flags: [
          {
            name: '',
            owner: 'Alice',
            default: 'off'
          }
        ]
      };

      const result = validator.validateData(invalidData);
      expect(result.valid).toBe(false);
    });

    test('should reject additional properties', () => {
      const invalidData = {
        flags: [
          {
            name: 'test_flag',
            owner: 'Alice',
            default: 'off',
            invalidProperty: 'should not be here'
          }
        ]
      };

      const result = validator.validateData(invalidData);
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('must NOT have additional properties'))).toBe(true);
    });
  });

  describe('validateFile', () => {
    test('should validate valid YAML file', () => {
      const validData = {
        flags: [
          {
            name: 'test_flag',
            owner: 'Alice',
            default: 'off',
            description: 'Test feature flag'
          }
        ]
      };

      const filePath = path.join(testDir, 'valid-flags.yaml');
      fs.writeFileSync(filePath, yaml.dump(validData));

      const result = validator.validateFile(filePath);
      expect(result.valid).toBe(true);
      expect(result.errors).toHaveLength(0);
    });

    test('should handle missing file', () => {
      const filePath = path.join(testDir, 'nonexistent.yaml');
      
      const result = validator.validateFile(filePath);
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('not found'))).toBe(true);
    });

    test('should handle invalid YAML syntax', () => {
      const filePath = path.join(testDir, 'invalid.yaml');
      fs.writeFileSync(filePath, 'invalid: yaml: content: [');

      const result = validator.validateFile(filePath);
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('Failed to parse'))).toBe(true);
    });
  });

  describe('validateDirectory', () => {
    test('should validate flags.yaml in specified directory', () => {
      const validData = {
        flags: [
          {
            name: 'dir_test_flag',
            owner: 'Alice',
            default: 'off'
          }
        ]
      };

      const releaseDir = path.join(testDir, 'release');
      fs.mkdirSync(releaseDir, { recursive: true });
      
      const flagsPath = path.join(releaseDir, 'flags.yaml');
      fs.writeFileSync(flagsPath, yaml.dump(validData));

      const result = validator.validateDirectory(releaseDir);
      expect(result.valid).toBe(true);
    });
  });

  describe('business rules validation', () => {
    test('should warn about flags defaulting to on', () => {
      const originalWarn = console.warn;
      const warnCalls = [];
      console.warn = (...args) => warnCalls.push(args);
      
      const dataWithOnFlag = {
        flags: [
          {
            name: 'always_on_flag',
            owner: 'Alice',
            default: 'on',
            description: 'Flag that defaults to on'
          }
        ]
      };

      const result = validator.validateData(dataWithOnFlag);
      expect(result.valid).toBe(true);
      expect(warnCalls.length).toBeGreaterThan(0);
      expect(warnCalls[0][0]).toContain("defaults to 'on'");

      console.warn = originalWarn;
    });

    test('should validate flag naming conventions', () => {
      const invalidData = {
        flags: [
          {
            name: 'kebab-case-flag',
            owner: 'Alice',
            default: 'off'
          }
        ]
      };

      const result = validator.validateData(invalidData);
      expect(result.valid).toBe(false);
      expect(result.errors.some(error => error.includes('pattern'))).toBe(true);
    });
  });
});
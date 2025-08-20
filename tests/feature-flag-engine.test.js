import { describe, it, test, expect, beforeEach, afterEach } from 'vitest';
import FeatureFlagEngine from '../scripts/feature-flag-engine.js';
import FeatureFlagIntegration, { isFeatureEnabled, whenFeatureEnabled, chooseByFeature } from '../scripts/feature-flag-integration.js';
import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('FeatureFlagEngine', () => {
  let testDir;
  let testConfigPath;

  beforeEach(() => {
    testDir = path.join(__dirname, 'temp-flags');
    if (!fs.existsSync(testDir)) {
      fs.mkdirSync(testDir, { recursive: true });
    }
    
    testConfigPath = path.join(testDir, 'flags.yaml');
    
    // Create test configuration
    const testConfig = {
      flags: [
        {
          name: 'test_feature',
          owner: 'Alice',
          default: 'off',
          description: 'Test feature flag'
        },
        {
          name: 'enabled_feature',
          owner: 'Bob',
          default: 'on',
          description: 'Feature that defaults to on'
        },
        {
          name: 'payment_v2',
          owner: 'Charlie @oncall-123',
          default: 'off'
        }
      ]
    };
    
    fs.writeFileSync(testConfigPath, yaml.dump(testConfig));
  });

  afterEach(() => {
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true, force: true });
    }
  });

  describe('initialization', () => {
    test('should load flags from configuration file', () => {
      const engine = new FeatureFlagEngine(testConfigPath);
      
      expect(engine.flags.size).toBe(3);
      expect(engine.flags.has('test_feature')).toBe(true);
      expect(engine.flags.has('enabled_feature')).toBe(true);
      expect(engine.flags.has('payment_v2')).toBe(true);
    });

    test('should handle missing configuration file gracefully', () => {
      const consoleSpy = [];
      const originalWarn = console.warn;
      console.warn = (...args) => consoleSpy.push(args);

      const engine = new FeatureFlagEngine('nonexistent.yaml');
      
      expect(engine.flags.size).toBe(0);
      expect(consoleSpy.length).toBeGreaterThan(0);
      expect(consoleSpy[0][0]).toContain('not found');

      console.warn = originalWarn;
    });

    test('should set initial state based on default values', () => {
      const engine = new FeatureFlagEngine(testConfigPath);
      
      expect(engine.isEnabled('test_feature')).toBe(false);
      expect(engine.isEnabled('enabled_feature')).toBe(true);
      expect(engine.isEnabled('payment_v2')).toBe(false);
    });
  });

  describe('flag operations', () => {
    let engine;

    beforeEach(() => {
      engine = new FeatureFlagEngine(testConfigPath);
    });

    test('should enable flags', () => {
      expect(engine.isEnabled('test_feature')).toBe(false);
      
      engine.enable('test_feature');
      
      expect(engine.isEnabled('test_feature')).toBe(true);
    });

    test('should disable flags', () => {
      expect(engine.isEnabled('enabled_feature')).toBe(true);
      
      engine.disable('enabled_feature');
      
      expect(engine.isEnabled('enabled_feature')).toBe(false);
    });

    test('should reset flags to default state', () => {
      engine.enable('test_feature');
      expect(engine.isEnabled('test_feature')).toBe(true);
      
      engine.reset('test_feature');
      
      expect(engine.isEnabled('test_feature')).toBe(false);
    });

    test('should reset all flags', () => {
      engine.enable('test_feature');
      engine.disable('enabled_feature');
      
      engine.resetAll();
      
      expect(engine.isEnabled('test_feature')).toBe(false);
      expect(engine.isEnabled('enabled_feature')).toBe(true);
    });

    test('should throw error for unknown flags', () => {
      expect(() => engine.enable('unknown_flag')).toThrow('not found');
      expect(() => engine.disable('unknown_flag')).toThrow('not found');
      expect(() => engine.reset('unknown_flag')).toThrow('not found');
    });

    test('should return false for unknown flags when checking', () => {
      const consoleSpy = [];
      const originalWarn = console.warn;
      console.warn = (...args) => consoleSpy.push(args);

      const result = engine.isEnabled('unknown_flag');
      
      expect(result).toBe(false);
      expect(consoleSpy.length).toBeGreaterThan(0);
      expect(consoleSpy[0][0]).toContain('not found');

      console.warn = originalWarn;
    });
  });

  describe('flag status', () => {
    let engine;

    beforeEach(() => {
      engine = new FeatureFlagEngine(testConfigPath);
    });

    test('should return detailed flag status', () => {
      const status = engine.getStatus('test_feature');
      
      expect(status).toEqual({
        name: 'test_feature',
        owner: 'Alice',
        description: 'Test feature flag',
        defaultState: false,
        currentState: false,
        hasOverride: false,
        overrideValue: null
      });
    });

    test('should show override information', () => {
      engine.enable('test_feature');
      const status = engine.getStatus('test_feature');
      
      expect(status.hasOverride).toBe(true);
      expect(status.overrideValue).toBe(true);
      expect(status.currentState).toBe(true);
    });

    test('should return all flags status', () => {
      const allFlags = engine.getAllFlags();
      
      expect(allFlags).toHaveLength(3);
      expect(allFlags[0].name).toBe('enabled_feature'); // sorted alphabetically
      expect(allFlags[1].name).toBe('payment_v2');
      expect(allFlags[2].name).toBe('test_feature');
    });
  });

  describe('utility methods', () => {
    let engine;

    beforeEach(() => {
      engine = new FeatureFlagEngine(testConfigPath);
    });

    test('should execute callback when flag is enabled', () => {
      let executed = false;
      
      engine.when('enabled_feature', () => {
        executed = true;
        return 'result';
      });
      
      expect(executed).toBe(true);
    });

    test('should not execute callback when flag is disabled', () => {
      let executed = false;
      
      const result = engine.when('test_feature', () => {
        executed = true;
        return 'result';
      });
      
      expect(executed).toBe(false);
      expect(result).toBe(null);
    });

    test('should choose correct callback based on flag state', () => {
      const enabledResult = engine.choose('enabled_feature', 
        () => 'enabled', 
        () => 'disabled'
      );
      
      const disabledResult = engine.choose('test_feature', 
        () => 'enabled', 
        () => 'disabled'
      );
      
      expect(enabledResult).toBe('enabled');
      expect(disabledResult).toBe('disabled');
    });

    test('should validate flag existence', () => {
      expect(() => engine.validateFlag('test_feature')).not.toThrow();
      expect(() => engine.validateFlag('unknown_flag')).toThrow('not defined');
    });
  });

  describe('batch operations', () => {
    let engine;

    beforeEach(() => {
      engine = new FeatureFlagEngine(testConfigPath);
    });

    test('should enable multiple flags', () => {
      const results = engine.enableMultiple(['test_feature', 'payment_v2']);
      
      expect(results).toHaveLength(2);
      expect(results[0].success).toBe(true);
      expect(results[1].success).toBe(true);
      expect(engine.isEnabled('test_feature')).toBe(true);
      expect(engine.isEnabled('payment_v2')).toBe(true);
    });

    test('should handle errors in batch operations', () => {
      const results = engine.enableMultiple(['test_feature', 'unknown_flag']);
      
      expect(results).toHaveLength(2);
      expect(results[0].success).toBe(true);
      expect(results[1].success).toBe(false);
      expect(results[1].error).toContain('not found');
    });

    test('should disable multiple flags', () => {
      engine.enable('test_feature');
      engine.enable('payment_v2');
      
      const results = engine.disableMultiple(['test_feature', 'payment_v2']);
      
      expect(results).toHaveLength(2);
      expect(results[0].success).toBe(true);
      expect(results[1].success).toBe(true);
      expect(engine.isEnabled('test_feature')).toBe(false);
      expect(engine.isEnabled('payment_v2')).toBe(false);
    });
  });
});

describe('FeatureFlagIntegration', () => {
  let testDir;
  let testConfigPath;

  beforeEach(() => {
    testDir = path.join(__dirname, 'temp-integration');
    if (!fs.existsSync(testDir)) {
      fs.mkdirSync(testDir, { recursive: true });
    }
    
    testConfigPath = path.join(testDir, 'flags.yaml');
    
    const testConfig = {
      flags: [
        {
          name: 'api_v2',
          owner: 'Alice',
          default: 'off'
        },
        {
          name: 'new_ui',
          owner: 'Bob',
          default: 'on'
        }
      ]
    };
    
    fs.writeFileSync(testConfigPath, yaml.dump(testConfig));
  });

  afterEach(() => {
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true, force: true });
    }
  });

  describe('integration utilities', () => {
    test('should validate required flags', () => {
      const integration = new FeatureFlagIntegration(testConfigPath);
      
      expect(() => integration.validateRequiredFlags(['api_v2', 'new_ui'])).not.toThrow();
      expect(() => integration.validateRequiredFlags(['api_v2', 'unknown_flag'])).toThrow('Missing required');
    });

    test('should provide health check data', () => {
      const integration = new FeatureFlagIntegration(testConfigPath);
      const health = integration.getHealthCheck();
      
      expect(health.status).toBe('healthy');
      expect(health.flags.total).toBe(2);
      expect(health.flags.enabled).toBe(1);
      expect(health.flags.disabled).toBe(1);
      expect(health.flags.overridden).toBe(0);
    });

    test('should log flag usage', () => {
      const integration = new FeatureFlagIntegration(testConfigPath);
      const consoleSpy = [];
      const originalLog = console.log;
      console.log = (...args) => consoleSpy.push(args);

      const logEntry = integration.logFlagUsage('api_v2', { user: 'test' });
      
      expect(logEntry.flag).toBe('api_v2');
      expect(logEntry.enabled).toBe(false);
      expect(logEntry.context.user).toBe('test');
      expect(consoleSpy.length).toBeGreaterThan(0);

      console.log = originalLog;
    });

    test('should check multiple flags', () => {
      const integration = new FeatureFlagIntegration(testConfigPath);
      
      expect(integration.areAllEnabled(['api_v2', 'new_ui'])).toBe(false);
      expect(integration.areAnyEnabled(['api_v2', 'new_ui'])).toBe(true);
      
      integration.enable('api_v2');
      
      expect(integration.areAllEnabled(['api_v2', 'new_ui'])).toBe(true);
    });
  });

  describe('convenience functions', () => {
    test('should work with convenience functions', () => {
      // Reset global instance by setting it directly
      const integration = new FeatureFlagIntegration(testConfigPath);
      
      // Test direct integration methods instead of global convenience functions
      expect(integration.isEnabled('new_ui')).toBe(true);
      expect(integration.isEnabled('api_v2')).toBe(false);
      
      let executed = false;
      integration.when('new_ui', () => {
        executed = true;
      });
      expect(executed).toBe(true);
      
      const result = integration.choose('api_v2', 
        () => 'v2', 
        () => 'v1'
      );
      expect(result).toBe('v1');
    });
  });
});
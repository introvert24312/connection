#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

class FeatureFlagEngine {
  constructor(configPath = 'docs/release/flags.yaml') {
    this.configPath = configPath;
    this.flags = new Map();
    this.overrides = new Map();
    this.loadFlags();
  }

  loadFlags() {
    try {
      if (!fs.existsSync(this.configPath)) {
        console.warn(`Feature flags config not found at ${this.configPath}, using empty configuration`);
        return;
      }

      const content = fs.readFileSync(this.configPath, 'utf8');
      const config = yaml.load(content);

      if (!config || !config.flags) {
        console.warn('No flags found in configuration');
        return;
      }

      // Load flags with their default states
      config.flags.forEach(flag => {
        this.flags.set(flag.name, {
          name: flag.name,
          owner: flag.owner,
          default: flag.default === 'on',
          description: flag.description || '',
          enabled: flag.default === 'on' // Start with default state
        });
      });

      console.log(`Loaded ${this.flags.size} feature flags`);
    } catch (error) {
      console.error(`Failed to load feature flags: ${error.message}`);
      throw error;
    }
  }

  reloadFlags() {
    this.flags.clear();
    this.loadFlags();
  }

  isEnabled(flagName) {
    // Check for runtime overrides first
    if (this.overrides.has(flagName)) {
      return this.overrides.get(flagName);
    }

    // Check if flag exists in configuration
    const flag = this.flags.get(flagName);
    if (!flag) {
      console.warn(`Feature flag '${flagName}' not found, defaulting to false`);
      return false;
    }

    return flag.enabled;
  }

  enable(flagName) {
    const flag = this.flags.get(flagName);
    if (!flag) {
      throw new Error(`Feature flag '${flagName}' not found`);
    }

    this.overrides.set(flagName, true);
    console.log(`Feature flag '${flagName}' enabled`);
  }

  disable(flagName) {
    const flag = this.flags.get(flagName);
    if (!flag) {
      throw new Error(`Feature flag '${flagName}' not found`);
    }

    this.overrides.set(flagName, false);
    console.log(`Feature flag '${flagName}' disabled`);
  }

  reset(flagName) {
    if (!this.flags.has(flagName)) {
      throw new Error(`Feature flag '${flagName}' not found`);
    }

    this.overrides.delete(flagName);
    console.log(`Feature flag '${flagName}' reset to default state`);
  }

  resetAll() {
    this.overrides.clear();
    console.log('All feature flag overrides cleared');
  }

  getStatus(flagName) {
    const flag = this.flags.get(flagName);
    if (!flag) {
      return null;
    }

    const hasOverride = this.overrides.has(flagName);
    const currentState = this.isEnabled(flagName);

    return {
      name: flag.name,
      owner: flag.owner,
      description: flag.description,
      defaultState: flag.default,
      currentState: currentState,
      hasOverride: hasOverride,
      overrideValue: hasOverride ? this.overrides.get(flagName) : null
    };
  }

  getAllFlags() {
    const result = [];
    
    for (const [name, flag] of this.flags) {
      result.push(this.getStatus(name));
    }

    return result.sort((a, b) => a.name.localeCompare(b.name));
  }

  // Utility method for conditional code execution
  when(flagName, callback) {
    if (this.isEnabled(flagName)) {
      return callback();
    }
    return null;
  }

  // Utility method for A/B testing style flags
  choose(flagName, onEnabled, onDisabled) {
    if (this.isEnabled(flagName)) {
      return onEnabled();
    }
    return onDisabled();
  }

  // Validation method to ensure all referenced flags exist
  validateFlag(flagName) {
    if (!this.flags.has(flagName)) {
      throw new Error(`Feature flag '${flagName}' is not defined in ${this.configPath}`);
    }
  }

  // Batch operations
  enableMultiple(flagNames) {
    const results = [];
    for (const flagName of flagNames) {
      try {
        this.enable(flagName);
        results.push({ flag: flagName, success: true });
      } catch (error) {
        results.push({ flag: flagName, success: false, error: error.message });
      }
    }
    return results;
  }

  disableMultiple(flagNames) {
    const results = [];
    for (const flagName of flagNames) {
      try {
        this.disable(flagName);
        results.push({ flag: flagName, success: true });
      } catch (error) {
        results.push({ flag: flagName, success: false, error: error.message });
      }
    }
    return results;
  }
}

// CLI usage
if (import.meta.url === `file://${process.argv[1]}`) {
  const command = process.argv[2];
  const flagName = process.argv[3];
  const configPath = process.argv[4] || 'docs/release/flags.yaml';

  const engine = new FeatureFlagEngine(configPath);

  switch (command) {
    case 'check':
      if (!flagName) {
        console.error('Usage: feature-flag-engine.js check <flag-name>');
        process.exit(1);
      }
      console.log(`Flag '${flagName}' is ${engine.isEnabled(flagName) ? 'ENABLED' : 'DISABLED'}`);
      break;

    case 'enable':
      if (!flagName) {
        console.error('Usage: feature-flag-engine.js enable <flag-name>');
        process.exit(1);
      }
      try {
        engine.enable(flagName);
      } catch (error) {
        console.error(error.message);
        process.exit(1);
      }
      break;

    case 'disable':
      if (!flagName) {
        console.error('Usage: feature-flag-engine.js disable <flag-name>');
        process.exit(1);
      }
      try {
        engine.disable(flagName);
      } catch (error) {
        console.error(error.message);
        process.exit(1);
      }
      break;

    case 'status':
      if (flagName) {
        const status = engine.getStatus(flagName);
        if (status) {
          console.log(JSON.stringify(status, null, 2));
        } else {
          console.error(`Flag '${flagName}' not found`);
          process.exit(1);
        }
      } else {
        console.log(JSON.stringify(engine.getAllFlags(), null, 2));
      }
      break;

    case 'reset':
      if (flagName) {
        try {
          engine.reset(flagName);
        } catch (error) {
          console.error(error.message);
          process.exit(1);
        }
      } else {
        engine.resetAll();
      }
      break;

    default:
      console.log('Usage: feature-flag-engine.js <command> [flag-name] [config-path]');
      console.log('Commands:');
      console.log('  check <flag-name>    - Check if flag is enabled');
      console.log('  enable <flag-name>   - Enable a flag');
      console.log('  disable <flag-name>  - Disable a flag');
      console.log('  status [flag-name]   - Show flag status (all flags if no name provided)');
      console.log('  reset [flag-name]    - Reset flag to default (all flags if no name provided)');
      process.exit(1);
  }
}

export default FeatureFlagEngine;
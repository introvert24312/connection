#!/usr/bin/env node

import FeatureFlagEngine from './feature-flag-engine.js';

// Singleton instance for application-wide use
let globalEngine = null;

export class FeatureFlagIntegration {
  constructor(configPath = 'docs/release/flags.yaml') {
    this.engine = new FeatureFlagEngine(configPath);
  }

  // Static method to get global instance
  static getInstance(configPath = 'docs/release/flags.yaml') {
    if (!globalEngine) {
      globalEngine = new FeatureFlagIntegration(configPath);
    }
    return globalEngine;
  }

  // Decorator for feature flag controlled functions
  static featureFlag(flagName) {
    return function(target, propertyKey, descriptor) {
      const originalMethod = descriptor.value;
      
      descriptor.value = function(...args) {
        const integration = FeatureFlagIntegration.getInstance();
        
        if (integration.isEnabled(flagName)) {
          return originalMethod.apply(this, args);
        } else {
          console.log(`Method ${propertyKey} skipped - feature flag '${flagName}' is disabled`);
          return null;
        }
      };
      
      return descriptor;
    };
  }

  // Middleware for Express.js applications
  static expressMiddleware(flagName, options = {}) {
    return (req, res, next) => {
      const integration = FeatureFlagIntegration.getInstance();
      
      if (integration.isEnabled(flagName)) {
        next();
      } else {
        if (options.fallback) {
          options.fallback(req, res, next);
        } else {
          res.status(404).json({ 
            error: 'Feature not available',
            flag: flagName 
          });
        }
      }
    };
  }

  // React Hook for feature flags (if using React)
  static useFeatureFlag(flagName) {
    const integration = FeatureFlagIntegration.getInstance();
    return integration.isEnabled(flagName);
  }

  // Proxy methods to engine
  isEnabled(flagName) {
    return this.engine.isEnabled(flagName);
  }

  enable(flagName) {
    return this.engine.enable(flagName);
  }

  disable(flagName) {
    return this.engine.disable(flagName);
  }

  getStatus(flagName) {
    return this.engine.getStatus(flagName);
  }

  getAllFlags() {
    return this.engine.getAllFlags();
  }

  when(flagName, callback) {
    return this.engine.when(flagName, callback);
  }

  choose(flagName, onEnabled, onDisabled) {
    return this.engine.choose(flagName, onEnabled, onDisabled);
  }

  // Configuration validation for application startup
  validateRequiredFlags(requiredFlags) {
    const missing = [];
    const errors = [];

    for (const flagName of requiredFlags) {
      try {
        this.engine.validateFlag(flagName);
      } catch (error) {
        missing.push(flagName);
        errors.push(error.message);
      }
    }

    if (missing.length > 0) {
      throw new Error(`Missing required feature flags: ${missing.join(', ')}`);
    }

    return true;
  }

  // Health check endpoint data
  getHealthCheck() {
    const flags = this.getAllFlags();
    const enabled = flags.filter(f => f.currentState).length;
    const total = flags.length;
    const overridden = flags.filter(f => f.hasOverride).length;

    return {
      status: 'healthy',
      flags: {
        total,
        enabled,
        disabled: total - enabled,
        overridden
      },
      timestamp: new Date().toISOString()
    };
  }

  // Logging integration
  logFlagUsage(flagName, context = {}) {
    const status = this.getStatus(flagName);
    const logEntry = {
      timestamp: new Date().toISOString(),
      flag: flagName,
      enabled: status ? status.currentState : false,
      context,
      hasOverride: status ? status.hasOverride : false
    };

    console.log(`[FEATURE_FLAG] ${JSON.stringify(logEntry)}`);
    return logEntry;
  }

  // Batch flag checking for complex features
  areAllEnabled(flagNames) {
    return flagNames.every(flagName => this.isEnabled(flagName));
  }

  areAnyEnabled(flagNames) {
    return flagNames.some(flagName => this.isEnabled(flagName));
  }

  // Environment-based flag overrides
  applyEnvironmentOverrides() {
    const envPrefix = 'FEATURE_FLAG_';
    
    for (const [key, value] of Object.entries(process.env)) {
      if (key.startsWith(envPrefix)) {
        const flagName = key.substring(envPrefix.length).toLowerCase();
        const enabled = value.toLowerCase() === 'true' || value === '1';
        
        try {
          if (enabled) {
            this.enable(flagName);
          } else {
            this.disable(flagName);
          }
          console.log(`Applied environment override: ${flagName} = ${enabled}`);
        } catch (error) {
          console.warn(`Failed to apply environment override for ${flagName}: ${error.message}`);
        }
      }
    }
  }
}

// Convenience functions for direct usage
export function isFeatureEnabled(flagName) {
  return FeatureFlagIntegration.getInstance().isEnabled(flagName);
}

export function whenFeatureEnabled(flagName, callback) {
  return FeatureFlagIntegration.getInstance().when(flagName, callback);
}

export function chooseByFeature(flagName, onEnabled, onDisabled) {
  return FeatureFlagIntegration.getInstance().choose(flagName, onEnabled, onDisabled);
}

export default FeatureFlagIntegration;
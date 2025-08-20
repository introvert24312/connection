/**
 * Tracing Logger
 * 
 * Structured logging utilities that automatically include traceId in all log entries.
 * Supports JSON formatting and integration with popular logging frameworks.
 */

import { getOrGenerateTraceId, isValidTraceId } from './tracing-utils.js';

/**
 * Log levels enum
 */
const LOG_LEVELS = {
  ERROR: 'error',
  WARN: 'warn',
  INFO: 'info',
  DEBUG: 'debug'
};

/**
 * Default log level priority for filtering (lower number = higher priority)
 */
const LOG_LEVEL_PRIORITY = {
  error: 0,
  warn: 1,
  info: 2,
  debug: 3
};

/**
 * TracingLogger class that automatically includes traceId in all log entries
 */
class TracingLogger {
  constructor(options = {}) {
    this.serviceName = options.serviceName || 'unknown-service';
    this.logLevel = options.logLevel || LOG_LEVELS.INFO;
    this.enableConsole = options.enableConsole !== false;
    this.enableJson = options.enableJson !== false;
    this.customFields = options.customFields || {};
    this.traceIdExtractor = options.traceIdExtractor || null;
  }

  /**
   * Create a structured log entry with traceId
   * @param {string} level - Log level
   * @param {string} message - Log message
   * @param {Object} metadata - Additional metadata
   * @param {string} traceId - Optional traceId (will be extracted if not provided)
   * @returns {Object} Structured log entry
   */
  createLogEntry(level, message, metadata = {}, traceId = null) {
    // Extract or use provided traceId
    if (!traceId && this.traceIdExtractor) {
      traceId = this.traceIdExtractor();
    }

    const timestamp = new Date().toISOString();
    
    const logEntry = {
      timestamp,
      level,
      service: this.serviceName,
      message,
      traceId: traceId || null,
      ...this.customFields,
      ...metadata
    };

    // Remove null traceId if not available
    if (!logEntry.traceId) {
      delete logEntry.traceId;
    }

    return logEntry;
  }

  /**
   * Check if log level should be output
   * @param {string} level - Log level to check
   * @returns {boolean} True if should log
   */
  shouldLog(level) {
    const currentLevelPriority = LOG_LEVEL_PRIORITY[this.logLevel];
    const messageLevelPriority = LOG_LEVEL_PRIORITY[level];
    
    // If either level is unknown, default to logging
    if (currentLevelPriority === undefined || messageLevelPriority === undefined) {
      return true;
    }
    
    // Log if message priority is higher or equal (lower number = higher priority)
    return messageLevelPriority <= currentLevelPriority;
  }

  /**
   * Output log entry to console and/or other destinations
   * @param {Object} logEntry - Structured log entry
   */
  output(logEntry) {
    if (!this.shouldLog(logEntry.level)) {
      return;
    }

    if (this.enableConsole) {
      if (this.enableJson) {
        console.log(JSON.stringify(logEntry));
      } else {
        const { timestamp, level, service, message, traceId, ...rest } = logEntry;
        const traceInfo = traceId ? ` [trace:${traceId}]` : '';
        const metaInfo = Object.keys(rest).length > 0 ? ` ${JSON.stringify(rest)}` : '';
        console.log(`${timestamp} [${level.toUpperCase()}] ${service}${traceInfo}: ${message}${metaInfo}`);
      }
    }
  }

  /**
   * Log error message
   * @param {string} message - Error message
   * @param {Object} metadata - Additional metadata
   * @param {string} traceId - Optional traceId
   */
  error(message, metadata = {}, traceId = null) {
    const logEntry = this.createLogEntry(LOG_LEVELS.ERROR, message, metadata, traceId);
    this.output(logEntry);
    return logEntry;
  }

  /**
   * Log warning message
   * @param {string} message - Warning message
   * @param {Object} metadata - Additional metadata
   * @param {string} traceId - Optional traceId
   */
  warn(message, metadata = {}, traceId = null) {
    const logEntry = this.createLogEntry(LOG_LEVELS.WARN, message, metadata, traceId);
    this.output(logEntry);
    return logEntry;
  }

  /**
   * Log info message
   * @param {string} message - Info message
   * @param {Object} metadata - Additional metadata
   * @param {string} traceId - Optional traceId
   */
  info(message, metadata = {}, traceId = null) {
    const logEntry = this.createLogEntry(LOG_LEVELS.INFO, message, metadata, traceId);
    this.output(logEntry);
    return logEntry;
  }

  /**
   * Log debug message
   * @param {string} message - Debug message
   * @param {Object} metadata - Additional metadata
   * @param {string} traceId - Optional traceId
   */
  debug(message, metadata = {}, traceId = null) {
    const logEntry = this.createLogEntry(LOG_LEVELS.DEBUG, message, metadata, traceId);
    this.output(logEntry);
    return logEntry;
  }

  /**
   * Create a child logger with additional context
   * @param {Object} context - Additional context to include in all logs
   * @returns {TracingLogger} New logger instance with context
   */
  child(context = {}) {
    return new TracingLogger({
      serviceName: this.serviceName,
      logLevel: this.logLevel,
      enableConsole: this.enableConsole,
      enableJson: this.enableJson,
      customFields: { ...this.customFields, ...context },
      traceIdExtractor: this.traceIdExtractor
    });
  }
}

/**
 * Express middleware for request logging with traceId
 * @param {TracingLogger} logger - Logger instance to use
 * @param {Object} options - Middleware options
 * @returns {Function} Express middleware function
 */
function expressLoggingMiddleware(logger, options = {}) {
  const {
    logRequests = true,
    logResponses = true,
    includeBody = false,
    excludePaths = []
  } = options;

  return (req, res, next) => {
    const startTime = Date.now();
    const traceId = req.traceId;

    // Skip logging for excluded paths
    if (excludePaths.some(path => req.path.startsWith(path))) {
      return next();
    }

    // Log incoming request
    if (logRequests) {
      const requestMetadata = {
        method: req.method,
        url: req.url,
        userAgent: req.get('User-Agent'),
        ip: req.ip || req.connection.remoteAddress
      };

      if (includeBody && req.body) {
        requestMetadata.body = req.body;
      }

      logger.info('Incoming request', requestMetadata, traceId);
    }

    // Override res.end to log response
    if (logResponses) {
      const originalEnd = res.end;
      res.end = function(chunk, encoding) {
        const duration = Date.now() - startTime;
        const responseMetadata = {
          method: req.method,
          url: req.url,
          statusCode: res.statusCode,
          duration: `${duration}ms`
        };

        if (res.statusCode >= 400) {
          logger.warn('Request completed with error', responseMetadata, traceId);
        } else {
          logger.info('Request completed', responseMetadata, traceId);
        }

        originalEnd.call(this, chunk, encoding);
      };
    }

    next();
  };
}

/**
 * Create a logger instance with traceId extraction from request context
 * @param {Object} options - Logger configuration options
 * @returns {TracingLogger} Configured logger instance
 */
function createRequestLogger(options = {}) {
  return new TracingLogger({
    ...options,
    traceIdExtractor: () => {
      // This would typically be extracted from async context or request context
      // For now, return null and let individual log calls provide traceId
      return null;
    }
  });
}

/**
 * Winston transport for tracing logs
 * Integrates with Winston logging framework to include traceId
 */
class WinstonTracingTransport {
  constructor(options = {}) {
    this.name = 'tracing-transport';
    this.level = options.level || 'info';
    this.serviceName = options.serviceName || 'unknown-service';
  }

  log(info, callback) {
    // Add service name to Winston log info if traceId is valid
    if (info.traceId && isValidTraceId(info.traceId)) {
      info.service = this.serviceName;
    }

    // Call callback to indicate transport is done
    if (callback) {
      setImmediate(() => callback());
    }

    return true;
  }
}

/**
 * Pino logger configuration with traceId support
 * @param {Object} options - Pino configuration options
 * @returns {Object} Pino logger configuration
 */
function createPinoConfig(options = {}) {
  return {
    level: options.level || 'info',
    formatters: {
      level: (label) => {
        return { level: label };
      }
    },
    serializers: {
      req: (req) => ({
        method: req.method,
        url: req.url,
        traceId: req.traceId
      }),
      res: (res) => ({
        statusCode: res.statusCode
      })
    },
    base: {
      service: options.serviceName || 'unknown-service'
    }
  };
}

/**
 * Global logger instance
 */
let globalLogger = null;

/**
 * Initialize global logger
 * @param {Object} options - Logger configuration
 */
function initializeGlobalLogger(options = {}) {
  globalLogger = new TracingLogger(options);
}

/**
 * Get global logger instance
 * @returns {TracingLogger} Global logger instance
 */
function getGlobalLogger() {
  if (!globalLogger) {
    globalLogger = new TracingLogger();
  }
  return globalLogger;
}

export {
  TracingLogger,
  LOG_LEVELS,
  expressLoggingMiddleware,
  createRequestLogger,
  WinstonTracingTransport,
  createPinoConfig,
  initializeGlobalLogger,
  getGlobalLogger
};
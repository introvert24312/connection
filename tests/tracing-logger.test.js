/**
 * Tests for tracing logger
 */

import { describe, test, expect, beforeEach, afterEach, vi } from 'vitest';

// Mock tracing-utils
vi.mock('../scripts/tracing-utils.js', () => ({
  getOrGenerateTraceId: vi.fn(),
  isValidTraceId: vi.fn().mockReturnValue(true)
}));

import {
  TracingLogger,
  LOG_LEVELS,
  expressLoggingMiddleware,
  createRequestLogger,
  WinstonTracingTransport,
  createPinoConfig,
  initializeGlobalLogger,
  getGlobalLogger
} from '../scripts/tracing-logger.js';

describe('Tracing Logger', () => {
  let consoleSpy;

  beforeEach(() => {
    consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
  });

  afterEach(() => {
    consoleSpy.mockRestore();
  });

  describe('TracingLogger', () => {
    test('should create log entry with traceId', () => {
      const logger = new TracingLogger({ serviceName: 'test-service' });
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      
      const logEntry = logger.createLogEntry('info', 'Test message', { key: 'value' }, traceId);
      
      expect(logEntry).toMatchObject({
        level: 'info',
        service: 'test-service',
        message: 'Test message',
        traceId: traceId,
        key: 'value'
      });
      expect(logEntry.timestamp).toBeDefined();
    });

    test('should create log entry without traceId', () => {
      const logger = new TracingLogger({ serviceName: 'test-service' });
      
      const logEntry = logger.createLogEntry('info', 'Test message', { key: 'value' });
      
      expect(logEntry).toMatchObject({
        level: 'info',
        service: 'test-service',
        message: 'Test message',
        key: 'value'
      });
      expect(logEntry.traceId).toBeUndefined();
    });

    test('should respect log level filtering', () => {
      const logger = new TracingLogger({ logLevel: 'warn' });
      
      expect(logger.shouldLog('error')).toBe(true);
      expect(logger.shouldLog('warn')).toBe(true);
      expect(logger.shouldLog('info')).toBe(false);
      expect(logger.shouldLog('debug')).toBe(false);
    });

    test('should log error messages', () => {
      const logger = new TracingLogger({ serviceName: 'test-service', enableJson: true });
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      
      const logEntry = logger.error('Error occurred', { errorCode: 500 }, traceId);
      
      expect(logEntry.level).toBe('error');
      expect(logEntry.message).toBe('Error occurred');
      expect(logEntry.traceId).toBe(traceId);
      expect(logEntry.errorCode).toBe(500);
      expect(consoleSpy).toHaveBeenCalled();
    });

    test('should log info messages', () => {
      const logger = new TracingLogger({ serviceName: 'test-service' });
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      
      logger.info('Info message', { requestId: 'req-123' }, traceId);
      
      expect(consoleSpy).toHaveBeenCalled();
    });

    test('should not log debug messages when level is info', () => {
      const logger = new TracingLogger({ logLevel: 'info' });
      
      logger.debug('Debug message');
      
      expect(consoleSpy).not.toHaveBeenCalled();
    });

    test('should output JSON format when enabled', () => {
      const logger = new TracingLogger({ enableJson: true });
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      
      logger.info('Test message', {}, traceId);
      
      expect(consoleSpy).toHaveBeenCalled();
      const loggedData = consoleSpy.mock.calls[0][0];
      expect(() => JSON.parse(loggedData)).not.toThrow();
    });

    test('should output human-readable format when JSON disabled', () => {
      const logger = new TracingLogger({ enableJson: false, serviceName: 'test-service' });
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      
      logger.info('Test message', {}, traceId);
      
      expect(consoleSpy).toHaveBeenCalled();
      const loggedData = consoleSpy.mock.calls[0][0];
      expect(loggedData).toContain('[INFO]');
      expect(loggedData).toContain('test-service');
      expect(loggedData).toContain(`[trace:${traceId}]`);
      expect(loggedData).toContain('Test message');
    });

    test('should create child logger with additional context', () => {
      const parentLogger = new TracingLogger({ serviceName: 'parent-service' });
      const childLogger = parentLogger.child({ component: 'auth' });
      
      const logEntry = childLogger.createLogEntry('info', 'Child message');
      
      expect(logEntry.service).toBe('parent-service');
      expect(logEntry.component).toBe('auth');
    });

    test('should use traceId extractor when provided', () => {
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      const extractor = vi.fn().mockReturnValue(traceId);
      const logger = new TracingLogger({ traceIdExtractor: extractor });
      
      const logEntry = logger.createLogEntry('info', 'Test message');
      
      expect(extractor).toHaveBeenCalled();
      expect(logEntry.traceId).toBe(traceId);
    });
  });

  describe('expressLoggingMiddleware', () => {
    test('should log incoming requests', () => {
      const logger = new TracingLogger();
      const loggerSpy = vi.spyOn(logger, 'info');
      const middleware = expressLoggingMiddleware(logger);
      
      const req = {
        method: 'GET',
        url: '/api/test',
        path: '/api/test',
        traceId: '123e4567-e89b-12d3-a456-426614174000',
        get: vi.fn().mockReturnValue('test-agent'),
        ip: '127.0.0.1'
      };
      const res = {
        end: vi.fn(),
        statusCode: 200
      };
      const next = vi.fn();
      
      middleware(req, res, next);
      
      expect(loggerSpy).toHaveBeenCalledWith(
        'Incoming request',
        expect.objectContaining({
          method: 'GET',
          url: '/api/test',
          userAgent: 'test-agent',
          ip: '127.0.0.1'
        }),
        '123e4567-e89b-12d3-a456-426614174000'
      );
      expect(next).toHaveBeenCalled();
    });

    test('should log response completion', () => {
      const logger = new TracingLogger();
      const loggerSpy = vi.spyOn(logger, 'info');
      const middleware = expressLoggingMiddleware(logger);
      
      const req = {
        method: 'POST',
        url: '/api/create',
        path: '/api/create',
        traceId: '123e4567-e89b-12d3-a456-426614174000',
        get: vi.fn(),
        ip: '127.0.0.1'
      };
      const res = {
        end: vi.fn(),
        statusCode: 201
      };
      const next = vi.fn();
      
      middleware(req, res, next);
      
      // Simulate response end
      res.end();
      
      expect(loggerSpy).toHaveBeenCalledWith(
        'Request completed',
        expect.objectContaining({
          method: 'POST',
          url: '/api/create',
          statusCode: 201,
          duration: expect.stringMatching(/\d+ms/)
        }),
        '123e4567-e89b-12d3-a456-426614174000'
      );
    });

    test('should log error responses with warning level', () => {
      const logger = new TracingLogger();
      const loggerSpy = vi.spyOn(logger, 'warn');
      const middleware = expressLoggingMiddleware(logger);
      
      const req = {
        method: 'GET',
        url: '/api/error',
        path: '/api/error',
        traceId: '123e4567-e89b-12d3-a456-426614174000',
        get: vi.fn(),
        ip: '127.0.0.1'
      };
      const res = {
        end: vi.fn(),
        statusCode: 500
      };
      const next = vi.fn();
      
      middleware(req, res, next);
      res.end();
      
      expect(loggerSpy).toHaveBeenCalledWith(
        'Request completed with error',
        expect.objectContaining({
          statusCode: 500
        }),
        '123e4567-e89b-12d3-a456-426614174000'
      );
    });

    test('should skip logging for excluded paths', () => {
      const logger = new TracingLogger();
      const loggerSpy = vi.spyOn(logger, 'info');
      const middleware = expressLoggingMiddleware(logger, { excludePaths: ['/health'] });
      
      const req = {
        path: '/health',
        traceId: '123e4567-e89b-12d3-a456-426614174000'
      };
      const res = {};
      const next = vi.fn();
      
      middleware(req, res, next);
      
      expect(loggerSpy).not.toHaveBeenCalled();
      expect(next).toHaveBeenCalled();
    });
  });

  describe('createRequestLogger', () => {
    test('should create logger with request context', () => {
      const logger = createRequestLogger({ serviceName: 'api-service' });
      
      expect(logger).toBeInstanceOf(TracingLogger);
      expect(logger.serviceName).toBe('api-service');
    });
  });

  describe('WinstonTracingTransport', () => {
    test('should create Winston transport', () => {
      const transport = new WinstonTracingTransport({ serviceName: 'test-service' });
      
      expect(transport.name).toBe('tracing-transport');
      expect(transport.serviceName).toBe('test-service');
    });

    test('should process log info with traceId', async () => {
      const transport = new WinstonTracingTransport({ serviceName: 'test-service' });
      const callback = vi.fn();
      const info = {
        level: 'info',
        message: 'Test message',
        traceId: '123e4567-e89b-12d3-a456-426614174000'
      };
      
      const result = transport.log(info, callback);
      
      expect(result).toBe(true);
      expect(info.service).toBe('test-service');
      
      // Wait for the async callback
      await new Promise(resolve => setTimeout(resolve, 0));
      expect(callback).toHaveBeenCalled();
    });
  });

  describe('createPinoConfig', () => {
    test('should create Pino configuration', () => {
      const config = createPinoConfig({ serviceName: 'test-service', level: 'debug' });
      
      expect(config.level).toBe('debug');
      expect(config.base.service).toBe('test-service');
      expect(config.serializers).toBeDefined();
      expect(config.formatters).toBeDefined();
    });

    test('should serialize request with traceId', () => {
      const config = createPinoConfig();
      const req = {
        method: 'GET',
        url: '/api/test',
        traceId: '123e4567-e89b-12d3-a456-426614174000'
      };
      
      const serialized = config.serializers.req(req);
      
      expect(serialized).toEqual({
        method: 'GET',
        url: '/api/test',
        traceId: '123e4567-e89b-12d3-a456-426614174000'
      });
    });
  });

  describe('Global Logger', () => {
    test('should initialize global logger', () => {
      initializeGlobalLogger({ serviceName: 'global-service' });
      const logger = getGlobalLogger();
      
      expect(logger).toBeInstanceOf(TracingLogger);
      expect(logger.serviceName).toBe('global-service');
    });

    test('should create default global logger if not initialized', () => {
      // Reset global logger
      initializeGlobalLogger();
      const logger = getGlobalLogger();
      
      expect(logger).toBeInstanceOf(TracingLogger);
    });
  });
});
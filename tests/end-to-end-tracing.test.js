/**
 * End-to-End Tracing Tests
 * 
 * Tests that verify traceId propagation across multiple services and components
 * in a distributed system scenario.
 */

import { describe, test, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  generateTraceId,
  createTracingHeaders,
  extractTraceIdFromHeaders,
  isValidTraceId
} from '../scripts/tracing-utils.js';
import {
  expressTracingMiddleware,
  wrapHttpClientWithTracing,
  createTracingFetch
} from '../scripts/tracing-middleware.js';
import {
  TracingLogger,
  expressLoggingMiddleware
} from '../scripts/tracing-logger.js';

describe('End-to-End Tracing', () => {
  let mockFetch;
  let consoleSpy;

  beforeEach(() => {
    mockFetch = vi.fn();
    global.fetch = mockFetch;
    consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('Single Service Tracing', () => {
    test('should generate and propagate traceId within a single service', () => {
      const traceId = generateTraceId();
      
      // Verify traceId is valid UUID
      expect(isValidTraceId(traceId)).toBe(true);
      
      // Create tracing headers
      const headers = createTracingHeaders(traceId);
      expect(headers['X-Trace-Id']).toBe(traceId);
      expect(headers.traceparent).toContain(traceId.replace(/-/g, ''));
      
      // Extract traceId from headers
      const extractedTraceId = extractTraceIdFromHeaders(headers);
      expect(extractedTraceId).toBe(traceId.replace(/-/g, ''));
    });

    test('should maintain traceId through Express middleware chain', () => {
      const originalTraceId = generateTraceId();
      const tracingMiddleware = expressTracingMiddleware();
      const logger = new TracingLogger({ serviceName: 'test-service' });
      const loggingMiddleware = expressLoggingMiddleware(logger);
      
      const req = {
        headers: { 'x-trace-id': originalTraceId },
        method: 'GET',
        url: '/api/test',
        path: '/api/test',
        get: vi.fn().mockReturnValue('test-agent'),
        ip: '127.0.0.1'
      };
      const res = {
        set: vi.fn(),
        end: vi.fn(),
        statusCode: 200
      };
      const next = vi.fn();

      // Apply tracing middleware
      tracingMiddleware(req, res, next);
      expect(req.traceId).toBe(originalTraceId);
      expect(next).toHaveBeenCalled();

      // Apply logging middleware
      next.mockClear();
      loggingMiddleware(req, res, next);
      expect(next).toHaveBeenCalled();

      // Simulate response
      res.end();

      // Verify traceId was maintained throughout the chain
      expect(req.traceId).toBe(originalTraceId);
    });
  });

  describe('Multi-Service Tracing', () => {
    test('should propagate traceId across HTTP service calls', async () => {
      const originalTraceId = generateTraceId();
      
      // Mock responses for downstream services
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve({ service: 'service-a', traceId: originalTraceId })
        })
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve({ service: 'service-b', traceId: originalTraceId })
        });

      // Service A calls Service B
      const serviceAFetch = createTracingFetch(originalTraceId);
      const serviceBResponse = await serviceAFetch('http://service-b/api/data');
      
      // Verify Service A sent tracing headers to Service B
      expect(mockFetch).toHaveBeenCalledWith(
        'http://service-b/api/data',
        expect.objectContaining({
          headers: expect.objectContaining({
            'X-Trace-Id': originalTraceId
          })
        })
      );

      // Service B calls Service C
      const serviceBFetch = createTracingFetch(originalTraceId);
      const serviceCResponse = await serviceBFetch('http://service-c/api/process');
      
      // Verify Service B sent the same traceId to Service C
      expect(mockFetch).toHaveBeenCalledWith(
        'http://service-c/api/process',
        expect.objectContaining({
          headers: expect.objectContaining({
            'X-Trace-Id': originalTraceId
          })
        })
      );

      // Verify both calls used the same traceId
      const [firstCall, secondCall] = mockFetch.mock.calls;
      expect(firstCall[1].headers['X-Trace-Id']).toBe(originalTraceId);
      expect(secondCall[1].headers['X-Trace-Id']).toBe(originalTraceId);
    });

    test('should maintain traceId across async operations', async () => {
      const originalTraceId = generateTraceId();
      const logger = new TracingLogger({ serviceName: 'async-service' });
      
      // Simulate async operations with traceId
      const asyncOperation1 = async (traceId) => {
        logger.info('Starting async operation 1', { operation: 'database-query' }, traceId);
        await new Promise(resolve => setTimeout(resolve, 10));
        logger.info('Completed async operation 1', { operation: 'database-query' }, traceId);
        return { result: 'data', traceId };
      };

      const asyncOperation2 = async (traceId) => {
        logger.info('Starting async operation 2', { operation: 'cache-update' }, traceId);
        await new Promise(resolve => setTimeout(resolve, 5));
        logger.info('Completed async operation 2', { operation: 'cache-update' }, traceId);
        return { result: 'cached', traceId };
      };

      // Execute async operations
      const [result1, result2] = await Promise.all([
        asyncOperation1(originalTraceId),
        asyncOperation2(originalTraceId)
      ]);

      // Verify both operations maintained the same traceId
      expect(result1.traceId).toBe(originalTraceId);
      expect(result2.traceId).toBe(originalTraceId);

      // Verify all log entries contain the same traceId
      expect(consoleSpy).toHaveBeenCalledTimes(4);
      consoleSpy.mock.calls.forEach(call => {
        const logEntry = JSON.parse(call[0]);
        expect(logEntry.traceId).toBe(originalTraceId);
      });
    });
  });

  describe('Error Propagation with Tracing', () => {
    test('should maintain traceId through error scenarios', async () => {
      const originalTraceId = generateTraceId();
      const logger = new TracingLogger({ serviceName: 'error-service' });
      
      // Mock a failing service call
      mockFetch.mockRejectedValueOnce(new Error('Service unavailable'));

      const tracingFetch = createTracingFetch(originalTraceId);
      
      try {
        await tracingFetch('http://failing-service/api/data');
      } catch (error) {
        // Log error with traceId
        logger.error('Service call failed', { 
          error: error.message,
          service: 'failing-service'
        }, originalTraceId);
      }

      // Verify error was logged with correct traceId
      expect(consoleSpy).toHaveBeenCalled();
      const errorLog = JSON.parse(consoleSpy.mock.calls[0][0]);
      expect(errorLog.traceId).toBe(originalTraceId);
      expect(errorLog.level).toBe('error');
      expect(errorLog.error).toBe('Service unavailable');
    });

    test('should handle missing traceId gracefully', () => {
      const logger = new TracingLogger({ serviceName: 'graceful-service' });
      
      // Log without traceId
      logger.info('Operation without traceId', { operation: 'standalone' });
      
      // Verify log was created without traceId
      expect(consoleSpy).toHaveBeenCalled();
      const logEntry = JSON.parse(consoleSpy.mock.calls[0][0]);
      expect(logEntry.traceId).toBeUndefined();
      expect(logEntry.message).toBe('Operation without traceId');
    });
  });

  describe('Tracing Validation Utilities', () => {
    test('should validate complete trace chain', () => {
      const traceId = generateTraceId();
      const traceChain = [];

      // Simulate service chain: API Gateway -> Service A -> Service B -> Database
      const services = ['api-gateway', 'service-a', 'service-b', 'database'];
      
      services.forEach((serviceName, index) => {
        const logger = new TracingLogger({ serviceName });
        const logEntry = logger.info(`Processing request in ${serviceName}`, {
          step: index + 1,
          totalSteps: services.length
        }, traceId);
        
        traceChain.push(logEntry);
      });

      // Validate all entries have the same traceId
      const traceIds = traceChain.map(entry => entry.traceId);
      const uniqueTraceIds = [...new Set(traceIds)];
      
      expect(uniqueTraceIds).toHaveLength(1);
      expect(uniqueTraceIds[0]).toBe(traceId);
      
      // Validate trace chain completeness
      expect(traceChain).toHaveLength(services.length);
      traceChain.forEach((entry, index) => {
        expect(entry.service).toBe(services[index]);
        expect(entry.step).toBe(index + 1);
      });
    });

    test('should detect trace chain breaks', () => {
      const originalTraceId = generateTraceId();
      const newTraceId = generateTraceId();
      const traceChain = [];

      // Simulate broken trace chain
      const logger1 = new TracingLogger({ serviceName: 'service-1' });
      const logger2 = new TracingLogger({ serviceName: 'service-2' });
      const logger3 = new TracingLogger({ serviceName: 'service-3' });

      traceChain.push(logger1.info('Request received', {}, originalTraceId));
      traceChain.push(logger2.info('Processing request', {}, originalTraceId));
      // Simulate trace break - service-3 generates new traceId
      traceChain.push(logger3.info('Final processing', {}, newTraceId));

      // Validate trace chain has break
      const traceIds = traceChain.map(entry => entry.traceId);
      const uniqueTraceIds = [...new Set(traceIds)];
      
      expect(uniqueTraceIds).toHaveLength(2);
      expect(uniqueTraceIds).toContain(originalTraceId);
      expect(uniqueTraceIds).toContain(newTraceId);
      
      // Identify where the break occurred
      const breakPoint = traceChain.findIndex((entry, index) => {
        if (index === 0) return false;
        return entry.traceId !== traceChain[index - 1].traceId;
      });
      
      expect(breakPoint).toBe(2); // Break at service-3
    });
  });

  describe('Performance Impact', () => {
    test('should have minimal performance impact on request processing', () => {
      const iterations = 1000;
      const traceId = generateTraceId();
      
      // Measure time without tracing
      const startWithoutTracing = Date.now();
      for (let i = 0; i < iterations; i++) {
        const req = { headers: {}, method: 'GET', url: '/test' };
        const res = { set: vi.fn() };
        const next = vi.fn();
        next(); // Simulate no middleware
      }
      const timeWithoutTracing = Date.now() - startWithoutTracing;
      
      // Measure time with tracing
      const tracingMiddleware = expressTracingMiddleware();
      const startWithTracing = Date.now();
      for (let i = 0; i < iterations; i++) {
        const req = { headers: { 'x-trace-id': traceId }, method: 'GET', url: '/test' };
        const res = { set: vi.fn() };
        const next = vi.fn();
        tracingMiddleware(req, res, next);
      }
      const timeWithTracing = Date.now() - startWithTracing;
      
      // Tracing overhead should be minimal (less than 50% increase)
      const overhead = (timeWithTracing - timeWithoutTracing) / timeWithoutTracing;
      expect(overhead).toBeLessThan(0.5);
    });
  });
});
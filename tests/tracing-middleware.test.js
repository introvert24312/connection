/**
 * Tests for tracing middleware
 */

import { describe, test, expect, beforeEach, vi } from 'vitest';

// Mock tracing-utils
vi.mock('../scripts/tracing-utils.js', () => ({
  getOrGenerateTraceId: vi.fn(),
  createTracingHeaders: vi.fn(),
  isValidTraceId: vi.fn(),
  generateTraceId: vi.fn(),
  createGrpcTracingMetadata: vi.fn()
}));

import {
  expressTracingMiddleware,
  wrapHttpClientWithTracing,
  setupAxiosTracingInterceptor,
  createTracingFetch,
  createGrpcTracingInterceptor,
  TracingContext,
  tracingContext
} from '../scripts/tracing-middleware.js';

import * as tracingUtils from '../scripts/tracing-utils.js';

describe('Tracing Middleware', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('expressTracingMiddleware', () => {
    test('should extract traceId and add to request', () => {
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      tracingUtils.getOrGenerateTraceId.mockReturnValue(traceId);
      tracingUtils.isValidTraceId.mockReturnValue(true);
      tracingUtils.createTracingHeaders.mockReturnValue({
        'traceparent': `00-${traceId}-1234567890123456-01`,
        'X-Trace-Id': traceId
      });

      const middleware = expressTracingMiddleware();
      const req = { headers: { 'x-trace-id': traceId } };
      const res = { set: vi.fn() };
      const next = vi.fn();

      middleware(req, res, next);

      expect(req.traceId).toBe(traceId);
      expect(res.set).toHaveBeenCalledWith({
        'traceparent': `00-${traceId}-1234567890123456-01`,
        'X-Trace-Id': traceId
      });
      expect(res.set).toHaveBeenCalledWith('x-trace-id', traceId);
      expect(next).toHaveBeenCalled();
    });

    test('should generate new traceId when invalid', () => {
      const invalidTraceId = 'invalid-trace-id';
      const newTraceId = '123e4567-e89b-12d3-a456-426614174000';
      
      tracingUtils.getOrGenerateTraceId.mockReturnValue(invalidTraceId);
      tracingUtils.isValidTraceId.mockReturnValue(false);
      tracingUtils.generateTraceId.mockReturnValue(newTraceId);
      tracingUtils.createTracingHeaders.mockReturnValue({
        'traceparent': `00-${newTraceId}-1234567890123456-01`,
        'X-Trace-Id': newTraceId
      });

      const middleware = expressTracingMiddleware();
      const req = { headers: {} };
      const res = { set: vi.fn() };
      const next = vi.fn();

      middleware(req, res, next);

      expect(req.traceId).toBe(newTraceId);
      expect(next).toHaveBeenCalled();
    });

    test('should handle errors gracefully', () => {
      tracingUtils.getOrGenerateTraceId.mockImplementation(() => {
        throw new Error('Test error');
      });

      const middleware = expressTracingMiddleware();
      const req = { headers: {} };
      const res = { set: vi.fn() };
      const next = vi.fn();

      expect(() => middleware(req, res, next)).not.toThrow();
      expect(next).toHaveBeenCalled();
    });
  });

  describe('wrapHttpClientWithTracing', () => {
    test('should add tracing headers to HTTP client calls', () => {
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      const mockClient = vi.fn();
      const tracingHeaders = {
        'traceparent': `00-${traceId}-1234567890123456-01`,
        'X-Trace-Id': traceId
      };

      tracingUtils.isValidTraceId.mockReturnValue(true);
      tracingUtils.createTracingHeaders.mockReturnValue(tracingHeaders);

      const wrappedClient = wrapHttpClientWithTracing(mockClient, traceId);
      wrappedClient('http://example.com', { method: 'GET' });

      expect(mockClient).toHaveBeenCalledWith('http://example.com', {
        method: 'GET',
        headers: tracingHeaders
      });
    });

    test('should merge with existing headers', () => {
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      const mockClient = vi.fn();
      const tracingHeaders = { 'X-Trace-Id': traceId };
      const existingHeaders = { 'Content-Type': 'application/json' };

      tracingUtils.isValidTraceId.mockReturnValue(true);
      tracingUtils.createTracingHeaders.mockReturnValue(tracingHeaders);

      const wrappedClient = wrapHttpClientWithTracing(mockClient, traceId);
      wrappedClient('http://example.com', { headers: existingHeaders });

      expect(mockClient).toHaveBeenCalledWith('http://example.com', {
        headers: {
          ...tracingHeaders,
          ...existingHeaders
        }
      });
    });

    test('should handle invalid traceId', () => {
      const invalidTraceId = 'invalid';
      const mockClient = vi.fn();

      tracingUtils.isValidTraceId.mockReturnValue(false);

      const wrappedClient = wrapHttpClientWithTracing(mockClient, invalidTraceId);
      wrappedClient('http://example.com');

      expect(mockClient).toHaveBeenCalledWith('http://example.com', {});
    });
  });

  describe('setupAxiosTracingInterceptor', () => {
    test('should add request interceptor to axios instance', () => {
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      const mockAxios = {
        interceptors: {
          request: {
            use: vi.fn()
          }
        }
      };
      const getTraceId = vi.fn().mockReturnValue(traceId);
      const tracingHeaders = { 'X-Trace-Id': traceId };

      tracingUtils.isValidTraceId.mockReturnValue(true);
      tracingUtils.createTracingHeaders.mockReturnValue(tracingHeaders);

      setupAxiosTracingInterceptor(mockAxios, getTraceId);

      expect(mockAxios.interceptors.request.use).toHaveBeenCalled();

      // Test the interceptor function
      const [interceptor] = mockAxios.interceptors.request.use.mock.calls[0];
      const config = { headers: {} };
      const result = interceptor(config);

      expect(result.headers).toEqual(tracingHeaders);
    });
  });

  describe('createTracingFetch', () => {
    test('should create fetch wrapper with tracing headers', () => {
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      const tracingHeaders = { 'X-Trace-Id': traceId };

      tracingUtils.isValidTraceId.mockReturnValue(true);
      tracingUtils.createTracingHeaders.mockReturnValue(tracingHeaders);

      // Mock global fetch
      global.fetch = vi.fn();

      const tracingFetch = createTracingFetch(traceId);
      tracingFetch('http://example.com', { method: 'GET' });

      expect(global.fetch).toHaveBeenCalledWith('http://example.com', {
        method: 'GET',
        headers: tracingHeaders
      });
    });
  });

  describe('createGrpcTracingInterceptor', () => {
    test('should create gRPC interceptor with tracing metadata', () => {
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      const tracingMetadata = { 'x-trace-id': traceId };

      tracingUtils.isValidTraceId.mockReturnValue(true);
      tracingUtils.createGrpcTracingMetadata.mockReturnValue(tracingMetadata);

      const interceptor = createGrpcTracingInterceptor(traceId);
      const options = { metadata: {} };
      const nextCall = vi.fn();

      interceptor(options, nextCall);

      expect(options.metadata).toEqual(tracingMetadata);
      expect(nextCall).toHaveBeenCalledWith(options);
    });
  });

  describe('TracingContext', () => {
    test('should store and retrieve traceId', () => {
      const context = new TracingContext();
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      const contextId = 'test-context';

      tracingUtils.isValidTraceId.mockReturnValue(true);

      context.setTraceId(contextId, traceId);
      expect(context.getTraceId(contextId)).toBe(traceId);
    });

    test('should clear traceId from context', () => {
      const context = new TracingContext();
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      const contextId = 'test-context';

      tracingUtils.isValidTraceId.mockReturnValue(true);

      context.setTraceId(contextId, traceId);
      context.clearTraceId(contextId);
      expect(context.getTraceId(contextId)).toBeNull();
    });

    test('should not store invalid traceId', () => {
      const context = new TracingContext();
      const invalidTraceId = 'invalid';
      const contextId = 'test-context';

      tracingUtils.isValidTraceId.mockReturnValue(false);

      context.setTraceId(contextId, invalidTraceId);
      expect(context.getTraceId(contextId)).toBeNull();
    });
  });
});
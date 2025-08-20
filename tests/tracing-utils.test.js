/**
 * Tests for tracing utilities
 */

import { describe, test, expect, vi } from 'vitest';
import {
  generateTraceId,
  extractTraceIdFromHeaders,
  createTracingHeaders,
  extractTraceIdFromGrpcMetadata,
  createGrpcTracingMetadata,
  getOrGenerateTraceId,
  isValidTraceId
} from '../scripts/tracing-utils.js';

describe('Tracing Utils', () => {
  describe('generateTraceId', () => {
    test('should generate valid UUID traceId', () => {
      const traceId = generateTraceId();
      expect(traceId).toBeDefined();
      expect(typeof traceId).toBe('string');
      expect(isValidTraceId(traceId)).toBe(true);
    });

    test('should generate unique traceIds', () => {
      const traceId1 = generateTraceId();
      const traceId2 = generateTraceId();
      expect(traceId1).not.toBe(traceId2);
    });
  });

  describe('isValidTraceId', () => {
    test('should validate correct UUID format', () => {
      const validTraceId = '123e4567-e89b-12d3-a456-426614174000';
      expect(isValidTraceId(validTraceId)).toBe(true);
    });

    test('should reject invalid formats', () => {
      expect(isValidTraceId('invalid-uuid')).toBe(false);
      expect(isValidTraceId('')).toBe(false);
      expect(isValidTraceId(null)).toBe(false);
      expect(isValidTraceId(undefined)).toBe(false);
      expect(isValidTraceId(123)).toBe(false);
    });
  });

  describe('extractTraceIdFromHeaders', () => {
    test('should extract traceId from traceparent header', () => {
      const traceId = '123e4567e89b12d3a456426614174000';
      const headers = {
        traceparent: `00-${traceId}-1234567890123456-01`
      };
      
      expect(extractTraceIdFromHeaders(headers)).toBe(traceId);
    });

    test('should extract traceId from X-Trace-Id header', () => {
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      const headers = {
        'x-trace-id': traceId
      };
      
      expect(extractTraceIdFromHeaders(headers)).toBe(traceId);
    });

    test('should prioritize traceparent over X-Trace-Id', () => {
      const traceId1 = '123e4567e89b12d3a456426614174000';
      const traceId2 = '987e6543-e21b-34d5-a678-426614174999';
      const headers = {
        traceparent: `00-${traceId1}-1234567890123456-01`,
        'x-trace-id': traceId2
      };
      
      expect(extractTraceIdFromHeaders(headers)).toBe(traceId1);
    });

    test('should return null when no tracing headers present', () => {
      const headers = {
        'content-type': 'application/json'
      };
      
      expect(extractTraceIdFromHeaders(headers)).toBeNull();
    });

    test('should handle malformed traceparent header', () => {
      const headers = {
        traceparent: 'invalid-format'
      };
      
      expect(extractTraceIdFromHeaders(headers)).toBeNull();
    });
  });

  describe('createTracingHeaders', () => {
    test('should create valid tracing headers', () => {
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      const headers = createTracingHeaders(traceId);
      
      expect(headers).toHaveProperty('traceparent');
      expect(headers).toHaveProperty('X-Trace-Id');
      expect(headers['X-Trace-Id']).toBe(traceId);
      
      // Validate traceparent format
      const traceparent = headers.traceparent;
      expect(traceparent).toMatch(/^00-[0-9a-f-]+-[0-9a-f]+-01$/);
      expect(traceparent).toContain(traceId);
    });
  });

  describe('extractTraceIdFromGrpcMetadata', () => {
    test('should extract traceId from gRPC metadata', () => {
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      const metadata = {
        get: vi.fn().mockReturnValue([traceId])
      };
      
      expect(extractTraceIdFromGrpcMetadata(metadata)).toBe(traceId);
      expect(metadata.get).toHaveBeenCalledWith('x-trace-id');
    });

    test('should return null when metadata is empty', () => {
      const metadata = {
        get: vi.fn().mockReturnValue([])
      };
      
      expect(extractTraceIdFromGrpcMetadata(metadata)).toBeNull();
    });

    test('should return null when metadata is invalid', () => {
      expect(extractTraceIdFromGrpcMetadata(null)).toBeNull();
      expect(extractTraceIdFromGrpcMetadata({})).toBeNull();
    });
  });

  describe('createGrpcTracingMetadata', () => {
    test('should create gRPC metadata with traceId', () => {
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      const metadata = createGrpcTracingMetadata(traceId);
      
      expect(metadata).toEqual({
        'x-trace-id': traceId
      });
    });
  });

  describe('getOrGenerateTraceId', () => {
    test('should return existing traceId from HTTP headers', () => {
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      const headers = {
        'x-trace-id': traceId
      };
      
      expect(getOrGenerateTraceId(headers, 'http')).toBe(traceId);
    });

    test('should generate new traceId when none exists', () => {
      const headers = {};
      const result = getOrGenerateTraceId(headers, 'http');
      
      expect(result).toBeDefined();
      expect(isValidTraceId(result)).toBe(true);
    });

    test('should handle gRPC metadata', () => {
      const traceId = '123e4567-e89b-12d3-a456-426614174000';
      const metadata = {
        get: vi.fn().mockReturnValue([traceId])
      };
      
      expect(getOrGenerateTraceId(metadata, 'grpc')).toBe(traceId);
    });
  });
});
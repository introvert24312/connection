/**
 * Distributed Tracing Utilities
 * 
 * Provides traceId generation and propagation utilities for distributed tracing
 * across HTTP and gRPC services following W3C Trace Context specification.
 */

import crypto from 'crypto';

/**
 * Generate a new UUID-based traceId
 * @returns {string} A new UUID traceId
 */
function generateTraceId() {
  return crypto.randomUUID();
}

/**
 * Extract traceId from HTTP headers
 * Supports both W3C traceparent and custom X-Trace-Id headers
 * @param {Object} headers - HTTP headers object
 * @returns {string|null} Extracted traceId or null if not found
 */
function extractTraceIdFromHeaders(headers) {
  // Try W3C traceparent header first (format: 00-{traceId}-{spanId}-{flags})
  if (headers.traceparent) {
    const parts = headers.traceparent.split('-');
    if (parts.length >= 4 && parts[0] === '00') {
      return parts[1];
    }
  }
  
  // Fallback to custom X-Trace-Id header
  if (headers['x-trace-id']) {
    return headers['x-trace-id'];
  }
  
  // Check lowercase variants
  if (headers['X-Trace-Id']) {
    return headers['X-Trace-Id'];
  }
  
  return null;
}

/**
 * Create HTTP headers for traceId propagation
 * @param {string} traceId - The traceId to propagate
 * @returns {Object} Headers object with tracing headers
 */
function createTracingHeaders(traceId) {
  const spanId = crypto.randomBytes(8).toString('hex');
  const flags = '01'; // Sampled
  
  return {
    'traceparent': `00-${traceId}-${spanId}-${flags}`,
    'X-Trace-Id': traceId
  };
}

/**
 * Extract traceId from gRPC metadata
 * @param {Object} metadata - gRPC metadata object
 * @returns {string|null} Extracted traceId or null if not found
 */
function extractTraceIdFromGrpcMetadata(metadata) {
  if (metadata && metadata.get) {
    const traceIds = metadata.get('x-trace-id');
    if (traceIds && traceIds.length > 0) {
      return traceIds[0];
    }
  }
  
  return null;
}

/**
 * Create gRPC metadata for traceId propagation
 * @param {string} traceId - The traceId to propagate
 * @returns {Object} Metadata object with tracing information
 */
function createGrpcTracingMetadata(traceId) {
  return {
    'x-trace-id': traceId
  };
}

/**
 * Get or generate traceId from request context
 * @param {Object} headers - HTTP headers or gRPC metadata
 * @param {string} type - 'http' or 'grpc'
 * @returns {string} Existing or newly generated traceId
 */
function getOrGenerateTraceId(headers, type = 'http') {
  let traceId;
  
  if (type === 'grpc') {
    traceId = extractTraceIdFromGrpcMetadata(headers);
  } else {
    traceId = extractTraceIdFromHeaders(headers);
  }
  
  return traceId || generateTraceId();
}

/**
 * Validate traceId format (UUID)
 * @param {string} traceId - The traceId to validate
 * @returns {boolean} True if valid UUID format
 */
function isValidTraceId(traceId) {
  if (!traceId || typeof traceId !== 'string') {
    return false;
  }
  
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuidRegex.test(traceId);
}

export {
  generateTraceId,
  extractTraceIdFromHeaders,
  createTracingHeaders,
  extractTraceIdFromGrpcMetadata,
  createGrpcTracingMetadata,
  getOrGenerateTraceId,
  isValidTraceId
};
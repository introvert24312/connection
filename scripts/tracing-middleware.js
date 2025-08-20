/**
 * Tracing Middleware
 * 
 * Express.js and generic HTTP middleware for automatic traceId extraction,
 * generation, and propagation in distributed systems.
 */

import { getOrGenerateTraceId, createTracingHeaders, isValidTraceId, generateTraceId, createGrpcTracingMetadata } from './tracing-utils.js';

/**
 * Express.js middleware for traceId handling
 * Extracts or generates traceId and adds it to request context
 * @param {Object} options - Middleware configuration options
 * @param {string} options.headerName - Custom header name for traceId (default: 'x-trace-id')
 * @param {boolean} options.generateIfMissing - Generate traceId if not present (default: true)
 * @returns {Function} Express middleware function
 */
function expressTracingMiddleware(options = {}) {
  const {
    headerName = 'x-trace-id',
    generateIfMissing = true
  } = options;

  return (req, res, next) => {
    try {
      // Extract or generate traceId
      let traceId = getOrGenerateTraceId(req.headers, 'http');
      
      // Validate traceId format
      if (!isValidTraceId(traceId)) {
        if (generateIfMissing) {
          traceId = generateTraceId();
          console.warn(`Invalid traceId format detected, generated new traceId: ${traceId}`);
        } else {
          console.warn('Invalid traceId format detected and generation disabled');
          traceId = null;
        }
      }
      
      // Add traceId to request context
      req.traceId = traceId;
      
      // Add traceId to response headers for downstream services
      if (traceId) {
        const tracingHeaders = createTracingHeaders(traceId);
        res.set(tracingHeaders);
        res.set(headerName, traceId);
      }
      
      next();
    } catch (error) {
      console.error('Error in tracing middleware:', error);
      // Don't block request processing on tracing errors
      next();
    }
  };
}

/**
 * Generic HTTP client wrapper that adds tracing headers
 * @param {Function} httpClient - HTTP client function (e.g., fetch, axios)
 * @param {string} traceId - TraceId to propagate
 * @returns {Function} Wrapped HTTP client with tracing headers
 */
function wrapHttpClientWithTracing(httpClient, traceId) {
  return function(url, options = {}) {
    if (!traceId || !isValidTraceId(traceId)) {
      console.warn('Invalid or missing traceId for HTTP client call');
      return httpClient(url, options);
    }
    
    const tracingHeaders = createTracingHeaders(traceId);
    
    // Merge tracing headers with existing headers
    const headers = {
      ...tracingHeaders,
      ...(options.headers || {})
    };
    
    const enhancedOptions = {
      ...options,
      headers
    };
    
    return httpClient(url, enhancedOptions);
  };
}

/**
 * Axios interceptor for automatic traceId propagation
 * @param {Object} axiosInstance - Axios instance to enhance
 * @param {Function} getTraceId - Function to get current traceId from context
 */
function setupAxiosTracingInterceptor(axiosInstance, getTraceId) {
  axiosInstance.interceptors.request.use(
    (config) => {
      try {
        const traceId = getTraceId();
        if (traceId && isValidTraceId(traceId)) {
          const tracingHeaders = createTracingHeaders(traceId);
          config.headers = {
            ...tracingHeaders,
            ...config.headers
          };
        }
      } catch (error) {
        console.warn('Error adding tracing headers to axios request:', error);
      }
      return config;
    },
    (error) => {
      return Promise.reject(error);
    }
  );
}

/**
 * Fetch wrapper with automatic tracing header injection
 * @param {string} traceId - Current traceId
 * @returns {Function} Enhanced fetch function
 */
function createTracingFetch(traceId) {
  return function(url, options = {}) {
    if (!traceId || !isValidTraceId(traceId)) {
      console.warn('Invalid or missing traceId for fetch call');
      return fetch(url, options);
    }
    
    const tracingHeaders = createTracingHeaders(traceId);
    
    const enhancedOptions = {
      ...options,
      headers: {
        ...tracingHeaders,
        ...(options.headers || {})
      }
    };
    
    return fetch(url, enhancedOptions);
  };
}

/**
 * gRPC client interceptor for traceId propagation
 * @param {string} traceId - Current traceId
 * @returns {Function} gRPC interceptor function
 */
function createGrpcTracingInterceptor(traceId) {
  return function(options, nextCall) {
    if (traceId && isValidTraceId(traceId)) {
      const tracingMetadata = createGrpcTracingMetadata(traceId);
      
      // Add tracing metadata to the call
      if (!options.metadata) {
        options.metadata = {};
      }
      
      Object.assign(options.metadata, tracingMetadata);
    }
    
    return nextCall(options);
  };
}

/**
 * Generic request context manager for tracing
 * Provides a simple way to store and retrieve traceId in async contexts
 */
class TracingContext {
  constructor() {
    this.contexts = new Map();
  }
  
  /**
   * Set traceId for current async context
   * @param {string} contextId - Unique context identifier
   * @param {string} traceId - TraceId to store
   */
  setTraceId(contextId, traceId) {
    if (isValidTraceId(traceId)) {
      this.contexts.set(contextId, traceId);
    }
  }
  
  /**
   * Get traceId from current async context
   * @param {string} contextId - Unique context identifier
   * @returns {string|null} Stored traceId or null
   */
  getTraceId(contextId) {
    return this.contexts.get(contextId) || null;
  }
  
  /**
   * Clear traceId from context
   * @param {string} contextId - Unique context identifier
   */
  clearTraceId(contextId) {
    this.contexts.delete(contextId);
  }
}

// Export singleton instance
const tracingContext = new TracingContext();

export {
  expressTracingMiddleware,
  wrapHttpClientWithTracing,
  setupAxiosTracingInterceptor,
  createTracingFetch,
  createGrpcTracingInterceptor,
  TracingContext,
  tracingContext
};
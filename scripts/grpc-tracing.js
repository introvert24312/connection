/**
 * gRPC Tracing Utilities
 * Handles traceId propagation for gRPC services
 */

import { generateTraceId, extractTraceIdFromGrpcMetadata, createGrpcTracingMetadata } from './tracing-utils.js';

/**
 * gRPC server interceptor for traceId handling
 * Extracts traceId from metadata or generates new one
 * @param {Object} call - gRPC call object
 * @param {Function} callback - Callback function
 * @param {Function} next - Next interceptor
 */
function grpcTracingServerInterceptor(call, callback, next) {
  // Extract traceId from incoming metadata
  let traceId = extractTraceIdFromGrpcMetadata(call.metadata);
  
  // Generate new traceId if none exists (entry point)
  if (!traceId) {
    traceId = generateTraceId();
  }
  
  // Add traceId to call context
  call.traceId = traceId;
  
  // Add traceId to response metadata
  if (call.sendMetadata) {
    const responseMetadata = createGrpcTracingMetadata(traceId);
    call.sendMetadata(responseMetadata);
  }
  
  next();
}

/**
 * gRPC client interceptor for traceId propagation
 * Adds traceId to outgoing call metadata
 * @param {string} traceId - Current traceId
 * @returns {Function} gRPC client interceptor
 */
function grpcTracingClientInterceptor(traceId) {
  return (options, nextCall) => {
    // Add tracing metadata to outgoing call
    const tracingMetadata = createGrpcTracingMetadata(traceId);
    
    if (options.metadata) {
      // Add to existing metadata
      Object.keys(tracingMetadata).forEach(key => {
        options.metadata.add(key, tracingMetadata[key]);
      });
    } else {
      // Create new metadata
      const grpc = await import('@grpc/grpc-js');
      options.metadata = new grpc.Metadata();
      Object.keys(tracingMetadata).forEach(key => {
        options.metadata.add(key, tracingMetadata[key]);
      });
    }
    
    return nextCall(options);
  };
}

/**
 * Wrap gRPC client with automatic tracing
 * @param {Object} grpcClient - gRPC client instance
 * @param {string} traceId - Current traceId
 * @returns {Object} Wrapped gRPC client with tracing
 */
async function wrapGrpcClientWithTracing(grpcClient, traceId) {
  const grpc = await import('@grpc/grpc-js');
  const tracingMetadata = new grpc.Metadata();
  
  Object.keys(createGrpcTracingMetadata(traceId)).forEach(key => {
    tracingMetadata.add(key, createGrpcTracingMetadata(traceId)[key]);
  });
  
  // Create a proxy that adds tracing metadata to all method calls
  return new Proxy(grpcClient, {
    get(target, prop) {
      const originalMethod = target[prop];
      
      if (typeof originalMethod === 'function') {
        return function(...args) {
          // Add tracing metadata to the call
          const lastArg = args[args.length - 1];
          
          if (lastArg && typeof lastArg === 'object' && lastArg.metadata) {
            // Merge with existing metadata
            Object.keys(createGrpcTracingMetadata(traceId)).forEach(key => {
              lastArg.metadata.add(key, createGrpcTracingMetadata(traceId)[key]);
            });
          } else {
            // Add metadata as last argument
            args.push({ metadata: tracingMetadata });
          }
          
          return originalMethod.apply(target, args);
        };
      }
      
      return originalMethod;
    }
  });
}

export {
  grpcTracingServerInterceptor,
  grpcTracingClientInterceptor,
  wrapGrpcClientWithTracing
};
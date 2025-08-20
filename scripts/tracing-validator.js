/**
 * Tracing Validation Utilities
 * 
 * Tools for validating traceId propagation and analyzing trace chains
 * in distributed systems.
 */

import { isValidTraceId } from './tracing-utils.js';

/**
 * Trace validation result structure
 */
class TraceValidationResult {
  constructor() {
    this.isValid = true;
    this.errors = [];
    this.warnings = [];
    this.statistics = {
      totalEntries: 0,
      uniqueTraceIds: 0,
      services: new Set(),
      timespan: 0
    };
  }

  addError(message, context = {}) {
    this.isValid = false;
    this.errors.push({ message, context, timestamp: new Date().toISOString() });
  }

  addWarning(message, context = {}) {
    this.warnings.push({ message, context, timestamp: new Date().toISOString() });
  }

  updateStatistics(entries) {
    this.statistics.totalEntries = entries.length;
    
    const traceIds = entries.map(e => e.traceId).filter(Boolean);
    this.statistics.uniqueTraceIds = new Set(traceIds).size;
    
    entries.forEach(entry => {
      if (entry.service) {
        this.statistics.services.add(entry.service);
      }
    });

    if (entries.length > 1) {
      const timestamps = entries
        .map(e => new Date(e.timestamp))
        .sort((a, b) => a - b);
      
      this.statistics.timespan = timestamps[timestamps.length - 1] - timestamps[0];
    }
  }
}

/**
 * Validate a single trace entry
 * @param {Object} entry - Log entry to validate
 * @param {Object} options - Validation options
 * @returns {Array} Array of validation issues
 */
function validateTraceEntry(entry, options = {}) {
  const issues = [];
  const requiredFields = options.requiredFields || ['timestamp', 'level', 'message'];

  // Check required fields
  requiredFields.forEach(field => {
    if (!entry[field]) {
      issues.push({
        type: 'error',
        message: `Missing required field: ${field}`,
        field
      });
    }
  });

  // Validate traceId format if present
  if (entry.traceId && !isValidTraceId(entry.traceId)) {
    issues.push({
      type: 'error',
      message: 'Invalid traceId format',
      traceId: entry.traceId
    });
  }

  // Validate timestamp format
  if (entry.timestamp && isNaN(new Date(entry.timestamp).getTime())) {
    issues.push({
      type: 'error',
      message: 'Invalid timestamp format',
      timestamp: entry.timestamp
    });
  }

  // Check for suspicious patterns
  if (entry.message && entry.message.length > 1000) {
    issues.push({
      type: 'warning',
      message: 'Unusually long log message',
      messageLength: entry.message.length
    });
  }

  return issues;
}

/**
 * Validate trace chain continuity
 * @param {Array} entries - Array of log entries
 * @param {Object} options - Validation options
 * @returns {TraceValidationResult} Validation result
 */
function validateTraceChain(entries, options = {}) {
  const result = new TraceValidationResult();
  const {
    expectSingleTraceId = true,
    maxTimespanMs = 300000, // 5 minutes
    requiredServices = [],
    allowMissingTraceId = false
  } = options;

  if (!Array.isArray(entries) || entries.length === 0) {
    result.addError('No entries provided for validation');
    return result;
  }

  // Update statistics
  result.updateStatistics(entries);

  // Validate individual entries
  entries.forEach((entry, index) => {
    const entryIssues = validateTraceEntry(entry, options);
    entryIssues.forEach(issue => {
      if (issue.type === 'error') {
        result.addError(`Entry ${index}: ${issue.message}`, { index, entry: entry });
      } else {
        result.addWarning(`Entry ${index}: ${issue.message}`, { index, entry: entry });
      }
    });
  });

  // Check for missing traceIds
  const entriesWithTraceId = entries.filter(e => e.traceId);
  const entriesWithoutTraceId = entries.filter(e => !e.traceId);

  if (entriesWithoutTraceId.length > 0 && !allowMissingTraceId) {
    result.addError(
      `${entriesWithoutTraceId.length} entries missing traceId`,
      { entriesWithoutTraceId: entriesWithoutTraceId.length }
    );
  }

  // Validate single traceId expectation
  if (expectSingleTraceId && result.statistics.uniqueTraceIds > 1) {
    const traceIds = [...new Set(entriesWithTraceId.map(e => e.traceId))];
    result.addError(
      'Multiple traceIds found in chain',
      { traceIds, count: traceIds.length }
    );
  }

  // Check timespan
  if (result.statistics.timespan > maxTimespanMs) {
    result.addWarning(
      'Trace chain spans longer than expected',
      { 
        timespanMs: result.statistics.timespan,
        maxTimespanMs,
        timespanMinutes: Math.round(result.statistics.timespan / 60000)
      }
    );
  }

  // Validate required services
  requiredServices.forEach(service => {
    if (!result.statistics.services.has(service)) {
      result.addError(
        `Required service not found in trace chain: ${service}`,
        { requiredService: service }
      );
    }
  });

  // Check for logical ordering issues
  const sortedEntries = [...entries].sort((a, b) => 
    new Date(a.timestamp) - new Date(b.timestamp)
  );

  if (JSON.stringify(entries) !== JSON.stringify(sortedEntries)) {
    result.addWarning(
      'Entries are not in chronological order',
      { originalOrder: entries.map(e => e.timestamp) }
    );
  }

  return result;
}

/**
 * Analyze trace performance metrics
 * @param {Array} entries - Array of log entries
 * @returns {Object} Performance analysis
 */
function analyzeTracePerformance(entries) {
  if (!entries || entries.length === 0) {
    return { error: 'No entries provided' };
  }

  const timestamps = entries
    .map(e => new Date(e.timestamp))
    .sort((a, b) => a - b);

  const services = entries.reduce((acc, entry) => {
    if (entry.service) {
      if (!acc[entry.service]) {
        acc[entry.service] = [];
      }
      acc[entry.service].push(new Date(entry.timestamp));
    }
    return acc;
  }, {});

  const analysis = {
    totalDuration: timestamps[timestamps.length - 1] - timestamps[0],
    entryCount: entries.length,
    serviceCount: Object.keys(services).length,
    services: {},
    timeline: []
  };

  // Analyze per-service metrics
  Object.entries(services).forEach(([serviceName, serviceTimestamps]) => {
    const sortedTimestamps = serviceTimestamps.sort((a, b) => a - b);
    analysis.services[serviceName] = {
      entryCount: serviceTimestamps.length,
      firstSeen: sortedTimestamps[0],
      lastSeen: sortedTimestamps[sortedTimestamps.length - 1],
      duration: sortedTimestamps[sortedTimestamps.length - 1] - sortedTimestamps[0]
    };
  });

  // Create timeline
  entries.forEach(entry => {
    analysis.timeline.push({
      timestamp: entry.timestamp,
      service: entry.service,
      message: entry.message,
      level: entry.level,
      relativeTime: new Date(entry.timestamp) - timestamps[0]
    });
  });

  analysis.timeline.sort((a, b) => a.relativeTime - b.relativeTime);

  return analysis;
}

/**
 * Generate trace chain report
 * @param {Array} entries - Array of log entries
 * @param {Object} options - Report options
 * @returns {Object} Comprehensive trace report
 */
function generateTraceReport(entries, options = {}) {
  const validation = validateTraceChain(entries, options);
  const performance = analyzeTracePerformance(entries);

  const report = {
    summary: {
      isValid: validation.isValid,
      totalEntries: validation.statistics.totalEntries,
      uniqueTraceIds: validation.statistics.uniqueTraceIds,
      services: Array.from(validation.statistics.services),
      duration: validation.statistics.timespan,
      errorCount: validation.errors.length,
      warningCount: validation.warnings.length
    },
    validation: {
      errors: validation.errors,
      warnings: validation.warnings
    },
    performance,
    recommendations: []
  };

  // Generate recommendations
  if (validation.errors.length > 0) {
    report.recommendations.push('Fix validation errors to ensure proper tracing');
  }

  if (validation.statistics.uniqueTraceIds > 1) {
    report.recommendations.push('Investigate trace chain breaks - multiple traceIds detected');
  }

  if (performance.totalDuration > 30000) {
    report.recommendations.push('Consider optimizing request processing - high total duration detected');
  }

  if (validation.statistics.services.size < 2) {
    report.recommendations.push('Verify distributed tracing setup - only single service detected');
  }

  return report;
}

/**
 * Mock trace generator for testing
 * @param {Object} options - Generation options
 * @returns {Array} Array of mock trace entries
 */
function generateMockTrace(options = {}) {
  const {
    traceId = 'test-trace-' + Date.now(),
    services = ['api-gateway', 'user-service', 'database'],
    entryCount = 10,
    timeSpanMs = 5000,
    includeErrors = false
  } = options;

  const entries = [];
  const startTime = new Date();

  services.forEach((service, serviceIndex) => {
    const serviceEntries = Math.ceil(entryCount / services.length);
    
    for (let i = 0; i < serviceEntries; i++) {
      const timestamp = new Date(
        startTime.getTime() + 
        (serviceIndex * timeSpanMs / services.length) + 
        (i * (timeSpanMs / services.length) / serviceEntries)
      );

      const level = includeErrors && Math.random() < 0.1 ? 'error' : 'info';
      const message = level === 'error' 
        ? `Error in ${service}: Operation failed`
        : `Processing request in ${service}`;

      entries.push({
        timestamp: timestamp.toISOString(),
        level,
        service,
        message,
        traceId,
        step: serviceIndex * serviceEntries + i + 1
      });
    }
  });

  return entries.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
}

export {
  TraceValidationResult,
  validateTraceEntry,
  validateTraceChain,
  analyzeTracePerformance,
  generateTraceReport,
  generateMockTrace
};
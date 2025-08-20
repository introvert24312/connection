#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

class GovernanceMonitor {
  constructor(docsPath = 'docs') {
    this.docsPath = docsPath;
    this.metrics = {
      coverage: {},
      health: {},
      compliance: {},
      alerts: []
    };
  }

  /**
   * Calculate documentation coverage metrics
   */
  calculateCoverageMetrics() {
    console.log('📊 Calculating documentation coverage metrics...\n');
    
    const coverage = {
      services: this.calculateServiceCoverage(),
      contracts: this.calculateContractCoverage(),
      dependencies: this.calculateDependencyCoverage(),
      runbooks: this.calculateRunbookCoverage(),
      architecture: this.calculateArchitectureCoverage(),
      featureFlags: this.calculateFeatureFlagCoverage()
    };
    
    this.metrics.coverage = coverage;
    
    // Calculate overall coverage score
    const totalComponents = Object.keys(coverage).length;
    const completedComponents = Object.values(coverage).filter(c => c.percentage >= 80).length;
    const overallCoverage = (completedComponents / totalComponents) * 100;
    
    console.log('📈 Coverage Summary:');
    console.log(`   Overall Coverage: ${overallCoverage.toFixed(1)}%`);
    console.log(`   Components with >80% coverage: ${completedComponents}/${totalComponents}`);
    console.log('');
    
    Object.entries(coverage).forEach(([component, data]) => {
      const status = data.percentage >= 80 ? '✅' : data.percentage >= 60 ? '⚠️' : '❌';
      console.log(`   ${status} ${component}: ${data.percentage.toFixed(1)}% (${data.covered}/${data.total})`);
      
      if (data.missing && data.missing.length > 0) {
        console.log(`      Missing: ${data.missing.slice(0, 3).join(', ')}${data.missing.length > 3 ? '...' : ''}`);
      }
    });
    
    return coverage;
  }

  calculateServiceCoverage() {
    const servicesDir = path.join(this.docsPath, 'services');
    
    if (!fs.existsSync(servicesDir)) {
      return { total: 0, covered: 0, percentage: 0, missing: [] };
    }
    
    const serviceFiles = fs.readdirSync(servicesDir)
      .filter(file => file.endsWith('.yaml') || file.endsWith('.yml'));
    
    let validServices = 0;
    const missingFields = [];
    
    for (const file of serviceFiles) {
      try {
        const content = fs.readFileSync(path.join(servicesDir, file), 'utf8');
        const service = yaml.load(content);
        
        const requiredFields = ['name', 'purpose', 'owner', 'health', 'runbook'];
        const missingInService = requiredFields.filter(field => !service[field]);
        
        if (missingInService.length === 0) {
          validServices++;
        } else {
          missingFields.push(`${file}: ${missingInService.join(', ')}`);
        }
      } catch (error) {
        missingFields.push(`${file}: parsing error`);
      }
    }
    
    return {
      total: serviceFiles.length,
      covered: validServices,
      percentage: serviceFiles.length > 0 ? (validServices / serviceFiles.length) * 100 : 0,
      missing: missingFields
    };
  }

  calculateContractCoverage() {
    const httpDir = path.join(this.docsPath, 'contracts/http');
    const eventsDir = path.join(this.docsPath, 'contracts/events');
    
    let totalContracts = 0;
    let validContracts = 0;
    const missingContracts = [];
    
    // Check HTTP contracts
    if (fs.existsSync(httpDir)) {
      const httpFiles = fs.readdirSync(httpDir)
        .filter(file => file.endsWith('.openapi.yaml') || file.endsWith('.openapi.yml'));
      
      totalContracts += httpFiles.length;
      
      for (const file of httpFiles) {
        try {
          const content = fs.readFileSync(path.join(httpDir, file), 'utf8');
          const contract = yaml.load(content);
          
          if (contract.openapi && contract.info && contract.paths) {
            const pathCount = Object.keys(contract.paths).length;
            if (pathCount >= 3) { // Requirement: at least 3 critical endpoints
              validContracts++;
            } else {
              missingContracts.push(`${file}: only ${pathCount} endpoints (need 3+)`);
            }
          } else {
            missingContracts.push(`${file}: missing required fields`);
          }
        } catch (error) {
          missingContracts.push(`${file}: parsing error`);
        }
      }
    }
    
    // Check Event contracts
    if (fs.existsSync(eventsDir)) {
      const eventFiles = fs.readdirSync(eventsDir)
        .filter(file => file.endsWith('.asyncapi.yaml') || file.endsWith('.asyncapi.yml'));
      
      totalContracts += eventFiles.length;
      
      for (const file of eventFiles) {
        try {
          const content = fs.readFileSync(path.join(eventsDir, file), 'utf8');
          const contract = yaml.load(content);
          
          if (contract.asyncapi && contract.info && contract.channels) {
            const channelCount = Object.keys(contract.channels).length;
            if (channelCount >= 1) { // Requirement: at least 1 main topic
              validContracts++;
            } else {
              missingContracts.push(`${file}: no channels defined`);
            }
          } else {
            missingContracts.push(`${file}: missing required fields`);
          }
        } catch (error) {
          missingContracts.push(`${file}: parsing error`);
        }
      }
    }
    
    return {
      total: totalContracts,
      covered: validContracts,
      percentage: totalContracts > 0 ? (validContracts / totalContracts) * 100 : 0,
      missing: missingContracts
    };
  }

  calculateDependencyCoverage() {
    const dependenciesDir = path.join(this.docsPath, 'dependencies');
    
    if (!fs.existsSync(dependenciesDir)) {
      return { total: 0, covered: 0, percentage: 100, missing: [] }; // Optional component
    }
    
    const depFiles = fs.readdirSync(dependenciesDir)
      .filter(file => file.endsWith('.yaml') || file.endsWith('.yml'));
    
    let validDependencies = 0;
    const missingFields = [];
    
    for (const file of depFiles) {
      try {
        const content = fs.readFileSync(path.join(dependenciesDir, file), 'utf8');
        const dependency = yaml.load(content);
        
        if (dependency.from && dependency.to && dependency.contract) {
          validDependencies++;
        } else {
          missingFields.push(`${file}: missing required fields`);
        }
      } catch (error) {
        missingFields.push(`${file}: parsing error`);
      }
    }
    
    return {
      total: depFiles.length,
      covered: validDependencies,
      percentage: depFiles.length > 0 ? (validDependencies / depFiles.length) * 100 : 100,
      missing: missingFields
    };
  }

  calculateRunbookCoverage() {
    const runbooksDir = path.join(this.docsPath, 'runbooks');
    const servicesDir = path.join(this.docsPath, 'services');
    
    if (!fs.existsSync(servicesDir)) {
      return { total: 0, covered: 0, percentage: 0, missing: [] };
    }
    
    const serviceFiles = fs.readdirSync(servicesDir)
      .filter(file => file.endsWith('.yaml') || file.endsWith('.yml'));
    
    let runbooksFound = 0;
    const missingRunbooks = [];
    
    for (const file of serviceFiles) {
      try {
        const content = fs.readFileSync(path.join(servicesDir, file), 'utf8');
        const service = yaml.load(content);
        
        if (service.runbook) {
          const runbookPath = path.resolve(servicesDir, service.runbook);
          if (fs.existsSync(runbookPath)) {
            runbooksFound++;
          } else {
            missingRunbooks.push(`${service.name}: ${service.runbook}`);
          }
        } else {
          missingRunbooks.push(`${service.name}: no runbook specified`);
        }
      } catch (error) {
        missingRunbooks.push(`${file}: parsing error`);
      }
    }
    
    return {
      total: serviceFiles.length,
      covered: runbooksFound,
      percentage: serviceFiles.length > 0 ? (runbooksFound / serviceFiles.length) * 100 : 0,
      missing: missingRunbooks
    };
  }

  calculateArchitectureCoverage() {
    const architectureDir = path.join(this.docsPath, 'architecture');
    
    const requiredFiles = ['l2.mmd', 'l2.puml', 'l2.md'];
    const existingFiles = [];
    
    if (fs.existsSync(architectureDir)) {
      const files = fs.readdirSync(architectureDir);
      requiredFiles.forEach(required => {
        if (files.some(file => file.includes(required.split('.')[0]))) {
          existingFiles.push(required);
        }
      });
    }
    
    const missing = requiredFiles.filter(file => !existingFiles.includes(file));
    
    return {
      total: requiredFiles.length,
      covered: existingFiles.length,
      percentage: (existingFiles.length / requiredFiles.length) * 100,
      missing: missing.map(file => `architecture/${file}`)
    };
  }

  calculateFeatureFlagCoverage() {
    const releaseDir = path.join(this.docsPath, 'release');
    
    const requiredFiles = ['flags.yaml', 'rollback.md'];
    const existingFiles = [];
    const missing = [];
    
    if (fs.existsSync(releaseDir)) {
      for (const file of requiredFiles) {
        const filePath = path.join(releaseDir, file);
        if (fs.existsSync(filePath)) {
          existingFiles.push(file);
          
          // Validate content
          if (file === 'flags.yaml') {
            try {
              const content = fs.readFileSync(filePath, 'utf8');
              const flags = yaml.load(content);
              if (!flags.flags || !Array.isArray(flags.flags)) {
                missing.push(`${file}: invalid structure`);
              }
            } catch (error) {
              missing.push(`${file}: parsing error`);
            }
          }
        } else {
          missing.push(file);
        }
      }
    } else {
      missing.push(...requiredFiles);
    }
    
    return {
      total: requiredFiles.length,
      covered: existingFiles.length,
      percentage: (existingFiles.length / requiredFiles.length) * 100,
      missing: missing
    };
  }

  /**
   * Check governance framework health
   */
  checkFrameworkHealth() {
    console.log('🏥 Checking governance framework health...\n');
    
    const health = {
      validationStatus: this.checkValidationHealth(),
      ciPipeline: this.checkCIPipelineHealth(),
      documentation: this.checkDocumentationHealth(),
      tracing: this.checkTracingHealth()
    };
    
    this.metrics.health = health;
    
    const healthyComponents = Object.values(health).filter(h => h.status === 'healthy').length;
    const totalComponents = Object.keys(health).length;
    const overallHealth = (healthyComponents / totalComponents) * 100;
    
    console.log('🏥 Health Summary:');
    console.log(`   Overall Health: ${overallHealth.toFixed(1)}%`);
    console.log(`   Healthy Components: ${healthyComponents}/${totalComponents}`);
    console.log('');
    
    Object.entries(health).forEach(([component, data]) => {
      const status = data.status === 'healthy' ? '✅' : data.status === 'warning' ? '⚠️' : '❌';
      console.log(`   ${status} ${component}: ${data.status}`);
      if (data.issues && data.issues.length > 0) {
        data.issues.forEach(issue => console.log(`      - ${issue}`));
      }
    });
    
    return health;
  }

  checkValidationHealth() {
    const issues = [];
    
    // Check if validation scripts exist
    const validationScript = path.join(__dirname, 'validate-governance.js');
    if (!fs.existsSync(validationScript)) {
      issues.push('Validation script not found');
    }
    
    // Check if schemas exist
    const schemaDir = path.join(__dirname, '../schemas');
    const requiredSchemas = ['service-catalog.schema.json', 'dependency.schema.json'];
    
    for (const schema of requiredSchemas) {
      const schemaPath = path.join(schemaDir, schema);
      if (!fs.existsSync(schemaPath)) {
        issues.push(`Schema not found: ${schema}`);
      }
    }
    
    return {
      status: issues.length === 0 ? 'healthy' : 'error',
      issues: issues
    };
  }

  checkCIPipelineHealth() {
    const issues = [];
    
    // Check if CI workflow exists
    const ciWorkflow = path.join(__dirname, '../.github/workflows/governance-validation.yml');
    if (!fs.existsSync(ciWorkflow)) {
      issues.push('CI workflow not found');
    }
    
    // Check if test files exist
    const testDir = path.join(__dirname, '../tests');
    const requiredTests = ['governance-ci.test.js', 'service-catalog.test.js'];
    
    for (const test of requiredTests) {
      const testPath = path.join(testDir, test);
      if (!fs.existsSync(testPath)) {
        issues.push(`Test file not found: ${test}`);
      }
    }
    
    return {
      status: issues.length === 0 ? 'healthy' : issues.length <= 2 ? 'warning' : 'error',
      issues: issues
    };
  }

  checkDocumentationHealth() {
    const issues = [];
    
    // Check directory structure
    const requiredDirs = [
      'services', 'contracts/http', 'contracts/events', 
      'runbooks', 'release', 'architecture'
    ];
    
    for (const dir of requiredDirs) {
      const dirPath = path.join(this.docsPath, dir);
      if (!fs.existsSync(dirPath)) {
        issues.push(`Directory not found: ${dir}`);
      }
    }
    
    // Check for orphaned contracts
    const orphanedContracts = this.findOrphanedContracts();
    if (orphanedContracts.length > 0) {
      issues.push(`${orphanedContracts.length} orphaned contracts found`);
    }
    
    return {
      status: issues.length === 0 ? 'healthy' : issues.length <= 3 ? 'warning' : 'error',
      issues: issues
    };
  }

  checkTracingHealth() {
    const issues = [];
    
    // Check if tracing utilities exist
    const tracingUtils = path.join(__dirname, 'tracing-utils.js');
    const tracingMiddleware = path.join(__dirname, 'tracing-middleware.js');
    
    if (!fs.existsSync(tracingUtils)) {
      issues.push('Tracing utilities not found');
    }
    
    if (!fs.existsSync(tracingMiddleware)) {
      issues.push('Tracing middleware not found');
    }
    
    // Check if tracing tests exist
    const tracingTests = path.join(__dirname, '../tests/tracing-middleware.test.js');
    if (!fs.existsSync(tracingTests)) {
      issues.push('Tracing tests not found');
    }
    
    return {
      status: issues.length === 0 ? 'healthy' : 'warning',
      issues: issues
    };
  }

  /**
   * Find orphaned contracts
   */
  findOrphanedContracts() {
    const servicesDir = path.join(this.docsPath, 'services');
    const httpContractsDir = path.join(this.docsPath, 'contracts/http');
    const eventContractsDir = path.join(this.docsPath, 'contracts/events');
    
    const referencedContracts = new Set();
    const orphanedContracts = [];
    
    // Collect referenced contracts
    if (fs.existsSync(servicesDir)) {
      const serviceFiles = fs.readdirSync(servicesDir)
        .filter(file => file.endsWith('.yaml') || file.endsWith('.yml'));
      
      for (const file of serviceFiles) {
        try {
          const content = fs.readFileSync(path.join(servicesDir, file), 'utf8');
          const service = yaml.load(content);
          
          if (service.openapi) {
            referencedContracts.add(path.resolve(servicesDir, service.openapi));
          }
          if (service.asyncapi) {
            referencedContracts.add(path.resolve(servicesDir, service.asyncapi));
          }
        } catch (error) {
          // Skip files that can't be parsed
        }
      }
    }
    
    // Check for orphaned HTTP contracts
    if (fs.existsSync(httpContractsDir)) {
      const contractFiles = fs.readdirSync(httpContractsDir)
        .filter(file => file.endsWith('.openapi.yaml') || file.endsWith('.openapi.yml'));
      
      for (const file of contractFiles) {
        const fullPath = path.resolve(httpContractsDir, file);
        if (!referencedContracts.has(fullPath)) {
          orphanedContracts.push(`http/${file}`);
        }
      }
    }
    
    // Check for orphaned Event contracts
    if (fs.existsSync(eventContractsDir)) {
      const contractFiles = fs.readdirSync(eventContractsDir)
        .filter(file => file.endsWith('.asyncapi.yaml') || file.endsWith('.asyncapi.yml'));
      
      for (const file of contractFiles) {
        const fullPath = path.resolve(eventContractsDir, file);
        if (!referencedContracts.has(fullPath)) {
          orphanedContracts.push(`events/${file}`);
        }
      }
    }
    
    return orphanedContracts;
  }

  /**
   * Generate alerts for failed validations and missing documentation
   */
  generateAlerts() {
    console.log('🚨 Generating governance alerts...\n');
    
    const alerts = [];
    
    // Coverage-based alerts
    Object.entries(this.metrics.coverage).forEach(([component, data]) => {
      if (data.percentage < 60) {
        alerts.push({
          type: 'coverage',
          severity: 'high',
          component: component,
          message: `${component} coverage is critically low: ${data.percentage.toFixed(1)}%`,
          details: data.missing.slice(0, 5)
        });
      } else if (data.percentage < 80) {
        alerts.push({
          type: 'coverage',
          severity: 'medium',
          component: component,
          message: `${component} coverage is below target: ${data.percentage.toFixed(1)}%`,
          details: data.missing.slice(0, 3)
        });
      }
    });
    
    // Health-based alerts
    Object.entries(this.metrics.health).forEach(([component, data]) => {
      if (data.status === 'error') {
        alerts.push({
          type: 'health',
          severity: 'high',
          component: component,
          message: `${component} health check failed`,
          details: data.issues
        });
      } else if (data.status === 'warning') {
        alerts.push({
          type: 'health',
          severity: 'medium',
          component: component,
          message: `${component} health check has warnings`,
          details: data.issues
        });
      }
    });
    
    // Orphaned contracts alert
    const orphanedContracts = this.findOrphanedContracts();
    if (orphanedContracts.length > 0) {
      alerts.push({
        type: 'orphaned',
        severity: 'medium',
        component: 'contracts',
        message: `${orphanedContracts.length} orphaned contracts detected`,
        details: orphanedContracts.slice(0, 5)
      });
    }
    
    this.metrics.alerts = alerts;
    
    // Display alerts
    if (alerts.length === 0) {
      console.log('✅ No alerts generated - governance framework is healthy');
    } else {
      console.log(`🚨 ${alerts.length} alerts generated:`);
      console.log('');
      
      const highAlerts = alerts.filter(a => a.severity === 'high');
      const mediumAlerts = alerts.filter(a => a.severity === 'medium');
      
      if (highAlerts.length > 0) {
        console.log('🔴 HIGH SEVERITY ALERTS:');
        highAlerts.forEach(alert => {
          console.log(`   ❌ ${alert.message}`);
          if (alert.details && alert.details.length > 0) {
            alert.details.forEach(detail => console.log(`      - ${detail}`));
          }
        });
        console.log('');
      }
      
      if (mediumAlerts.length > 0) {
        console.log('🟡 MEDIUM SEVERITY ALERTS:');
        mediumAlerts.forEach(alert => {
          console.log(`   ⚠️ ${alert.message}`);
          if (alert.details && alert.details.length > 0) {
            alert.details.forEach(detail => console.log(`      - ${detail}`));
          }
        });
      }
    }
    
    return alerts;
  }

  /**
   * Generate monitoring dashboard data
   */
  generateDashboard() {
    const dashboard = {
      timestamp: new Date().toISOString(),
      summary: {
        overallCoverage: this.calculateOverallCoverage(),
        overallHealth: this.calculateOverallHealth(),
        totalAlerts: this.metrics.alerts.length,
        highSeverityAlerts: this.metrics.alerts.filter(a => a.severity === 'high').length
      },
      coverage: this.metrics.coverage,
      health: this.metrics.health,
      alerts: this.metrics.alerts,
      recommendations: this.generateRecommendations()
    };
    
    return dashboard;
  }

  calculateOverallCoverage() {
    const coverageValues = Object.values(this.metrics.coverage).map(c => c.percentage);
    return coverageValues.length > 0 ? 
      coverageValues.reduce((sum, val) => sum + val, 0) / coverageValues.length : 0;
  }

  calculateOverallHealth() {
    const healthyComponents = Object.values(this.metrics.health).filter(h => h.status === 'healthy').length;
    const totalComponents = Object.keys(this.metrics.health).length;
    return totalComponents > 0 ? (healthyComponents / totalComponents) * 100 : 0;
  }

  generateRecommendations() {
    const recommendations = [];
    
    // Coverage recommendations
    Object.entries(this.metrics.coverage).forEach(([component, data]) => {
      if (data.percentage < 80 && data.missing.length > 0) {
        recommendations.push({
          type: 'coverage',
          priority: data.percentage < 60 ? 'high' : 'medium',
          component: component,
          action: `Improve ${component} coverage`,
          details: `Add missing: ${data.missing.slice(0, 3).join(', ')}`
        });
      }
    });
    
    // Health recommendations
    Object.entries(this.metrics.health).forEach(([component, data]) => {
      if (data.status !== 'healthy' && data.issues.length > 0) {
        recommendations.push({
          type: 'health',
          priority: data.status === 'error' ? 'high' : 'medium',
          component: component,
          action: `Fix ${component} health issues`,
          details: data.issues.slice(0, 2).join(', ')
        });
      }
    });
    
    return recommendations;
  }

  /**
   * Run complete monitoring cycle
   */
  async runMonitoring() {
    console.log('🔍 Starting governance framework monitoring...\n');
    
    // Calculate metrics
    this.calculateCoverageMetrics();
    console.log('');
    
    this.checkFrameworkHealth();
    console.log('');
    
    this.generateAlerts();
    console.log('');
    
    // Generate dashboard
    const dashboard = this.generateDashboard();
    
    console.log('📊 Monitoring Summary:');
    console.log(`   Overall Coverage: ${dashboard.summary.overallCoverage.toFixed(1)}%`);
    console.log(`   Overall Health: ${dashboard.summary.overallHealth.toFixed(1)}%`);
    console.log(`   Total Alerts: ${dashboard.summary.totalAlerts}`);
    console.log(`   High Severity: ${dashboard.summary.highSeverityAlerts}`);
    
    return dashboard;
  }
}

// CLI usage
if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  
  const flags = {
    coverage: args.includes('--coverage'),
    health: args.includes('--health'),
    alerts: args.includes('--alerts'),
    dashboard: args.includes('--dashboard'),
    json: args.includes('--json'),
    help: args.includes('--help') || args.includes('-h')
  };
  
  const customPath = args.find(arg => arg.startsWith('--path='))?.split('=')[1] || 'docs';
  
  if (flags.help) {
    console.log(`
📊 Governance Framework Monitoring Tool

Usage: node governance-monitoring.js [flags] [options]

Monitoring Flags:
  --coverage        Calculate documentation coverage metrics
  --health          Check governance framework health
  --alerts          Generate alerts for issues
  --dashboard       Generate complete monitoring dashboard
  --json            Output results in JSON format

Options:
  --path=<path>     Use custom docs path (default: docs)
  --help, -h        Show this help message

Examples:
  node governance-monitoring.js --coverage
  node governance-monitoring.js --health --alerts
  node governance-monitoring.js --dashboard --json
  node governance-monitoring.js --coverage --path=custom/docs
`);
    process.exit(0);
  }
  
  const monitor = new GovernanceMonitor(customPath);
  
  if (flags.coverage) {
    const coverage = monitor.calculateCoverageMetrics();
    if (flags.json) {
      console.log(JSON.stringify(coverage, null, 2));
    }
  }
  
  if (flags.health) {
    const health = monitor.checkFrameworkHealth();
    if (flags.json) {
      console.log(JSON.stringify(health, null, 2));
    }
  }
  
  if (flags.alerts) {
    const alerts = monitor.generateAlerts();
    if (flags.json) {
      console.log(JSON.stringify(alerts, null, 2));
    }
  }
  
  if (flags.dashboard) {
    monitor.runMonitoring().then(dashboard => {
      if (flags.json) {
        console.log(JSON.stringify(dashboard, null, 2));
      }
    });
  }
  
  // If no specific flags, run complete monitoring
  if (!flags.coverage && !flags.health && !flags.alerts && !flags.dashboard) {
    monitor.runMonitoring();
  }
}

export default GovernanceMonitor;
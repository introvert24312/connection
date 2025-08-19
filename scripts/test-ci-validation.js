#!/usr/bin/env node

import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';

console.log('🧪 Running Governance CI Validation Tests\n');

try {
  // Run the comprehensive test suite
  console.log('📋 Running comprehensive CI validation tests...');
  const testResult = execSync('npm test -- tests/governance-ci.test.js', { 
    encoding: 'utf8',
    stdio: 'inherit'
  });
  
  console.log('\n✅ All CI validation tests passed!');
  
  // Run actual validation on current repository
  console.log('\n🔍 Running validation on current repository...');
  
  const validations = [
    { flag: '--catalog', name: 'Service Catalog' },
    { flag: '--openapi', name: 'OpenAPI Contracts' },
    { flag: '--asyncapi', name: 'AsyncAPI Contracts' },
    { flag: '--sync', name: 'Documentation Sync' },
    { flag: '--orphans', name: 'Orphaned Contracts' },
    { flag: '--completeness', name: 'Catalog Completeness' }
  ];
  
  let allPassed = true;
  
  for (const validation of validations) {
    try {
      console.log(`\n📊 ${validation.name}:`);
      const result = execSync(`node scripts/validate-governance.js ${validation.flag}`, {
        encoding: 'utf8',
        stdio: 'pipe'
      });
      console.log(result);
    } catch (error) {
      console.log(`❌ ${validation.name} failed:`);
      if (error.stdout) console.log(error.stdout);
      if (error.stderr) console.log(error.stderr);
      allPassed = false;
    }
  }
  
  console.log('\n' + '='.repeat(50));
  if (allPassed) {
    console.log('✅ All governance validations passed!');
    console.log('🚀 CI pipeline is ready for deployment');
  } else {
    console.log('❌ Some governance validations failed');
    console.log('🔧 Please fix the issues before deploying CI pipeline');
  }
  
} catch (error) {
  console.error('❌ Test execution failed:', error.message);
  process.exit(1);
}
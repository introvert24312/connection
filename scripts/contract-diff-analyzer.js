#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import { execSync } from 'child_process';

class ContractDiffAnalyzer {
  constructor() {
    this.breakingChangePatterns = {
      openapi: [
        {
          pattern: /^-\s+.*required:/m,
          description: 'Removed required field',
          severity: 'breaking'
        },
        {
          pattern: /^-\s+.*paths:/m,
          description: 'Removed API endpoint',
          severity: 'breaking'
        },
        {
          pattern: /^-\s+.*\/[^:]+:/m,
          description: 'Removed specific path',
          severity: 'breaking'
        },
        {
          pattern: /^-\s+.*get:|^-\s+.*post:|^-\s+.*put:|^-\s+.*delete:/m,
          description: 'Removed HTTP method',
          severity: 'breaking'
        },
        {
          pattern: /^-\s+.*type:\s*string/m,
          description: 'Changed field type from string',
          severity: 'breaking'
        },
        {
          pattern: /^-\s+.*type:\s*integer/m,
          description: 'Changed field type from integer',
          severity: 'breaking'
        }
      ],
      asyncapi: [
        {
          pattern: /^-\s+.*channels:/m,
          description: 'Removed event channel',
          severity: 'breaking'
        },
        {
          pattern: /^-\s+.*subscribe:/m,
          description: 'Removed subscription endpoint',
          severity: 'breaking'
        },
        {
          pattern: /^-\s+.*publish:/m,
          description: 'Removed publish endpoint',
          severity: 'breaking'
        },
        {
          pattern: /^-\s+.*required:/m,
          description: 'Removed required field',
          severity: 'breaking'
        }
      ]
    };
  }

  analyzeContractDiff(filePath, baseBranch = 'origin/main') {
    try {
      // Get the diff for this file
      const diff = execSync(`git diff ${baseBranch} -- ${filePath}`, { encoding: 'utf8' });
      
      if (!diff.trim()) {
        return { hasBreakingChanges: false, changes: [] };
      }

      const contractType = this.detectContractType(filePath);
      const patterns = this.breakingChangePatterns[contractType] || [];
      
      const changes = [];
      
      for (const { pattern, description, severity } of patterns) {
        const matches = diff.match(pattern);
        if (matches) {
          changes.push({
            type: severity,
            description,
            pattern: pattern.toString(),
            match: matches[0].trim()
          });
        }
      }
      
      // Additional semantic analysis
      const semanticChanges = this.analyzeSemanticChanges(filePath, baseBranch);
      changes.push(...semanticChanges);
      
      const hasBreakingChanges = changes.some(change => change.type === 'breaking');
      
      return { hasBreakingChanges, changes };
      
    } catch (error) {
      return { 
        hasBreakingChanges: false, 
        changes: [], 
        error: `Could not analyze diff: ${error.message}` 
      };
    }
  }

  detectContractType(filePath) {
    if (filePath.includes('.openapi.')) {
      return 'openapi';
    } else if (filePath.includes('.asyncapi.')) {
      return 'asyncapi';
    }
    return 'unknown';
  }

  analyzeSemanticChanges(filePath, baseBranch) {
    const changes = [];
    
    try {
      // Get current and previous versions of the file
      const currentContent = fs.readFileSync(filePath, 'utf8');
      const previousContent = execSync(`git show ${baseBranch}:${filePath}`, { encoding: 'utf8' });
      
      const currentSpec = yaml.load(currentContent);
      const previousSpec = yaml.load(previousContent);
      
      // Analyze version changes
      if (currentSpec.info?.version !== previousSpec.info?.version) {
        const versionChange = this.analyzeVersionChange(
          previousSpec.info?.version, 
          currentSpec.info?.version
        );
        changes.push(versionChange);
      }
      
      // Analyze path changes for OpenAPI
      if (currentSpec.paths && previousSpec.paths) {
        const pathChanges = this.analyzePathChanges(previousSpec.paths, currentSpec.paths);
        changes.push(...pathChanges);
      }
      
      // Analyze channel changes for AsyncAPI
      if (currentSpec.channels && previousSpec.channels) {
        const channelChanges = this.analyzeChannelChanges(previousSpec.channels, currentSpec.channels);
        changes.push(...channelChanges);
      }
      
    } catch (error) {
      // If we can't parse the files, skip semantic analysis
    }
    
    return changes;
  }

  analyzeVersionChange(oldVersion, newVersion) {
    if (!oldVersion || !newVersion) {
      return { type: 'info', description: 'Version information missing' };
    }
    
    const oldParts = oldVersion.split('.').map(Number);
    const newParts = newVersion.split('.').map(Number);
    
    // Major version change
    if (newParts[0] > oldParts[0]) {
      return { 
        type: 'breaking', 
        description: `Major version change: ${oldVersion} → ${newVersion}` 
      };
    }
    
    // Minor version change
    if (newParts[1] > oldParts[1]) {
      return { 
        type: 'minor', 
        description: `Minor version change: ${oldVersion} → ${newVersion}` 
      };
    }
    
    // Patch version change
    if (newParts[2] > oldParts[2]) {
      return { 
        type: 'patch', 
        description: `Patch version change: ${oldVersion} → ${newVersion}` 
      };
    }
    
    return { 
      type: 'info', 
      description: `Version unchanged: ${newVersion}` 
    };
  }

  analyzePathChanges(oldPaths, newPaths) {
    const changes = [];
    
    // Check for removed paths
    for (const path in oldPaths) {
      if (!(path in newPaths)) {
        changes.push({
          type: 'breaking',
          description: `Removed API path: ${path}`
        });
      } else {
        // Check for removed methods
        const oldMethods = Object.keys(oldPaths[path]);
        const newMethods = Object.keys(newPaths[path]);
        
        for (const method of oldMethods) {
          if (!newMethods.includes(method)) {
            changes.push({
              type: 'breaking',
              description: `Removed HTTP method: ${method.toUpperCase()} ${path}`
            });
          }
        }
      }
    }
    
    // Check for new paths (non-breaking)
    for (const path in newPaths) {
      if (!(path in oldPaths)) {
        changes.push({
          type: 'addition',
          description: `Added new API path: ${path}`
        });
      }
    }
    
    return changes;
  }

  analyzeChannelChanges(oldChannels, newChannels) {
    const changes = [];
    
    // Check for removed channels
    for (const channel in oldChannels) {
      if (!(channel in newChannels)) {
        changes.push({
          type: 'breaking',
          description: `Removed event channel: ${channel}`
        });
      }
    }
    
    // Check for new channels (non-breaking)
    for (const channel in newChannels) {
      if (!(channel in oldChannels)) {
        changes.push({
          type: 'addition',
          description: `Added new event channel: ${channel}`
        });
      }
    }
    
    return changes;
  }

  generateReport(results) {
    console.log('\n📊 Contract Diff Analysis Report');
    console.log('================================');
    
    let totalBreaking = 0;
    let totalFiles = 0;
    
    for (const [filePath, result] of Object.entries(results)) {
      totalFiles++;
      console.log(`\n📄 ${filePath}:`);
      
      if (result.error) {
        console.log(`  ⚠ ${result.error}`);
        continue;
      }
      
      if (result.changes.length === 0) {
        console.log('  ✅ No significant changes detected');
        continue;
      }
      
      const breakingChanges = result.changes.filter(c => c.type === 'breaking');
      const minorChanges = result.changes.filter(c => c.type === 'minor' || c.type === 'addition');
      const infoChanges = result.changes.filter(c => c.type === 'info' || c.type === 'patch');
      
      if (breakingChanges.length > 0) {
        totalBreaking += breakingChanges.length;
        console.log(`  ❌ Breaking changes (${breakingChanges.length}):`);
        breakingChanges.forEach(change => {
          console.log(`     - ${change.description}`);
        });
      }
      
      if (minorChanges.length > 0) {
        console.log(`  ⚠ Non-breaking changes (${minorChanges.length}):`);
        minorChanges.forEach(change => {
          console.log(`     - ${change.description}`);
        });
      }
      
      if (infoChanges.length > 0) {
        console.log(`  ℹ Info (${infoChanges.length}):`);
        infoChanges.forEach(change => {
          console.log(`     - ${change.description}`);
        });
      }
    }
    
    console.log('\n📈 Summary:');
    console.log(`   Files analyzed: ${totalFiles}`);
    console.log(`   Breaking changes: ${totalBreaking}`);
    
    return totalBreaking === 0;
  }
}

// CLI usage
if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const baseBranch = args.find(arg => arg.startsWith('--base='))?.split('=')[1] || 'origin/main';
  const filePath = args.find(arg => !arg.startsWith('--'));
  
  if (args.includes('--help') || args.includes('-h')) {
    console.log(`
🔍 Contract Diff Analyzer

Usage: node contract-diff-analyzer.js [file] [options]

Arguments:
  file              Specific contract file to analyze (optional)

Options:
  --base=<branch>   Base branch for comparison (default: origin/main)
  --help, -h        Show this help message

Examples:
  node contract-diff-analyzer.js --base=origin/develop
  node contract-diff-analyzer.js docs/contracts/http/api.openapi.yaml
`);
    process.exit(0);
  }
  
  const analyzer = new ContractDiffAnalyzer();
  
  if (filePath) {
    // Analyze single file
    const result = analyzer.analyzeContractDiff(filePath, baseBranch);
    const results = { [filePath]: result };
    const success = analyzer.generateReport(results);
    process.exit(success ? 0 : 1);
  } else {
    // Analyze all contract files
    try {
      const changedFiles = execSync(`git diff --name-only ${baseBranch} -- docs/contracts/`, { encoding: 'utf8' })
        .split('\n')
        .filter(file => file.trim() && (file.includes('.openapi.') || file.includes('.asyncapi.')));
      
      if (changedFiles.length === 0) {
        console.log('✅ No contract changes detected');
        process.exit(0);
      }
      
      const results = {};
      for (const file of changedFiles) {
        results[file] = analyzer.analyzeContractDiff(file, baseBranch);
      }
      
      const success = analyzer.generateReport(results);
      process.exit(success ? 0 : 1);
      
    } catch (error) {
      console.error(`❌ Error analyzing contracts: ${error.message}`);
      process.exit(1);
    }
  }
}

export default ContractDiffAnalyzer;
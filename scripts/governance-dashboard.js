#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import GovernanceMonitor from './governance-monitoring.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

class GovernanceDashboard {
  constructor(docsPath = 'docs') {
    this.monitor = new GovernanceMonitor(docsPath);
    this.docsPath = docsPath;
  }

  /**
   * Generate HTML dashboard
   */
  async generateHTMLDashboard() {
    console.log('📊 Generating governance dashboard...\n');
    
    // Run monitoring to get data
    const dashboardData = await this.monitor.runMonitoring();
    
    // Generate HTML
    const html = this.createHTMLDashboard(dashboardData);
    
    // Save dashboard
    const outputPath = path.join(__dirname, '../governance-dashboard.html');
    fs.writeFileSync(outputPath, html);
    
    console.log(`\n📊 Dashboard generated: ${outputPath}`);
    console.log(`   Open in browser: file://${path.resolve(outputPath)}`);
    
    return outputPath;
  }

  createHTMLDashboard(data) {
    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Governance Framework Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background-color: #f5f7fa;
            color: #333;
            line-height: 1.6;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .header .timestamp {
            opacity: 0.9;
            font-size: 0.9em;
        }
        
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .summary-card {
            background: white;
            padding: 25px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            text-align: center;
        }
        
        .summary-card h3 {
            color: #666;
            font-size: 0.9em;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 10px;
        }
        
        .summary-card .value {
            font-size: 2.5em;
            font-weight: bold;
            margin-bottom: 5px;
        }
        
        .summary-card .unit {
            color: #999;
            font-size: 0.8em;
        }
        
        .coverage-good { color: #27ae60; }
        .coverage-warning { color: #f39c12; }
        .coverage-error { color: #e74c3c; }
        
        .section {
            background: white;
            margin-bottom: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        
        .section-header {
            background: #f8f9fa;
            padding: 20px;
            border-bottom: 1px solid #e9ecef;
        }
        
        .section-header h2 {
            color: #495057;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .section-content {
            padding: 20px;
        }
        
        .coverage-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
        }
        
        .coverage-item {
            border: 1px solid #e9ecef;
            border-radius: 8px;
            padding: 20px;
        }
        
        .coverage-item h4 {
            margin-bottom: 15px;
            text-transform: capitalize;
        }
        
        .progress-bar {
            background: #e9ecef;
            border-radius: 10px;
            height: 20px;
            margin-bottom: 10px;
            overflow: hidden;
        }
        
        .progress-fill {
            height: 100%;
            border-radius: 10px;
            transition: width 0.3s ease;
        }
        
        .progress-good { background: #27ae60; }
        .progress-warning { background: #f39c12; }
        .progress-error { background: #e74c3c; }
        
        .coverage-details {
            font-size: 0.9em;
            color: #666;
        }
        
        .health-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
        }
        
        .health-item {
            border: 1px solid #e9ecef;
            border-radius: 8px;
            padding: 20px;
        }
        
        .health-status {
            display: flex;
            align-items: center;
            gap: 10px;
            margin-bottom: 15px;
        }
        
        .status-icon {
            width: 20px;
            height: 20px;
            border-radius: 50%;
        }
        
        .status-healthy { background: #27ae60; }
        .status-warning { background: #f39c12; }
        .status-error { background: #e74c3c; }
        
        .health-issues {
            font-size: 0.9em;
            color: #666;
        }
        
        .health-issues li {
            margin-bottom: 5px;
        }
        
        .alerts-list {
            max-height: 400px;
            overflow-y: auto;
        }
        
        .alert-item {
            border-left: 4px solid;
            padding: 15px;
            margin-bottom: 15px;
            border-radius: 0 8px 8px 0;
            background: #f8f9fa;
        }
        
        .alert-high { border-left-color: #e74c3c; }
        .alert-medium { border-left-color: #f39c12; }
        
        .alert-header {
            display: flex;
            justify-content: between;
            align-items: center;
            margin-bottom: 10px;
        }
        
        .alert-severity {
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 0.8em;
            font-weight: bold;
            text-transform: uppercase;
        }
        
        .severity-high {
            background: #e74c3c;
            color: white;
        }
        
        .severity-medium {
            background: #f39c12;
            color: white;
        }
        
        .alert-details {
            font-size: 0.9em;
            color: #666;
        }
        
        .alert-details li {
            margin-bottom: 3px;
        }
        
        .recommendations-list {
            max-height: 400px;
            overflow-y: auto;
        }
        
        .recommendation-item {
            border: 1px solid #e9ecef;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 15px;
        }
        
        .recommendation-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 10px;
        }
        
        .priority-high { color: #e74c3c; font-weight: bold; }
        .priority-medium { color: #f39c12; font-weight: bold; }
        
        .no-data {
            text-align: center;
            color: #666;
            font-style: italic;
            padding: 40px;
        }
        
        .refresh-button {
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: #667eea;
            color: white;
            border: none;
            border-radius: 50px;
            padding: 15px 25px;
            cursor: pointer;
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
            font-weight: bold;
        }
        
        .refresh-button:hover {
            background: #5a6fd8;
            transform: translateY(-2px);
        }
        
        @media (max-width: 768px) {
            .container {
                padding: 10px;
            }
            
            .summary-grid {
                grid-template-columns: 1fr;
            }
            
            .coverage-grid,
            .health-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🏛️ Governance Framework Dashboard</h1>
            <div class="timestamp">Last updated: ${new Date(data.timestamp).toLocaleString()}</div>
        </div>
        
        <div class="summary-grid">
            <div class="summary-card">
                <h3>Overall Coverage</h3>
                <div class="value ${this.getCoverageClass(data.summary.overallCoverage)}">${data.summary.overallCoverage.toFixed(1)}</div>
                <div class="unit">%</div>
            </div>
            <div class="summary-card">
                <h3>Framework Health</h3>
                <div class="value ${this.getCoverageClass(data.summary.overallHealth)}">${data.summary.overallHealth.toFixed(1)}</div>
                <div class="unit">%</div>
            </div>
            <div class="summary-card">
                <h3>Total Alerts</h3>
                <div class="value ${data.summary.totalAlerts > 0 ? 'coverage-warning' : 'coverage-good'}">${data.summary.totalAlerts}</div>
                <div class="unit">issues</div>
            </div>
            <div class="summary-card">
                <h3>High Priority</h3>
                <div class="value ${data.summary.highSeverityAlerts > 0 ? 'coverage-error' : 'coverage-good'}">${data.summary.highSeverityAlerts}</div>
                <div class="unit">critical</div>
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">
                <h2>📊 Documentation Coverage</h2>
            </div>
            <div class="section-content">
                <div class="coverage-grid">
                    ${Object.entries(data.coverage).map(([component, coverage]) => `
                        <div class="coverage-item">
                            <h4>${component.replace(/([A-Z])/g, ' $1').toLowerCase()}</h4>
                            <div class="progress-bar">
                                <div class="progress-fill ${this.getProgressClass(coverage.percentage)}" 
                                     style="width: ${coverage.percentage}%"></div>
                            </div>
                            <div class="coverage-details">
                                <strong>${coverage.percentage.toFixed(1)}%</strong> - 
                                ${coverage.covered}/${coverage.total} complete
                                ${coverage.missing && coverage.missing.length > 0 ? 
                                    `<br><small>Missing: ${coverage.missing.slice(0, 2).join(', ')}${coverage.missing.length > 2 ? '...' : ''}</small>` : 
                                    ''}
                            </div>
                        </div>
                    `).join('')}
                </div>
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">
                <h2>🏥 Framework Health</h2>
            </div>
            <div class="section-content">
                <div class="health-grid">
                    ${Object.entries(data.health).map(([component, health]) => `
                        <div class="health-item">
                            <div class="health-status">
                                <div class="status-icon ${this.getStatusClass(health.status)}"></div>
                                <h4>${component.replace(/([A-Z])/g, ' $1').toLowerCase()}</h4>
                            </div>
                            <div class="health-issues">
                                ${health.issues && health.issues.length > 0 ? 
                                    `<ul>${health.issues.map(issue => `<li>${issue}</li>`).join('')}</ul>` :
                                    '<em>No issues detected</em>'}
                            </div>
                        </div>
                    `).join('')}
                </div>
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">
                <h2>🚨 Active Alerts</h2>
            </div>
            <div class="section-content">
                ${data.alerts.length > 0 ? `
                    <div class="alerts-list">
                        ${data.alerts.map(alert => `
                            <div class="alert-item alert-${alert.severity}">
                                <div class="alert-header">
                                    <strong>${alert.message}</strong>
                                    <span class="alert-severity severity-${alert.severity}">${alert.severity}</span>
                                </div>
                                ${alert.details && alert.details.length > 0 ? `
                                    <div class="alert-details">
                                        <ul>
                                            ${alert.details.map(detail => `<li>${detail}</li>`).join('')}
                                        </ul>
                                    </div>
                                ` : ''}
                            </div>
                        `).join('')}
                    </div>
                ` : '<div class="no-data">🎉 No active alerts - governance framework is healthy!</div>'}
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">
                <h2>💡 Recommendations</h2>
            </div>
            <div class="section-content">
                ${data.recommendations.length > 0 ? `
                    <div class="recommendations-list">
                        ${data.recommendations.map(rec => `
                            <div class="recommendation-item">
                                <div class="recommendation-header">
                                    <strong>${rec.action}</strong>
                                    <span class="priority-${rec.priority}">${rec.priority.toUpperCase()}</span>
                                </div>
                                <div class="recommendation-details">
                                    ${rec.details}
                                </div>
                            </div>
                        `).join('')}
                    </div>
                ` : '<div class="no-data">✅ No recommendations - governance framework is well maintained!</div>'}
            </div>
        </div>
    </div>
    
    <button class="refresh-button" onclick="location.reload()">
        🔄 Refresh
    </button>
    
    <script>
        // Auto-refresh every 5 minutes
        setTimeout(() => {
            location.reload();
        }, 5 * 60 * 1000);
        
        // Add smooth scrolling
        document.querySelectorAll('a[href^="#"]').forEach(anchor => {
            anchor.addEventListener('click', function (e) {
                e.preventDefault();
                document.querySelector(this.getAttribute('href')).scrollIntoView({
                    behavior: 'smooth'
                });
            });
        });
    </script>
</body>
</html>`;
  }

  getCoverageClass(percentage) {
    if (percentage >= 80) return 'coverage-good';
    if (percentage >= 60) return 'coverage-warning';
    return 'coverage-error';
  }

  getProgressClass(percentage) {
    if (percentage >= 80) return 'progress-good';
    if (percentage >= 60) return 'progress-warning';
    return 'progress-error';
  }

  getStatusClass(status) {
    switch (status) {
      case 'healthy': return 'status-healthy';
      case 'warning': return 'status-warning';
      case 'error': return 'status-error';
      default: return 'status-error';
    }
  }

  /**
   * Generate JSON dashboard data for API consumption
   */
  async generateJSONDashboard() {
    console.log('📊 Generating JSON dashboard data...\n');
    
    const dashboardData = await this.monitor.runMonitoring();
    
    // Save JSON data
    const outputPath = path.join(__dirname, '../governance-dashboard.json');
    fs.writeFileSync(outputPath, JSON.stringify(dashboardData, null, 2));
    
    console.log(`\n📊 JSON dashboard generated: ${outputPath}`);
    
    return dashboardData;
  }

  /**
   * Start dashboard server (simple HTTP server for development)
   */
  async startDashboardServer(port = 3000) {
    const http = await import('http');
    const url = await import('url');
    
    const server = http.createServer(async (req, res) => {
      const parsedUrl = url.parse(req.url, true);
      
      if (parsedUrl.pathname === '/') {
        // Serve HTML dashboard
        try {
          const dashboardData = await this.monitor.runMonitoring();
          const html = this.createHTMLDashboard(dashboardData);
          
          res.writeHead(200, { 'Content-Type': 'text/html' });
          res.end(html);
        } catch (error) {
          res.writeHead(500, { 'Content-Type': 'text/plain' });
          res.end('Error generating dashboard: ' + error.message);
        }
      } else if (parsedUrl.pathname === '/api/dashboard') {
        // Serve JSON API
        try {
          const dashboardData = await this.monitor.runMonitoring();
          
          res.writeHead(200, { 
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
          });
          res.end(JSON.stringify(dashboardData, null, 2));
        } catch (error) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: error.message }));
        }
      } else {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not Found');
      }
    });
    
    server.listen(port, () => {
      console.log(`📊 Governance Dashboard Server running at:`);
      console.log(`   HTML Dashboard: http://localhost:${port}/`);
      console.log(`   JSON API: http://localhost:${port}/api/dashboard`);
      console.log(`   Press Ctrl+C to stop`);
    });
    
    return server;
  }
}

// CLI usage
if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  
  const flags = {
    html: args.includes('--html'),
    json: args.includes('--json'),
    serve: args.includes('--serve'),
    help: args.includes('--help') || args.includes('-h')
  };
  
  const customPath = args.find(arg => arg.startsWith('--path='))?.split('=')[1] || 'docs';
  const port = parseInt(args.find(arg => arg.startsWith('--port='))?.split('=')[1]) || 3000;
  
  if (flags.help) {
    console.log(`
📊 Governance Dashboard Generator

Usage: node governance-dashboard.js [flags] [options]

Dashboard Flags:
  --html            Generate HTML dashboard file
  --json            Generate JSON dashboard data
  --serve           Start dashboard HTTP server
  
Options:
  --path=<path>     Use custom docs path (default: docs)
  --port=<port>     Server port (default: 3000)
  --help, -h        Show this help message

Examples:
  node governance-dashboard.js --html
  node governance-dashboard.js --json
  node governance-dashboard.js --serve --port=8080
  node governance-dashboard.js --html --json --path=custom/docs
`);
    process.exit(0);
  }
  
  const dashboard = new GovernanceDashboard(customPath);
  
  if (flags.serve) {
    dashboard.startDashboardServer(port);
  } else {
    if (flags.html) {
      dashboard.generateHTMLDashboard();
    }
    
    if (flags.json) {
      dashboard.generateJSONDashboard();
    }
    
    // If no specific flags, generate HTML dashboard
    if (!flags.html && !flags.json) {
      dashboard.generateHTMLDashboard();
    }
  }
}

export default GovernanceDashboard;
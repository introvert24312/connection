# Dependency Analysis Report

Generated: 2025-08-20T04:05:31.443Z

## Validation Summary
- Total Dependencies: 2
- Valid: 2
- Invalid: 0
- Status: ✅ ALL VALID

## Critical Path Analysis
- Total Paths: 2
- Critical Paths: 2
- Non-Critical Paths: 0

### Critical Paths
- **wordtagger-app POST /api/search** → **search-service GET /api/search**
  - Description: Main app search functionality
  - SLA: {"response_time_ms":2000,"availability":0.99,"error_rate":0.01}
- **wordtagger-app POST /api/git/commit** → **git-service POST /api/commit, external-data-service GET /api/status**
  - Description: Git commit operation with status check
  - SLA: {"response_time_ms":8000,"availability":0.95,"error_rate":0.05}

## Service Dependency Matrix
- **wordtagger-app** depends on: search-service, git-service, external-data-service
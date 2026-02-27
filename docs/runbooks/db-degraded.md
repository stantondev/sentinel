# Runbook: Database Degraded

## Symptoms
- `/health` returns `"status":"degraded"` with database check failing
- `/health/deep` shows high latency or connection errors
- Slow page loads, timeouts on entry creation/feed loading
- Oban jobs piling up (retryable count increasing)

## Severity: Critical

## Quick Checks (< 2 minutes)

### 1. Check deep health for DB details
```bash
curl -s -H "X-Monitor-Key: $MONITOR_API_KEY" \
  https://api.inkwell.social/health/deep | jq '.checks.database'
```
Look for: `latency_ms` (normal: < 5ms, concerning: > 50ms, critical: > 500ms), `active_connections`

### 2. Check Fly Postgres status
```bash
fly status --app inkwell-db
fly checks list --app inkwell-db
```

### 3. Check Fly Postgres platform
Visit: https://status.flyio.net/
Fly Postgres auto-suspends after inactivity and takes a few seconds to wake up.

## Remediation Steps

### If Postgres machine is suspended (cold start):
This is normal on Fly. The API is configured with generous checkout timeouts:
- `queue_target: 5_000` (5s)
- `queue_interval: 30_000` (30s)

The DB should auto-resume. If it doesn't:
```bash
fly machine restart --app inkwell-db
```

### If connection pool exhaustion:
```bash
# Check active connections via deep health
curl -s -H "X-Monitor-Key: $MONITOR_API_KEY" \
  https://api.inkwell.social/health/deep | jq '.checks.database.active_connections'

# If near pool_size (default 5), consider increasing
fly secrets set POOL_SIZE=10 --app inkwell-api
```

### If disk space issue:
```bash
fly ssh console --app inkwell-db -C "df -h"
```

### If Oban jobs are piling up:
```bash
# Check via deep health
curl -s -H "X-Monitor-Key: $MONITOR_API_KEY" \
  https://api.inkwell.social/health/deep | jq '.checks.oban'

# If retryable > 0, jobs are failing. Check API logs:
fly logs --app inkwell-api --no-tail | grep -i "oban\|error"
```

## Post-Incident
1. If cold start caused the issue, this is expected Fly behavior — document but don't panic
2. If connection pool exhaustion, increase `POOL_SIZE`
3. If disk space, consider vacuuming or extending volume
4. Update incident issue with root cause

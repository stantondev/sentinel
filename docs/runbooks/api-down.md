# Runbook: API Down

## Symptoms
- `/health` returning non-200 or timing out
- Frontend showing errors or loading indefinitely
- Better Stack alerts firing for API monitors

## Severity: Critical

## Quick Checks (< 2 minutes)

### 1. Check Fly.io machine status
```bash
fly status --app inkwell-api
```
Look for: machine state (started/stopped/failed), health check status

### 2. Check Fly.io platform status
Visit: https://status.flyio.net/
If Fly is having issues, wait for their resolution.

### 3. Check the health endpoint directly
```bash
curl -v https://api.inkwell.social/health
```
- **No response / timeout**: Machine is down or networking issue
- **503 with JSON**: App is running but a dependency is failing (check which component)
- **502 Bad Gateway**: Fly proxy can't reach the app (app crashed or not listening)

## Remediation Steps

### If machine is stopped/crashed:
```bash
# Restart the machine
fly machine restart --app inkwell-api

# If that doesn't work, check logs
fly logs --app inkwell-api --no-tail

# Look for: OOM kills, crash loops, migration failures
```

### If machine is running but health check fails:
```bash
# Check deep health for specifics
curl -H "X-Monitor-Key: $MONITOR_API_KEY" https://api.inkwell.social/health/deep

# Check if it's a DB issue → see db-degraded.md runbook
# Check if it's an Oban issue → restart should fix
```

### If networking/DNS issue:
```bash
# Check DNS resolution
dig api.inkwell.social

# Check if Fly proxy is working
fly ping --app inkwell-api

# Check if custom domain cert is valid
fly certs list --app inkwell-api
```

### Nuclear option (full redeploy):
```bash
cd /Users/stanton/Documents/Claude/inkwell
fly deploy --config fly.api.toml --wait-timeout 600 --depot=false
```

## Post-Incident
1. Check what caused the crash in `fly logs`
2. If OOM: consider increasing machine memory
3. If migration failed: fix migration and redeploy
4. Update the incident issue with root cause
5. Write a brief postmortem if downtime > 15 minutes

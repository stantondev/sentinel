# Runbook: Web Frontend Down

## Symptoms
- `inkwell.social` returning errors or blank page
- Better Stack alerts firing for web monitors
- API is healthy but frontend isn't

## Severity: High

## Quick Checks (< 2 minutes)

### 1. Check if it's just the web or also the API
```bash
# API healthy?
curl -s https://api.inkwell.social/health | jq .status

# Web responding?
curl -sI https://inkwell.social | head -5
```

If API is also down, follow `api-down.md` instead.

### 2. Check Fly.io web machine
```bash
fly status --app inkwell-web
```

### 3. Check logs
```bash
fly logs --app inkwell-web --no-tail
```
Look for: Next.js build errors, Node.js crashes, OOM kills

## Remediation Steps

### If machine is stopped/crashed:
```bash
fly machine restart --app inkwell-web
```

### If build/deploy error:
```bash
# Check recent deploy
fly releases --app inkwell-web

# Redeploy
cd /Users/stanton/Documents/Claude/inkwell
fly deploy --config fly.web.toml --wait-timeout 600 --depot=false
```

### If API connection issue (web can't reach API):
The web frontend proxies API calls through server-side route handlers.
If the API URL is misconfigured:
```bash
# Check the API_URL environment variable
fly ssh console --app inkwell-web -C "printenv API_URL"
# Should be: https://api.inkwell.social
```

### If SSL/certificate issue:
```bash
fly certs list --app inkwell-web
fly certs check inkwell.social --app inkwell-web
```

## Post-Incident
1. Check what caused the issue in `fly logs`
2. If Next.js build broke: run `npx tsc --noEmit` locally to catch type errors
3. Update incident issue with root cause

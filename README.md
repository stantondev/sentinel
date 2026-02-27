# Sentinel

Free, open-source uptime monitoring powered by GitHub Actions. No servers, no cost, no vendor lock-in.

**[View Live Status Dashboard](https://stantondev.github.io/sentinel/)**

## What is this?

Sentinel monitors your websites and APIs every 5 minutes using GitHub Actions. When something goes down:

1. Slack gets an alert within 5 minutes
2. A GitHub Issue is auto-created with details and linked runbooks
3. The status dashboard updates in real-time
4. When it recovers, the issue is auto-closed and Slack gets the all-clear

Total cost: **$0**. Runs entirely on GitHub's free tier.

## Features

- **YAML-driven config** — add endpoints to `config/monitors.yml`
- **Slack alerts** — rich formatted messages for failures and recoveries
- **Auto-incident management** — GitHub Issues created/closed automatically
- **Status dashboard** — GitHub Pages site with uptime bars and incident history
- **Incident runbooks** — pre-written playbooks linked from issue bodies
- **Failure thresholds** — requires 2 consecutive failures before alerting (no flappy alerts)
- **State tracking** — knows the difference between "new incident" and "still down"

## Quick Start (Fork & Configure)

### 1. Fork this repo

### 2. Edit `config/monitors.yml`
Replace the Inkwell endpoints with your own:
```yaml
monitors:
  - name: "My API"
    url: "https://api.example.com/health"
    method: GET
    expected_status: 200
    timeout_ms: 10000
    tags: [api, critical]

  - name: "My Website"
    url: "https://example.com"
    method: GET
    expected_status: 200
    timeout_ms: 15000
    tags: [web]
```

### 3. Add secrets
Go to Settings > Secrets and Variables > Actions:
- `SLACK_WEBHOOK_URL` — your Slack incoming webhook URL
- `MONITOR_API_KEY` — (optional) API key for authenticated health checks

### 4. Enable GitHub Pages
Settings > Pages > Source: Deploy from branch `gh-pages`

### 5. Enable Actions
The monitor workflow runs every 5 minutes automatically.

## Architecture

```
GitHub Actions (every 5 min)
  |
  ├─ scripts/check.sh    → curl each endpoint, write results.json
  ├─ scripts/alert.sh    → post to Slack on failure/recovery
  ├─ GitHub Issues API   → create/update/close incident issues
  └─ gh-pages branch     → update dashboard data (status.json, history.json)
       |
       └─ dashboard/     → static HTML/CSS/JS status page
```

## Project Structure

```
sentinel/
  .github/workflows/
    monitor.yml           # Main monitoring workflow (runs every 5 min)
  config/
    monitors.yml          # Endpoint definitions
    alerting.yml          # Alert channel configuration
  scripts/
    check.sh              # Health check runner
    alert.sh              # Slack alert sender
  dashboard/
    index.html            # Status page
    style.css             # Dark theme styles
    app.js                # Fetches status data, renders UI
  docs/
    runbooks/             # Incident response playbooks
    postmortem-template.md
```

## Status Dashboard

The dashboard is a static site deployed to GitHub Pages. It shows:
- Current status of all monitors (green/red dots)
- Response latency for each endpoint
- 24-hour uptime bars per monitor
- Recent incidents from GitHub Issues

## Alerting

### Slack Messages
Failures show which endpoints are down, their status codes, latency, and error details.
Recoveries show how long the incident lasted.

### GitHub Issues
- Auto-created on new incidents with `[INCIDENT]` prefix
- Labeled with `incident`, `active`, plus monitor tags
- Updated with status comments while the incident is ongoing
- Auto-closed with duration when all monitors recover
- Linked to relevant runbooks in the issue body

## Built with Claude Code

This project was designed and built using [Claude Code](https://claude.com/claude-code) as a learning project for monitoring, alerting, and incident management.

## License

MIT

// Sentinel Status Dashboard
// Fetches status.json + history.json and renders the dashboard.

const REPO_OWNER = 'stantondev';
const REPO_NAME = 'sentinel';

async function fetchJSON(file) {
  try {
    const res = await fetch(file + '?t=' + Date.now());
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

async function fetchIncidents() {
  try {
    const res = await fetch(
      `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues?labels=incident&state=all&per_page=10&sort=created&direction=desc`
    );
    if (!res.ok) return [];
    return await res.json();
  } catch {
    return [];
  }
}

function renderOverallStatus(data) {
  const badge = document.getElementById('overall-status');
  badge.className = 'status-badge ' + data.overall;
  badge.textContent = data.overall === 'healthy' ? 'All Systems Operational' : 'Degraded';
}

function renderMonitors(data) {
  const grid = document.getElementById('monitors');
  grid.innerHTML = data.monitors.map(m => `
    <div class="monitor-card">
      <div class="monitor-info">
        <div class="status-dot ${m.status}"></div>
        <span class="monitor-name">${m.name}</span>
      </div>
      <div class="monitor-meta">
        <span class="latency">${m.latency_ms}ms</span>
        <span>${m.http_code}</span>
      </div>
    </div>
  `).join('');
}

function renderUptime(history) {
  const container = document.getElementById('uptime-bars');

  if (!history || history.length === 0) {
    container.innerHTML = '<div class="no-incidents">No history data yet. Check back after a few runs.</div>';
    return;
  }

  // Group by monitor name, last 288 entries (24h at 5-min intervals)
  const monitorNames = [...new Set(history.flatMap(h => h.monitors.map(m => m.name)))];
  const recent = history.slice(-288);

  container.innerHTML = monitorNames.map(name => {
    const segments = recent.map(h => {
      const monitor = h.monitors.find(m => m.name === name);
      return monitor ? monitor.status : 'unknown';
    });

    const total = segments.filter(s => s !== 'unknown').length;
    const passed = segments.filter(s => s === 'pass').length;
    const pct = total > 0 ? ((passed / total) * 100).toFixed(1) : '—';
    const pctClass = pct >= 99.5 ? 'good' : pct >= 95 ? 'warn' : 'bad';

    // Show last 48 segments (4 hours) for visual bar
    const barSegments = segments.slice(-48);

    return `
      <div class="uptime-row">
        <span class="uptime-label" title="${name}">${name}</span>
        <div class="uptime-bar">
          ${barSegments.map(s => `<div class="uptime-segment ${s}"></div>`).join('')}
        </div>
        <span class="uptime-pct ${pctClass}">${pct}%</span>
      </div>
    `;
  }).join('');
}

function renderIncidents(issues) {
  const container = document.getElementById('incidents');

  if (issues.length === 0) {
    container.innerHTML = '<div class="no-incidents">No incidents in the last 30 days.</div>';
    return;
  }

  container.innerHTML = issues.map(issue => {
    const isActive = issue.state === 'open';
    const date = new Date(issue.created_at).toLocaleDateString('en-US', {
      month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit'
    });

    return `
      <div class="incident-card ${isActive ? 'active' : 'resolved'}">
        <div class="title">
          <a href="${issue.html_url}" target="_blank" style="color: inherit; text-decoration: none;">
            ${issue.title}
          </a>
        </div>
        <div class="meta">
          ${isActive ? 'Active' : 'Resolved'} &mdash; ${date}
        </div>
      </div>
    `;
  }).join('');
}

async function init() {
  const [status, history, incidents] = await Promise.all([
    fetchJSON('status.json'),
    fetchJSON('history.json'),
    fetchIncidents(),
  ]);

  if (status) {
    renderOverallStatus(status);
    renderMonitors(status);
    document.getElementById('last-updated').textContent =
      'Last checked: ' + new Date(status.timestamp).toLocaleString();
  } else {
    document.getElementById('overall-status').textContent = 'No Data';
    document.getElementById('monitors').innerHTML =
      '<div class="loading-placeholder">No status data yet. Waiting for first check run...</div>';
  }

  renderUptime(history);
  renderIncidents(incidents);
}

init();

// Auto-refresh every 5 minutes
setInterval(init, 5 * 60 * 1000);

#!/usr/bin/env bash
# Sentinel Health Check Runner
# Reads monitors.yml, checks each endpoint, outputs JSON results.
# Usage: ./scripts/check.sh [config_file]

set -euo pipefail

CONFIG_FILE="${1:-config/monitors.yml}"
RESULTS_FILE="results.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Parse YAML monitors into a simple format using grep/sed (no yq dependency)
# Each monitor block is extracted and checked individually
parse_monitors() {
  local in_monitor=false
  local name="" url="" method="GET" expected_status="200" expected_body="" timeout_ms="15000" tags="" headers=""
  local in_headers=false

  local results="[]"
  local monitor_count=0

  while IFS= read -r line; do
    # Detect start of a monitor entry
    if echo "$line" | grep -q '^\s*- name:'; then
      # Save previous monitor if we had one
      if [ -n "$name" ]; then
        result=$(check_endpoint "$name" "$url" "$method" "$expected_status" "$expected_body" "$timeout_ms" "$tags" "$headers")
        results=$(echo "$results" | jq --argjson r "$result" '. + [$r]')
        monitor_count=$((monitor_count + 1))
      fi
      name=$(echo "$line" | sed 's/.*name: *"\(.*\)"/\1/')
      url="" method="GET" expected_status="200" expected_body="" timeout_ms="15000" tags="" headers=""
      in_headers=false
    elif echo "$line" | grep -q '^\s*url:'; then
      url=$(echo "$line" | sed 's/.*url: *"\(.*\)"/\1/')
      in_headers=false
    elif echo "$line" | grep -q '^\s*method:'; then
      method=$(echo "$line" | sed 's/.*method: *//')
      in_headers=false
    elif echo "$line" | grep -q '^\s*expected_status:'; then
      expected_status=$(echo "$line" | sed 's/.*expected_status: *//')
      in_headers=false
    elif echo "$line" | grep -q '^\s*expected_body_contains:'; then
      expected_body=$(echo "$line" | sed "s/.*expected_body_contains: *'\(.*\)'/\1/" | sed 's/.*expected_body_contains: *"\(.*\)"/\1/')
      in_headers=false
    elif echo "$line" | grep -q '^\s*timeout_ms:'; then
      timeout_ms=$(echo "$line" | sed 's/.*timeout_ms: *//')
      in_headers=false
    elif echo "$line" | grep -q '^\s*tags:'; then
      tags=$(echo "$line" | sed 's/.*tags: *\[//' | sed 's/\]//' | tr -d ' ')
      in_headers=false
    elif echo "$line" | grep -q '^\s*headers:'; then
      in_headers=true
    elif [ "$in_headers" = true ] && echo "$line" | grep -qE '^\s+[A-Za-z][-A-Za-z0-9]*:'; then
      # Parse header line: "      Key: "value""
      local hdr_key hdr_val
      hdr_key=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/:.*//')
      hdr_val=$(echo "$line" | sed 's/[^:]*: *//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
      # Substitute env vars (e.g., ${MONITOR_API_KEY})
      hdr_val=$(echo "$hdr_val" | sed "s/\${MONITOR_API_KEY}/${MONITOR_API_KEY:-}/g")
      # Append to headers string (pipe-delimited: "Key1: val1|Key2: val2")
      if [ -n "$headers" ]; then
        headers="${headers}|${hdr_key}: ${hdr_val}"
      else
        headers="${hdr_key}: ${hdr_val}"
      fi
    else
      # Any non-header indented line ends the headers block
      if echo "$line" | grep -qE '^\s+[a-z]'; then
        in_headers=false
      fi
    fi
  done < "$CONFIG_FILE"

  # Process last monitor
  if [ -n "$name" ]; then
    result=$(check_endpoint "$name" "$url" "$method" "$expected_status" "$expected_body" "$timeout_ms" "$tags" "$headers")
    results=$(echo "$results" | jq --argjson r "$result" '. + [$r]')
    monitor_count=$((monitor_count + 1))
  fi

  echo "$results"
}

check_endpoint() {
  local name="$1" url="$2" method="$3" expected_status="$4" expected_body="$5" timeout_ms="$6" tags="$7" headers="$8"
  local timeout_sec=$((timeout_ms / 1000))

  # Build curl command
  local curl_args=(-s -o /tmp/sentinel_body -w '%{http_code}\n%{time_total}' --max-time "$timeout_sec" -X "$method")

  # Add all headers (pipe-delimited: "Key1: val1|Key2: val2")
  if [ -n "$headers" ]; then
    IFS='|' read -ra hdr_array <<< "$headers"
    for hdr in "${hdr_array[@]}"; do
      curl_args+=(-H "$hdr")
    done
  fi

  curl_args+=("$url")

  # Execute check
  local start_time=$(date +%s%N 2>/dev/null || date +%s)
  local http_code="" time_total="" body="" status="pass" error=""

  if output=$(curl "${curl_args[@]}" 2>/dev/null); then
    http_code=$(echo "$output" | head -1)
    time_total=$(echo "$output" | tail -1)
    body=$(cat /tmp/sentinel_body 2>/dev/null || echo "")

    # Check status code
    if [ "$http_code" != "$expected_status" ]; then
      status="fail"
      error="Expected status $expected_status, got $http_code"
    fi

    # Check body contains (if specified)
    if [ -n "$expected_body" ] && [ "$status" = "pass" ]; then
      if ! echo "$body" | grep -q "$expected_body"; then
        status="fail"
        error="Response body missing expected content"
      fi
    fi
  else
    status="fail"
    http_code="0"
    time_total="0"
    error="Connection failed or timed out"
  fi

  # Calculate latency in ms
  local latency_ms=$(echo "$time_total * 1000" | bc 2>/dev/null || echo "0")

  # Build JSON result
  jq -n \
    --arg name "$name" \
    --arg url "$url" \
    --arg status "$status" \
    --arg http_code "$http_code" \
    --arg latency_ms "$latency_ms" \
    --arg error "$error" \
    --arg tags "$tags" \
    --arg timestamp "$TIMESTAMP" \
    '{
      name: $name,
      url: $url,
      status: $status,
      http_code: ($http_code | tonumber),
      latency_ms: ($latency_ms | tonumber | round),
      error: (if $error == "" then null else $error end),
      tags: ($tags | split(",") | map(select(. != ""))),
      timestamp: $timestamp
    }'
}

# Run all checks
echo "Sentinel Health Check — $TIMESTAMP"
echo "=================================="

results=$(parse_monitors)

# Count pass/fail
total=$(echo "$results" | jq 'length')
passed=$(echo "$results" | jq '[.[] | select(.status == "pass")] | length')
failed=$(echo "$results" | jq '[.[] | select(.status == "fail")] | length')

echo "Checked $total monitors: $passed passed, $failed failed"
echo ""

# Print individual results
echo "$results" | jq -r '.[] | "\(.status | if . == "pass" then "  \u2705" else "  \u274c" end) \(.name) — \(.http_code) in \(.latency_ms)ms\(if .error then " (\(.error))" else "" end)"'

# Write results file
jq -n \
  --argjson results "$results" \
  --arg timestamp "$TIMESTAMP" \
  --argjson total "$total" \
  --argjson passed "$passed" \
  --argjson failed "$failed" \
  '{
    timestamp: $timestamp,
    total: $total,
    passed: $passed,
    failed: $failed,
    overall: (if $failed > 0 then "degraded" else "healthy" end),
    monitors: $results
  }' > "$RESULTS_FILE"

echo ""
echo "Results written to $RESULTS_FILE"

# Exit with failure if any checks failed
if [ "$failed" -gt 0 ]; then
  exit 1
fi

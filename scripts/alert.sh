#!/usr/bin/env bash
# Sentinel Alert Script
# Sends formatted Slack messages for failures and recoveries.
# Usage: ./scripts/alert.sh <failure|recovery> [results_file]

set -euo pipefail

ACTION="${1:-}"
RESULTS_FILE="${2:-results.json}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

if [ -z "$ACTION" ]; then
  echo "Usage: $0 <failure|recovery> [results_file]"
  exit 1
fi

if [ -z "$SLACK_WEBHOOK_URL" ]; then
  echo "SLACK_WEBHOOK_URL not set, skipping alert"
  exit 0
fi

send_slack() {
  local payload="$1"
  curl -s -X POST "$SLACK_WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    -d "$payload" > /dev/null
}

if [ "$ACTION" = "failure" ]; then
  # Build failure alert from results
  timestamp=$(jq -r '.timestamp' "$RESULTS_FILE")
  failed_monitors=$(jq -r '[.monitors[] | select(.status == "fail")]' "$RESULTS_FILE")
  failed_count=$(echo "$failed_monitors" | jq 'length')
  total=$(jq -r '.total' "$RESULTS_FILE")

  # Build fields for each failed monitor
  fields=""
  while IFS= read -r monitor; do
    name=$(echo "$monitor" | jq -r '.name')
    url=$(echo "$monitor" | jq -r '.url')
    http_code=$(echo "$monitor" | jq -r '.http_code')
    latency=$(echo "$monitor" | jq -r '.latency_ms')
    error=$(echo "$monitor" | jq -r '.error // "Unknown error"')

    fields="$fields
> *$name*
> Status: \`$http_code\` | Latency: \`${latency}ms\`
> Error: $error
> URL: $url
"
  done < <(echo "$failed_monitors" | jq -c '.[]')

  payload=$(jq -n \
    --arg failed_count "$failed_count" \
    --arg total "$total" \
    --arg timestamp "$timestamp" \
    --arg fields "$fields" \
    '{
      blocks: [
        {
          type: "header",
          text: {
            type: "plain_text",
            text: ("\u26a0\ufe0f ALERT: " + $failed_count + " of " + $total + " monitors failing"),
            emoji: true
          }
        },
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: $fields
          }
        },
        {
          type: "context",
          elements: [
            {
              type: "mrkdwn",
              text: ("Sentinel Monitor | " + $timestamp)
            }
          ]
        }
      ]
    }')

  echo "Sending failure alert to Slack ($failed_count monitors down)..."
  send_slack "$payload"

elif [ "$ACTION" = "recovery" ]; then
  timestamp=$(jq -r '.timestamp' "$RESULTS_FILE")
  total=$(jq -r '.total' "$RESULTS_FILE")
  duration="${INCIDENT_DURATION:-unknown}"

  payload=$(jq -n \
    --arg total "$total" \
    --arg timestamp "$timestamp" \
    --arg duration "$duration" \
    '{
      blocks: [
        {
          type: "header",
          text: {
            type: "plain_text",
            text: ("\u2705 RECOVERED: All " + $total + " monitors healthy"),
            emoji: true
          }
        },
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: ("All endpoints responding normally.\nIncident duration: *" + $duration + "*")
          }
        },
        {
          type: "context",
          elements: [
            {
              type: "mrkdwn",
              text: ("Sentinel Monitor | " + $timestamp)
            }
          ]
        }
      ]
    }')

  echo "Sending recovery alert to Slack..."
  send_slack "$payload"

else
  echo "Unknown action: $ACTION (expected 'failure' or 'recovery')"
  exit 1
fi

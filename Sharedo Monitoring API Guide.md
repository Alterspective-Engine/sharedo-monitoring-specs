Sharedo Monitoring & API Guide
This knowledge base article documents the endpoints we discovered, how to call them, what they reveal about system health, and how to authenticate. It also covers workflow (execution engine) diagnostics, recommended checks, collectors, and report generation.

All examples use sanitized values and placeholders. Replace <TOKEN>, <PLAN_EXECUTION_ID>, <STEP_ID>, <VIEW_ID>, and base URLs with your environment.

Authentication
Pattern: Bearer token via Authorization header
Authorization: Bearer <TOKEN>
Obtain a token via your OIDC/IDP flow (client credentials recommended) or run a short Playwright login to mint a session token and reuse it.
Browser-based monitors: use Playwright to log in and call APIs via page.request (no manual token handling).
Core Health Endpoints (GET)
Event Engine Stream Stats

URL: /admin/diagnostics/eventengine/streamStats
Reveals: per-stream connectionCount, backlog, lastKnownEventNumber, lastProcessedEventNumber
Health
Backlog: 0 (or tiny, short-lived spikes)
Lag: lastKnown - lastProcessed == 0
Connections: >= 1 (or your expected concurrency)
Example
curl -s -H "Authorization: Bearer <TOKEN>" \
  https://demo-aus.sharedo.tech/admin/diagnostics/eventengine/streamStats | jq
Indexer Status

URL: /api/indexer/status
Health: HTTP 200 and an "ok/ready" payload
Example
curl -s -H "Authorization: Bearer <TOKEN>" \
  https://demo-aus.sharedo.tech/api/indexer/status | jq
Elasticsearch Status

URL: /api/elasticsearch/status
Health: HTTP 200 and an "ok/green" payload
Example
curl -s -H "Authorization: Bearer <TOKEN>" \
  https://demo-aus.sharedo.tech/api/elasticsearch/status | jq
Identity Server Status

URL: /api/idsrv/status
Health: HTTP 200 and a non-error payload
Example
curl -s -H "Authorization: Bearer <TOKEN>" \
  https://demo-aus.sharedo.tech/api/idsrv/status | jq
Admin Diagnostics Config

URL: /api/admin/diagnostics/config
Reveals: diagnostics/config flags enabled for the environment
Optional Integrations (User-Level)

Calendar Sync: /api/exchange/calendarsync/my/status
InfoTrack: /api/infotrack/my/status
Workflow (Execution Engine) Diagnostics
Active Processes (ListView, read via POST)
List API (paged, read-only)

URL pattern: /api/listview/core-admin-active-processes/<pageSize>/<page>/started/desc/?view=table&withCounts=1
Body pattern:
{
  "additionalParameters": {},
  "filters": [],
  "viewId": "<VIEW_ID>"
}
Response: includes resultCount and an array of rows with data fields (e.g., id (planExecutionId), started, errored, state tooltip, titles/references, commands)
Use: issue by state to get counts (RUNNING, WAITING, STOPPED, ERRORED)
Discover filter values (e.g., states)

URL: /api/listview/filterData/core-admin-active-processes/state/clv-filter-lov/?viewId=<VIEW_ID>
Body: { "config": "{}" }
Filtering by state (ERRORED example)

Body example (note parameters is a JSON string):
{
  "additionalParameters": {},
  "filters": [
    {
      "fieldId": "state",
      "filterId": "clv-filter-lov",
      "config": "{}",
      "parameters": "{\"selectedValues\":[\"ERRORED\"]}"
    }
  ],
  "viewId": "<VIEW_ID>"
}
Plan Details and Step Logs
Execution Plan Detail

URL: /api/executionengine/plans/executing/<PLAN_EXECUTION_ID>
Reveals: planSystemName (use this, not display name), overall state, startTime/endTime, and subProcesses including { systemName, state, executionStepId }
Example
curl -s -H "Authorization: Bearer <TOKEN>" \
  https://demo-aus.sharedo.tech/api/executionengine/plans/executing/<PLAN_EXECUTION_ID> | jq
Step Logs (duration estimation)

URL: /api/executionengine/plans/executing/<PLAN_EXECUTION_ID>/steps/<STEP_ID>/log
Reveals: log entries with logTime, logLevel, logMessage
Step duration (approx): diff between first and last logTime
Mutating/Action Endpoints (do NOT use in health checks)

Retry a step: POST /api/executionengine/plans/executing/<PLAN_EXECUTION_ID>/steps/<STEP_ID>/retry
Cancel visual modeler plan: POST /api/executionengine/visualmodeller/plans/executing/<PLAN_EXECUTION_ID>/cancel
Delete record: DELETE /api/executionengine/plans/executing/<PLAN_EXECUTION_ID>
Failure Signals (Dead Letters)
URL: POST /api/deadLetterManagement/search/
Body (example): { "page": 1, "pageSize": 50 }
Use: total failures and top error reasons; trend and budget
Using the Endpoints
Enumerate current workflows and counts by state
Discover state values via filterData
POST active-processes with a state filter (and withCounts=1) → track resultCount
Enrich plans with type and steps
GET plan detail by id to obtain planSystemName and subProcesses
GET step logs (optional) to estimate slow steps
Detect stuck/errored
Stuck RUNNING: now - started > 30m (tune per env)
Long ERRORED: errored - started > 10m and not resolved in subsequent polls
Compute per-type metrics
Group by planSystemName: counts, mean durations (completed/errored), max step counts, slowest steps
Prometheus & JSONL Metrics
Metrics Server (HTTP)

Script: npm run metrics:server
/metrics (text/plain) exposes:
sharedo_stream_backlog_total
sharedo_stream_lag_streams
sharedo_stream_zero_connections
sharedo_workflows_state_total{state=...}
Env: AUTH_TOKEN, WORKFLOW_ACTIVE_VIEW_ID (or auto via data/viewIds.json)
One-shot Collector (JSONL)

Script: npm run collect:workflows
Appends to data/metrics/workflows-YYYY-MM-DD.jsonl with:
streamStats summary (backlog/lag/zeroConn)
Per-state totals
Enriched plan samples (type, stepCount, a sample step duration)
Looping Collector

Script: npm run collect:workflows:loop -- --interval 60
CSV Export and Rollup

Export CSVs for a day: node src/export_workflows_csv.js --date YYYY-MM-DD
Roll up since date: node src/rollup_workflows.js --since YYYY-MM-DD
Outputs:
history-types.csv (per-day per-type averages)
history-mttr.csv (overall per-type MTTR)
history-mttr-daily.csv (per-day per-type MTTR average and p95)
Example cURL Recipes
streamStats

S=https://demo-aus.sharedo.tech; AUTH="Authorization: Bearer <TOKEN>"
curl -s -H "$AUTH" $S/admin/diagnostics/eventengine/streamStats | jq
Active processes (ERRORED)

BODY='{"additionalParameters":{},"filters":[{"fieldId":"state","filterId":"clv-filter-lov","config":"{}","parameters":"{\\"selectedValues\\":[\\"ERRORED\\"]}"}],"viewId":"<VIEW_ID>"}'
curl -s -H "$AUTH" -H "Content-Type: application/json" \
  -d "$BODY" \
  $S/api/listview/core-admin-active-processes/20/1/started/desc/?view=table&withCounts=1 | jq '.resultCount'
Plan detail & step logs

curl -s -H "$AUTH" $S/api/executionengine/plans/executing/<PLAN_EXECUTION_ID> | jq
curl -s -H "$AUTH" $S/api/executionengine/plans/executing/<PLAN_EXECUTION_ID>/steps/<STEP_ID>/log | jq '.[0, -1]'
Dead letters

curl -s -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"page":1,"pageSize":100}' \
  $S/api/deadLetterManagement/search/ | jq '{total: .total, top:(.items|group_by(.reason)|map({reason:.[0].reason,count:length})|sort_by(-.count)|.[0:5])}'
Client-Friendly Reports
HTML Screenshots + highlights: npm run report:screens → docs/screenshots/session-…/index.html
Metrics HTML snapshot: npm run report:metrics-html → docs/metrics-<timestamp>.html
Endpoint inventory: npm run analyze → docs/endpoints-<timestamp>.md
Workflow diagnostics: npm run report:workflows → docs/workflows-<timestamp>.md
Security Notes
Do not store tokens in the repo. Use CI secrets or a secure vault.
Use read-only, diagnostic endpoints for health checks; avoid mutating actions (retry/cancel/delete).
Redaction: capture tooling redacts sensitive headers and cookie values.
For scheduling examples, alert thresholds, or publishing automation, contact the team — we can wire systemd/service or CI workflows to run collectors, rollups, and regenerate HTML reports nightly
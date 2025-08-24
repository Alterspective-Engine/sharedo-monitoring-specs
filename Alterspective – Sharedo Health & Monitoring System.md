Below is a **complete product & technical specification** for the multi‑tenant **Alterspective – Sharedo Health & Monitoring System** (HMS). It is written for law‑firm deployments and assumes your **Sovereign AI Capsule** (single RTX 5090 to start) operating in a **hybrid (capsule + cloud)** model.

**Document version:** v0.9 (Sydney, 16 Aug 2025)
**Owner:** Alterspective (Platform & AI)
**Audiences:** Delivery, SRE/Ops, Security, Sales, Exec, Client IT

---

## 1) Executive summary

HMS ingests operational telemetry from **Seq** and **Sharedo Admin/Public APIs**, turns it into **real‑time health signals**, and exposes **dashboards, alerting, guided RCA, and AI‑assisted investigation**. It is **multi‑tenant** (client → environment), with strong isolation for law firms. Core outcomes:

* Detect degradations **before** users feel them (lead indicators, not only error spikes).
* Explain **what changed** (config, deployment, index, EE nodes), **where** (env/node/service), and **who** (actor/session) with anchored evidence.
* Provide **post‑incident reports** and **audit analytics** for governance and SOP adherence (e.g., **no config changes in Prod**).
* Offer an **AI Copilot** that can answer “why is MB Prod slow?”, “show the run‑up to this failure”, “who changed notification rules yesterday?”, etc.

---

## 2) Scope

**In‑scope (MVP):**

* Seq ingestion (real‑time + historical backfill), with **24h/48h baselines**, anomaly scoring, and **pattern detectors** (token, HTTP/SendWithRetry, script/plan, heartbeat/restarts).
* Sharedo Admin/Public API polling for **health surfaces**: Event‑Engine connections/backlogs, search indexes, dead letters, monitored email/SMS channels, maintenance plans, active processes, config change history, OAuth links, diagnostics.
* Multi‑tenant data model; per‑tenant dashboards & alerting.
* AI Copilot for natural language investigation (RAG over logs/metrics + runbooks).
* Governance signals: **Prod config changes**, **vNext–UAT–Prod drift**, **runaway plans**.

**Later phases:**

* User journey analytics (session timelines, route performance).
* Proactive capacity recommendations (indexer/EE scaling).
* Auto‑healing playbooks.

**Out of scope (MVP):**

* Mutating Sharedo config.
* Acting on client infrastructure (informational guidance only).

---

## 3) Tenancy & data segregation

* **Tenant = client** (e.g., Maurice Blackburn), **Environment** = vNext, UAT, Prod.
* Strong isolation: each row tagged with `{tenant_id, environment_id}`. **Row‑level security**; per‑tenant encryption keys; per‑tenant S3/Blob prefixes for raw archives.
* UI and API enforce **context pinning** (a user can see only their tenants/environments).
* Time: **store UTC**, display in the tenant’s default zone; Sydney for Alterspective operations by default.

---

## 4) Data sources & integration contracts

### 4.1 Seq (primary)

* API: `POST /api/events/signal` with `X-Seq-ApiKey`, **time‑bounded filters**, chunked windows (≥15 min) to avoid truncation. This matches your existing integrations and backfill strategy. &#x20;
* Parallelism: semaphore‑bounded concurrency (e.g., 4–5 in flight), using the same pattern as your **Parallel SEQ Query Executor**.&#x20;
* **Noise exclusion**: drop Seq’s own API noise
  `not (@Properties.SourceContext like 'Seq.Api%' or @Properties.Group = 'api/events/resources')`.
* **Environment match**: robust LIKE
  `@Properties._Environment like 'Sharedo Maurice Blackburn Prod%'`.

**Key fields used:**
`_Environment, _AppName, _Server/_Node, Level, Timestamp, StatusCode, ElapsedMs/ResponseTime, RequestId, routePattern/RequestPath, ExecutionEngine.* (PlanExecutionId, StepSystemName…), CorrelationId/InternalCorrelationId, _TotalRestartCount, Exception, SourceContext`.

### 4.2 Sharedo front‑end/Admin/Public APIs (read‑only)

Examples (supplied during discovery; auth via Sharedo Identity Bearer tokens):

* Config change history: `/api/listview/config-change-history-extended/...`
* Active processes: `/api/listview/core-admin-active-processes/...`
* Sharedo types & rules: `/api/modeller/sharedoTypes`, `/api/admin/participantSynchronisationRules/all`
* Channels: `/admin/channels-email`, `/admin/channels-sms` (status checks)
* Indexes: `/admin/search-indexes` (index health, backlogs)
* Dead letters: `/admin/dead-letter-management`
* Diagnostics: `/admin/diagnostics-*` (EE, incoming email, notifications, config)
* EE config/services: `/admin/event-engine-config-service`
* Maintenance plans: `/admin/maintenance-plans`
* Users/admin & advisor issues: `/admin/users-all`, **User Advisor issues** count
* OAuth connectors: `/admin/oauth` (unlinked/broken connections)

Polling cadence: **30–120 s** depending on endpoint cost & volatility; delta detection with ETags or `If-Modified-Since` where available. Findings are normalized into **health facets**.

---

## 5) Functional requirements

1. **Real‑time health** (≤60 s lag): event rates, error ratios, HTTP 5xx, token/auth failures, script/plan failures, EE heartbeats/restarts, queue backlogs, index health, channel statuses, DLQs.
2. **Anomaly detection**:

   * Baselines: **24 h** and **48 h** per environment & category.
   * Z‑score/EWMA for counts; **seasonal STL** for cyclicity; **Isolation Forest** for multi‑metric bursts; **Holt‑Winters** for forecasting.
3. **RCA & correlation**: chain events by `PlanExecutionId` and `CorrelationId`; surface likely cause: auth outage vs. downstream 5xx vs. runaway plan vs. index backlog.
4. **Governance**: detect **Prod config edits**, **vNext/UAT drift**, **runaway* plan loops*\* (self‑trigger patterns), **SOP breaches**.
5. **AI Copilot**: NLQ over logs/metrics + runbooks; explainers; “compare this Tuesday 13:50–15:38 AEST to the previous day”.
6. **Post‑incident report** (one click): timeline, top signals, affected services/users, mean time to detect/respond, remediation notes, and SOP flags.
7. **Dashboards**: Exec, Ops, Sharedo Admin, Developer; **per‑tenant/per‑environment**.
8. **Alerting**: e‑mail/Teams/Slack; on‑call routing; severity rules; maintenance windows.

---

## 6) Non‑functional requirements

* **Privacy & compliance:** encryption in transit (TLS 1.2+), at rest (per‑tenant keys), audit logs, access reviews; support AU residency.
* **SLOs:** pipeline availability 99.9%, alert latency p95 < 90 s, data loss < 0.1% for critical streams.
* **Retention:** raw JSONL 30–90 days (compressed), metrics indefinitely (aggregated).
* **Throughput (assumption):** 12 M events/day ≈ \~139 ev/s avg; plan for peak ×5–10.
* **Cost controls:** sampling for verbose categories; tiered retention; roll‑ups.

---

## 7) Architecture (hybrid)

**Capsule (on‑prem, RTX 5090)**

* Real‑time ingestion workers; short‑term cache; inference for anomaly scoring and Copilot when needed offline.
* Local object store (MinIO) for spillover; Postgres for metadata.

**Cloud (Azure or AWS)**

* Durable storage: object store (raw archives), **columnar** analytics (e.g., ClickHouse/Parquet+Athena), **time‑series** roll‑ups, **vector** store (k‑NN) for Copilot recall.
* Scale‑out workers for backfill/reprocessing; model training.
* SSO with firm IdP; IP allowlists.

**Observability:** HMS itself emits health/metrics; SLOs monitored by Ops.

---

## 8) Data pipeline & processing

### 8.1 Ingestion flows

* **Real‑time Seq ingestion** with plan execution analysis and general log processing (your existing module extended).&#x20;
* **Enhanced ingestion via Configuration Manager** supporting dynamic query sets and categories; captures **ALL critical events** rather than just plan executions.&#x20;
* **Historical backfill** in hourly or 15‑min chunks; throttled to protect Seq; same code path as real‑time with time predicates.&#x20;
* **Parallel execution** for wider coverage with a **semaphore‑bounded** aiohttp client (max 5–10 conc.).&#x20;

**Canonical filter skeletons (examples):**

* Critical levels:
  `@Level in ['Error','Fatal'] and @Properties._Environment like '{env}%' and {time} and {noise_excl}`
* Token/auth:
  `(@Message like '%Token handle not found%' or '%Token expired%') and {env} and {time} and {noise_excl}`
* HTTP/downstream:
  `(@Message like '%SendWithRetry%' or '%HttpClient%' or has(@Properties.StatusCode)) and {env} and {time} and {noise_excl}`
* EE heartbeat/restarts:
  `(@Message like '%heartbeat%' or has(@Properties._TotalRestartCount)) and {env} and {time} and {noise_excl}`

Where `{time}` = `@Timestamp >= '{fromZ}' and @Timestamp < '{toZ}'`,
`{noise_excl}` = Seq API exclusion snippet (above).

### 8.2 Normalization & storage

* **Raw events**: JSONL in object store by `{tenant}/{env}/{yyyy}/{mm}/{dd}/`.
* **Relational (Postgres)**:

  * `log_entries` (normalized subset for dashboards & fast queries)
  * `workflow_executions` (from EventEngine plans; updated via upsert)&#x20;
  * `health_facets` (index, DLQ, channels, EE nodes/heartbeats)
  * `config_changes`, `oauth_connectors`, `active_processes`, etc.
* **Columnar (ClickHouse/Parquet)**: long‑term analytics, joins, cohorting.
* **Vector store**: embeddings of messages + metadata for Copilot retrieval.

### 8.3 Derived metrics & baselines

* 1‑min and 5‑min buckets: totals, Error/Fatal, Warnings, 5xx, token failures, SendWithRetry, script exceptions, EE restarts, index backlog, DLQ size.
* Baselines computed **per environment and per category** for **24 h / 48 h** windows, with anomaly scores and trend forecasts.

---

## 9) Detection logic (MVP rules)

**Early‑warning rules (lead indicators):**

* Token errors > **X/min** and **> 3× baseline** for 10 min → **Auth degradation**.
* HTTP 5xx (iManage/Graph/Indexer) > **Y/min** and **increasing slope** → **Downstream outage**.
* EE heartbeat gaps or `_TotalRestartCount` jump → **EE node instability**.
* Search‑index backlog > threshold for 15 min → **User search lag**.
* Incoming‑email **unallocated** count rising → **Email processing fault**.
* **Config change** detected in **Prod** during business hours → **SOP breach** alert (with diff).

**Runaway plan detection:**

* Same plan type triggering **>N** executions per minute AND median inter‑arrival << baseline.
* Plan A updates entity that triggers event B that re‑triggers plan A (detect by correlated entity ids + causal chain of messages).

**Outage classifiers (RCA hints):**

* “Auth, Downstream, Index, EE Capacity, Config Change, Email, Unknown (manual)”.

---

## 10) Dashboards

**Executive:** SLA, incidents this week, MTTR/MTTD, top risks.
**Ops/SRE:** per‑env queue sizes, EE nodes, index health, HTTP 4xx/5xx, token failures, script fails, anomaly ribbons vs 24h/48h baselines.
**Sharedo Admin:** config changes, advisor issues count, OAuth links, channels status, DLQs, maintenance plans.
**Developer:** error traces by correlation/plan, slow routes (`ElapsedMs`), payload samples.

---

## 11) AI Copilot

* Model strategy: cloud LLM (GPT‑class) with **RAG** over recent logs/metrics, and a **capsule‑hosted** small model fallback for sensitive queries/offline use.
* Prompting: bind answers to **cited events** (time, env, node).
* Tools: “pull logs for window X”, “compare with −24 h”, “explain spike drivers”, “list config deltas”.
* Guardrails: no actions; no PII leakage; per‑tenant scoping.

---

## 12) Security & compliance

* **RBAC**: roles for Viewer, Investigator, Admin.
* **Secrets**: Vault/KMS; short‑lived Sharedo tokens; key rotation.
* **Data handling**: redact PII fields at ingest where feasible.
* **Audit**: every query & export logged with user/time/tenant.

---

## 13) Operations

* **Runbooks** per detector class (auth/downstream/index/EE/cfg/email).
* **On‑call**: incident severity ladder; paging rules.
* **Backpressure**: if Seq rate limits, queue windows and reduce chunk size automatically; visible lag indicator.
* **Backfill**: operator‑launched; hourly chunks; guardrails and progress reporting.&#x20;
* **Ingestion health**: capture rate, last ingest timestamp, errors by source. Enhanced ingestion module already exposes stats.&#x20;

---

## 14) Data model (selected)

**log\_entries (core)**

* `timestamp_utc`, `level`, `message`, `app_name`, `environment`, `server_node`, `status_code`, `elapsed_ms`, `route_pattern`, `correlation_id`, `internal_correlation_id`, `plan_execution_id`, `exception`, `tenant_id`, `env_id`, `raw_ref`.

**workflow\_executions** (from EventEngine)

* `plan_execution_id`, `plan_system_name`, `plan_type`, `status`, `start_time`, `end_time`, `duration_ms`, `error_count`, `warning_count`, `completed_steps`, `total_steps`, `environment`, `primary_server_node`, `last_activity`. (Extraction & upsert logic as per your module.)&#x20;

**health\_facets** (examples)

* `facet_type` (index, dlq, email\_channel, ee\_node, oauth\_link, active\_process, maintenance\_plan, advisor\_issue), `value1..n`, `status`, `observed_at`.

---

## 15) APIs (exposed by HMS)

* `GET /tenants/{t}/envs/{e}/kpis?from&to`
* `GET /tenants/{t}/envs/{e}/anomalies?from&to`
* `GET /tenants/{t}/envs/{e}/rca?incidentId=…`
* `POST /tenants/{t}/queries/canned/{name}` (e.g., “compare-with-minus24h”)
* `POST /tenants/{t}/copilot/ask` (tool‑enabled, read‑only)

All endpoints require **tenant‑scoped tokens**; responses include **evidence links** back to HMS or Seq.

---

## 16) Implementation plan

**Phase 0 – Foundation (2–3 weeks)**

* Stand up capsule services; connect to Seq; secrets and RLS; baseline dashboards.
* Port & harden ingestion with **parallel queries** + **noise exclusion**; tests with MB UAT/Prod. &#x20;

**Phase 1 – Health facets & detectors (3–4 weeks)**

* Poll Sharedo Admin APIs; normalize health facets; implement detector rules & baselines (24h/48h).
* Alerting integration; initial AI Copilot with retrieval.

**Phase 2 – Governance & RCA (3–4 weeks)**

* Config‑change diffing; SOP breach detection; runaway plans.
* Post‑incident report automation.

**Phase 3 – UX analytics & forecasting (4 weeks)**

* Route performance and user journeys; capacity forecasts.

---

## 17) Acceptance criteria (MVP)

* Ingest ≥ **95%** of critical events in real‑time; **<0.1%** loss on backfill.
* Alert on token/HTTP/script/EE anomalies within **90 s p95**.
* Detect any **Prod config change** within 60 s.
* Post‑incident report generated within 5 min of incident close.
* Per‑tenant isolation verified; audit trail for every export.

---

## 18) Risks & mitigations

* **Seq rate limiting / burstiness** → chunking, backoff, concurrency caps. &#x20;
* **Schema drift** → dynamic property extraction with tolerant mappers; CM‑driven filters.&#x20;
* **Time‑zone confusion** → always store UTC; UI shows tenant local; manifest checks.
* **Noise pollution** → strict noise‑exclusion filters; environment LIKE.
* **Sensitive data** → redaction, RBAC, audit, encryption.

---

## 19) Commercial model (indicative)

* **Platform fee** per tenant + **environment add‑on**.
* **Ingestion tier** by daily event volume (e.g., up to 10 M/day, 10–25 M/day, 25–50 M/day).
* **Support** tiers: Standard, Enhanced (SLA), Premium (24×7 with on‑call).
* **One‑off onboarding** per tenant (connectors, baselines, dashboards).

---

## 20) What you need from us to start

* Seq endpoint + API keys per tenant/environment; environment **canonical names**.
* Sharedo Identity OAuth client for polling Admin/Public APIs.
* Read‑only DB and S3/Blob buckets (if hosted in client cloud).
* Business hours/maintenance windows per tenant (for alert noise shaping).

---

### Appendix A — Detector thresholds (initial)

* Token errors: **>50/min** and **>3× baseline** for 10 min.
* HTTP 5xx to indexer/Graph/iManage: **>30/min** and rising for 5 min.
* EE `_TotalRestartCount` **Δ≥2** in 30 min, or heartbeat gap **>2 min**.
* Index backlog: **>5k docs** for 15 min.
* Email DLQ or **unallocated** > **100** for 10 min.
  (Refine per tenant after 2–4 weeks of data.)

### Appendix B — Example RCA prompts (Copilot)

* “Compare **12 Aug 13:00–16:00 AEST** vs **11 Aug** for MB Prod and list **lead indicators** 15 min before the error peak.”
* “List **Prod config changes** in the last 24 h and whether matching changes exist in **vNext**.”
* “Show the **causal chain** for plan execution `…PlanExecutionId…`.”

---

### Why this spec is feasible now (ties to your code)

* **Real‑time ingestion & plan extraction** are already implemented in your Seq module; HMS builds on that.&#x20;
* **Dynamic queries** via Configuration Manager allow us to update filters without redeploys.&#x20;
* **Historical backfill** and **chunked time windows** are in place for reliable replay.&#x20;
* **Parallel query execution** is designed and battle‑tested for performance with sane concurrency limits.&#x20;

---

If you’d like, I can turn this into a **delivery plan** with ticket breakdowns (ingestion, facets, detectors, dashboards, Copilot, SRE) and a **client‑facing pitch deck** tailored for law‑firm CIOs.

# Relay — Technical Requirements / Design Document (TRD)

## 1. Technical Objective

Build a backend system that accepts application events over HTTP and reliably delivers them asynchronously to customer-defined HTTP endpoints.

The design should make failure handling, concurrency, data consistency, and observability first-class concerns.

---

## 2. Initial Technology Stack

| Layer | Technology | Why it exists |
|---|---|---|
| Language | TypeScript | Static types and maintainable backend code |
| Runtime | Node.js | Backend runtime and async I/O |
| HTTP framework | Fastify | Lightweight, high-performance API framework |
| Database | PostgreSQL | Durable source of truth and transactional consistency |
| ORM | Prisma | Schema management and typed DB access |
| Queue | BullMQ | Background job processing, retries, delayed jobs |
| Queue state | Redis | Fast job/queue state used by BullMQ and rate limiting |
| Containers | Docker Compose | Reproducible local infrastructure |
| API docs | OpenAPI / Swagger | Discoverable API contract |
| Testing | Vitest | Unit/integration testing |
| Load testing | k6 | Controlled performance experiments |
| Observability | OpenTelemetry | Traces and metrics instrumentation |
| Version control | Git/GitHub | Source control and CI |

### Deliberately excluded from v1

Kafka, Kubernetes, service mesh, cloud-native orchestration, and a multi-region topology.

The architecture should earn those additions through demonstrated requirements.

---

## 3. System Context

```text
                 ┌─────────────────────┐
                 │  External Sender    │
                 │  /events API client  │
                 └──────────┬──────────┘
                            │ HTTPS
                            ▼
                 ┌─────────────────────┐
                 │     Relay API       │
                 │ Node.js + Fastify   │
                 └───────┬───────┬─────┘
                         │       │
                         │       └──────────────┐
                         ▼                      ▼
                  PostgreSQL               Redis/BullMQ
                         │                      │
                         │                      ▼
                         │               Worker Processes
                         │                      │
                         └───────────────┬──────┘
                                         │ HTTPS
                                         ▼
                               Customer Webhook Server
```

---

## 4. Architectural Principles

### 4.1 PostgreSQL is the source of truth

Persistent business state belongs in PostgreSQL.

Redis should not become the authoritative store for events or delivery history.

### 4.2 HTTP ingestion is separate from HTTP delivery

The API accepts and persists an event. A worker performs delivery asynchronously.

### 4.3 Prefer at-least-once processing

The initial system should be designed around the reality that a job may execute more than once.

Do not claim exactly-once delivery.

### 4.4 Preserve history

Delivery attempts should be append-oriented historical records whenever practical. Operational actions such as replay should not destroy evidence of previous failures.

### 4.5 Make failure states explicit

Timeouts, 4xx responses, 5xx responses, queue failures, and process crashes should have observable states and defined recovery behavior.

---

## 5. Logical Components

## 5.1 API Service

Responsibilities:

- authentication
- tenant resolution
- validation
- endpoint management
- event ingestion
- idempotency
- querying delivery state
- replay requests
- admin/operator APIs

The API should not perform outbound webhook delivery synchronously.

---

## 5.2 PostgreSQL

Proposed core tables:

```text
users
organizations
api_keys
webhook_endpoints
webhook_endpoint_secrets
events
deliveries
delivery_attempts
idempotency_keys
audit_logs
```

### Simplified relationships

```text
organization
    │
    ├── api_keys
    ├── webhook_endpoints
    │       └── deliveries
    │               └── delivery_attempts
    │
    └── events
```

---

## 6. Suggested Data Model

### organizations

```text
id                  UUID PK
name                TEXT
created_at          TIMESTAMPTZ
updated_at          TIMESTAMPTZ
```

### api_keys

```text
id                  UUID PK
organization_id     UUID FK
key_hash            TEXT UNIQUE
name                TEXT
last_used_at        TIMESTAMPTZ NULL
revoked_at          TIMESTAMPTZ NULL
created_at          TIMESTAMPTZ
```

Never store raw API keys if hashing can be used safely for verification.

### webhook_endpoints

```text
id                  UUID PK
organization_id     UUID FK
url                 TEXT
status              ENUM
secret_hash         TEXT
created_at          TIMESTAMPTZ
updated_at          TIMESTAMPTZ
```

The system needs access to the secret when generating signatures, so choose an appropriate secret-storage strategy rather than blindly hashing an unrecoverable value. A future production implementation could use encrypted secret storage/KMS.

### events

```text
id                  UUID PK
organization_id     UUID FK
type                TEXT
payload             JSONB
created_at          TIMESTAMPTZ
```

### deliveries

```text
id                  UUID PK
event_id            UUID FK
endpoint_id         UUID FK
status              ENUM
attempt_count       INTEGER
next_attempt_at     TIMESTAMPTZ NULL
created_at          TIMESTAMPTZ
updated_at          TIMESTAMPTZ
```

### delivery_attempts

```text
id                  UUID PK
delivery_id         UUID FK
attempt_number      INTEGER
status              ENUM
response_code       INTEGER NULL
error_code          TEXT NULL
error_message       TEXT NULL
latency_ms          INTEGER NULL
started_at          TIMESTAMPTZ
finished_at         TIMESTAMPTZ NULL
```

### idempotency_keys

```text
id                  UUID PK
organization_id     UUID FK
key                 TEXT
request_hash        TEXT
response_reference UUID
created_at          TIMESTAMPTZ
expires_at          TIMESTAMPTZ NULL

UNIQUE(organization_id, key)
```

Exact schema can evolve during implementation.

---

## 7. Event Ingestion Flow

```text
Client
  │
  │ POST /v1/events
  ▼
API
  │
  ├── authenticate tenant
  ├── validate payload
  ├── check idempotency key
  │
  ▼
PostgreSQL transaction
  │
  ├── insert event
  ├── insert delivery
  └── record idempotency result
  │
  ▼
Queue job
  │
  ▼
HTTP response
```

### Important implementation note

The project should eventually demonstrate a transactional strategy for synchronizing durable event state and queue publication.

For the first implementation, this can begin with a simpler transaction + queue workflow, followed by an explicit outbox phase.

---

## 8. Transactional Outbox

Once the basic system works, introduce an `outbox_events` table.

Example:

```text
BEGIN

INSERT event
INSERT delivery
INSERT outbox_event

COMMIT
```

A relay process reads un-published outbox rows and creates queue jobs.

This addresses the failure window where the database transaction succeeds but the process dies before publishing the job.

### Outbox lifecycle

```text
PENDING
   ↓
PUBLISHED
   ↓
PROCESSED / ARCHIVED
```

The implementation should be idempotent because a publisher can itself encounter crashes and publish more than once.

---

## 9. Queue Architecture

BullMQ queues should separate different work types where justified.

Initial queue:

```text
webhook-delivery
```

Potential later queues:

```text
webhook-retry
endpoint-health
outbox-publisher
```

A delivery job should contain identifiers rather than a large copy of the event payload where possible:

```json
{
  "deliveryId": "del_123"
}
```

The worker loads authoritative event/endpoint information from PostgreSQL.

---

## 10. Worker Design

Worker responsibilities:

```text
1. Receive delivery job
2. Load delivery/event/endpoint
3. Check whether delivery is already complete
4. Mark processing state safely
5. Build signed request
6. Apply timeout
7. Send HTTP request
8. Record attempt result
9. Decide success / retry / dead-letter
10. Schedule next action
```

### Worker concurrency

Make concurrency configurable:

```text
WORKER_CONCURRENCY=20
```

Do not assume increasing concurrency always improves performance. Measure it.

---

## 11. Delivery State Machine

```text
                 ┌─────────────┐
                 │   PENDING   │
                 └──────┬──────┘
                        ▼
                 ┌─────────────┐
                 │ PROCESSING  │
                 └──────┬──────┘
                  ┌─────┴─────┐
                  │           │
                success      failure
                  │           │
                  ▼           ▼
             SUCCEEDED    retryable?
                              │
                         ┌────┴────┐
                        yes        no
                         │          │
                         ▼          ▼
                     RETRYING    FAILED
                         │
                         ▼
                     PROCESSING
                         │
                     attempts exhausted
                         ▼
                  DEAD_LETTERED
```

The exact states can be simplified in code, but the transitions must be explicit.

---

## 12. Retry Strategy

Retryable conditions:

```text
network timeout
connection reset
HTTP 429
HTTP 500-599
```

Non-retryable conditions should be configurable and documented.

Backoff function concept:

```text
backoff(attempt) = min(maxDelay, baseDelay * 2^(attempt-1))
```

Add jitter to reduce synchronized retry spikes.

---

## 13. Idempotency Strategy

For incoming event submission:

```text
organization_id + idempotency_key
```

must be unique.

When a duplicate request arrives:

1. Find the existing idempotency record.
2. Compare the request identity/hash where appropriate.
3. Return the existing result rather than creating another event.

A key reused with a materially different request should be rejected rather than silently accepted.

---

## 14. Outgoing Webhook Signing

Recommended conceptual payload to sign:

```text
{timestamp}.{raw_request_body}
```

Signature:

```text
HMAC-SHA256(secret, signing_input)
```

Headers:

```text
X-Relay-Event-ID
X-Relay-Timestamp
X-Relay-Signature
```

The receiver should reject:

- invalid signatures
- timestamps outside an allowed tolerance
- malformed requests

---

## 15. Rate Limiting

Implement tenant-level rate limiting using Redis.

Possible initial model:

```text
Token Bucket

capacity = configurable
refill rate = configurable
```

Enforce at the event ingestion API.

Later, consider separate limits for:

- API requests
- event creation
- delivery concurrency

---

## 16. Circuit Breaker — Later Phase

Circuit breaker behavior:

```text
CLOSED
  │ repeated failures
  ▼
OPEN
  │ cooldown elapsed
  ▼
HALF_OPEN
  │
  ├── success -> CLOSED
  └── failure -> OPEN
```

This is useful when a customer endpoint remains unhealthy and continued attempts would waste resources.

Do not implement before the core delivery/retry system is correct.

---

## 17. Observability

### Metrics

Track at minimum:

```text
events_ingested_total
deliveries_total
deliveries_succeeded_total
deliveries_failed_total
delivery_latency_ms
queue_depth
retry_count
worker_active_jobs
http_request_duration
```

### Tracing

Trace at least:

```text
HTTP request
  -> PostgreSQL transaction
  -> queue publication
  -> worker execution
  -> outbound HTTP request
```

Trace IDs should allow a single event to be followed through the system.

### Logging

Structured logs should include identifiers such as:

```text
tenant_id
event_id
delivery_id
attempt_id
worker_id
trace_id
```

Do not log secrets or full sensitive payloads unnecessarily.

---

## 18. API Surface

Initial endpoints:

```text
POST   /v1/auth/api-keys
POST   /v1/endpoints
GET    /v1/endpoints
PATCH  /v1/endpoints/:id
DELETE /v1/endpoints/:id

POST   /v1/events
GET    /v1/events/:id
GET    /v1/events

GET    /v1/deliveries/:id
GET    /v1/events/:id/deliveries
POST   /v1/deliveries/:id/replay

GET    /health
GET    /metrics
```

The API should be versioned from the beginning:

```text
/v1/...
```

---

## 19. Project Structure

Suggested monorepo/application structure:

```text
relay/
├── apps/
│   ├── api/
│   ├── worker/
│   └── outbox-relay/
├── packages/
│   ├── db/
│   ├── contracts/
│   ├── config/
│   └── observability/
├── prisma/
├── docker/
├── tests/
├── load-tests/
├── docs/
└── docker-compose.yml
```

The exact structure can be simplified. Do not create packages solely for architectural aesthetics.

---

## 20. Testing Strategy

### Unit tests

Test:

- retry classification
- backoff calculation
- HMAC generation/verification
- idempotency behavior
- delivery state transitions
- rate limiting logic

### Integration tests

Test against real PostgreSQL and Redis containers:

- event ingestion
- queue creation
- worker delivery
- retries
- replay
- persistence

### Failure tests

Explicitly simulate:

- customer returns 500
- customer times out
- worker crashes
- duplicate event submission
- queue connection loss
- database failure

### Load tests

Use k6 to measure:

- ingestion throughput
- p50/p95/p99 latency
- worker throughput
- queue growth
- database saturation

---

## 21. Docker Environment

Local services should include at minimum:

```text
api
worker
outbox-relay
postgres
redis
```

Potential later services:

```text
prometheus
grafana
otel-collector
```

Keep local development one command away from running the whole system:

```bash
docker compose up
```

---

## 22. Technical Risks

### Redis failure

Queue operations can be disrupted. Durable event state must remain in PostgreSQL so the system can recover.

### Duplicate jobs

Workers must be idempotent.

### Worker overload

Concurrency must be bounded and measurable.

### Slow customer endpoints

Use strict outbound timeouts so workers are not blocked indefinitely.

### Retry storms

Use exponential backoff + jitter and eventually dead-letter unhealthy deliveries.

### Database bottlenecks

Use proper indexes, connection pooling, pagination, and measured query optimization.

---

## 23. Advanced Extension: Kafka

Kafka is a later architectural experiment, not an MVP dependency.

A future architecture could be:

```text
API
 ↓
PostgreSQL + Outbox
 ↓
Kafka
 ├── delivery consumer
 ├── analytics consumer
 ├── audit consumer
 └── notification consumer
```

Introduce it only after benchmarking the simpler Redis/BullMQ design and identifying a concrete requirement for durable event streaming or independent consumer groups.

---

## 24. Definition of Technical Success

You should be able to explain and demonstrate:

- why the API and worker are separate
- why PostgreSQL is the source of truth
- why Redis is used
- what happens during worker failure
- how retries work
- why duplicate processing is possible
- how idempotency prevents duplicate event creation
- how the outbox closes the DB/queue consistency gap
- why delivery is at-least-once rather than exactly-once
- how rate limiting protects tenants
- how you measured system performance
- where the bottleneck was and what you changed

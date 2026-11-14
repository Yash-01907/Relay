# Relay — Phased Implementation Plan

## How to Use This Plan

The project is intentionally built from simple to difficult.

**Rule:** Do not add infrastructure because it appears on the final architecture diagram. Add it only when the previous phase creates a concrete requirement for it.

The order is:

```text
Understand -> Basic backend -> Async processing -> Reliability -> Security -> Failure handling -> Observability -> Performance -> Advanced architecture
```

---

# Phase 0 — Understand the Problem

## Goal

Before writing code, understand what Relay is actually solving.

## Learn

- synchronous vs asynchronous processing
- webhook basics
- queues and background workers
- at-least-once processing
- idempotency
- retries and exponential backoff
- database transactions
- failure windows

## Questions you must be able to answer

1. Why shouldn't the API directly call the customer endpoint?
2. Why do we need a queue?
3. Why is PostgreSQL the source of truth?
4. What happens if a worker crashes?
5. What happens if the customer returns 500?
6. What happens if the webhook succeeds but our worker crashes before recording success?
7. Why can duplicate processing happen?
8. What does idempotency solve?

## Exit Criteria

You can draw the basic architecture from memory and explain every arrow.

```text
Client -> API -> PostgreSQL -> Queue -> Worker -> Customer
```

---

# Phase 1 — Repository + Basic API

## Goal

Build a normal backend before introducing distributed-system complexity.

## Build

- TypeScript project
- Fastify
- environment configuration
- Prisma
- PostgreSQL
- Docker Compose
- OpenAPI/Swagger
- error handling
- validation

## Endpoints

```text
POST /v1/endpoints
GET  /v1/endpoints
PATCH /v1/endpoints/:id
POST /v1/events
GET  /v1/events/:id
GET  /health
```

## Database

Start with:

```text
organizations
api_keys
webhook_endpoints
events
```

## Do not build yet

- Kafka
- circuit breaker
- advanced observability
- complicated frontend
- multiple microservices

## Exit Criteria

You can:

```text
create tenant
create endpoint
submit event
persist event
retrieve event
```

---

# Phase 2 — First Working Delivery

## Goal

Actually deliver events to external HTTP endpoints.

## Build

- worker process
- BullMQ
- Redis
- delivery table
- delivery states
- outbound HTTP client
- request timeout

Architecture becomes:

```text
API
 ↓
PostgreSQL
 ↓
BullMQ / Redis
 ↓
Worker
 ↓
Customer endpoint
```

## Important learning

Understand exactly why the API response should not wait for delivery.

## Exit Criteria

When the user submits an event:

```text
POST /events
      ↓
201 Created
      ↓
worker picks job
      ↓
customer receives webhook
```

You can run two workers simultaneously.

---

# Phase 3 — Delivery History

## Goal

Make delivery observable and inspectable.

## Build

Add:

```text
deliveries
delivery_attempts
```

Track:

```text
status
attempt number
response code
latency
error
timestamps
```

## API

```text
GET /v1/events/:id/deliveries
GET /v1/deliveries/:id
```

## Exit Criteria

For any event you can answer:

```text
Was it delivered?
How many times was it attempted?
What did the customer return?
How long did delivery take?
```

---

# Phase 4 — Retry System

## Goal

Handle temporary failures automatically.

## Build

Implement:

- retry classification
- exponential backoff
- maximum attempts
- delayed BullMQ jobs
- jitter

Example:

```text
500
 ↓
retry in 5s
 ↓
500
 ↓
retry in 30s
 ↓
500
 ↓
retry in 2m
 ↓
success
```

## Test

Create a local fake webhook endpoint with configurable behavior:

```text
always 200
always 500
always 429
random failures
slow response
```

## Exit Criteria

You can deliberately break the customer endpoint and watch Relay recover automatically when the endpoint becomes healthy.

---

# Phase 5 — Dead-Letter Queue + Replay

## Goal

Handle events that cannot be delivered after retries.

## Build

States:

```text
RETRYING
   ↓
DEAD_LETTERED
```

Implement:

```text
GET  /v1/dead-letters
POST /v1/deliveries/:id/replay
```

## Design rule

Never erase the historical attempts when replaying.

Replay should produce a new attempt/context while preserving the original history.

## Exit Criteria

Demonstrate:

```text
endpoint returns 500
→ retries exhausted
→ DLQ
→ operator replays
→ endpoint healthy
→ delivery succeeds
```

---

# Phase 6 — Idempotency

## Goal

Prevent duplicate event creation when clients retry requests.

## Build

Support:

```http
Idempotency-Key: abc123
```

Store:

```text
organization_id
idempotency_key
request identity/hash
result reference
```

Enforce:

```text
UNIQUE(organization_id, idempotency_key)
```

## Test

Send the same event request 10 times concurrently with the same idempotency key.

Expected:

```text
1 event
not 10 events
```

## Exit Criteria

You can explain the difference between:

```text
idempotent event ingestion
```

and:

```text
idempotent webhook consumption
```

Both matter, but they solve different problems.

---

# Phase 7 — Transactional Outbox

## Goal

Remove the database/queue consistency gap.

## Problem

This is unsafe:

```text
INSERT event
publish queue job
```

because the process may die between those operations.

## Build

Add:

```text
outbox_events
```

Within one DB transaction:

```text
BEGIN

insert event
insert delivery
insert outbox event

COMMIT
```

Then:

```text
Outbox Relay
   ↓
BullMQ
```

## Test

Simulate a process failure immediately after the transaction commits.

Confirm the outbox can still publish the delivery later.

## Exit Criteria

You can explain exactly which failure window the outbox pattern solves.

---

# Phase 8 — Webhook Security

## Goal

Ensure consumers can verify that requests came from Relay.

## Build

- endpoint secrets
- HMAC SHA-256 signatures
- timestamp header
- event ID header
- verification example for consumers
- replay/timestamp tolerance

## Example

```http
X-Relay-Event-ID: evt_123
X-Relay-Timestamp: 1728123000
X-Relay-Signature: sha256=...
```

## Exit Criteria

Build a tiny sample consumer that rejects:

```text
invalid signature
stale timestamp
modified payload
```

---

# Phase 9 — Rate Limiting + Tenant Isolation

## Goal

Protect the system from noisy tenants.

## Build

Redis-backed rate limiter.

Start with:

```text
N requests / second / tenant
```

Later evaluate separate limits for:

```text
API ingestion
worker concurrency
```

## Test

Create two tenants:

```text
Tenant A -> very high request rate
Tenant B -> normal request rate
```

Confirm A does not consume all API capacity.

## Exit Criteria

You can explain why rate limiting is also a resource-isolation mechanism.

---

# Phase 10 — Failure Engineering

## Goal

Stop testing only the happy path.

Create deliberate failure scenarios.

## Simulate

```text
customer timeout
customer 429
customer 500
customer unavailable
worker crash
Redis unavailable
PostgreSQL unavailable
duplicate job
duplicate event submission
```

## For each failure document

```text
What fails?
What state is persisted?
What is retried?
What is lost?
How does the system recover?
```

## Exit Criteria

You have a written failure matrix and can demonstrate recovery for the important scenarios.

---

# Phase 11 — Observability

## Goal

Make the system diagnosable.

## Build

OpenTelemetry instrumentation for:

```text
API request
DB query/transaction
queue publication
worker execution
outbound HTTP
```

Metrics:

```text
events/sec
queue depth
worker utilization
delivery latency
failure rate
retry count
API p95/p99
```

Structured logs:

```text
tenant_id
event_id
delivery_id
attempt_id
trace_id
```

## Exit Criteria

Intentionally create a slow/failing delivery and use telemetry to identify where the delay/failure occurred.

---

# Phase 12 — Load Testing + Performance Engineering

## Goal

Replace guesses with measurements.

## Tool

k6.

## Experiments

Test increasing load:

```text
1,000 events
10,000 events
100,000 events
```

Measure:

```text
ingestion throughput
p50 latency
p95 latency
p99 latency
worker throughput
queue depth
DB CPU / connections
Redis behavior
```

## Change one variable at a time

Examples:

```text
worker concurrency
DB indexes
connection pool size
batching
payload size
rate limit
```

## Exit Criteria

You have real benchmark numbers and at least one documented performance optimization based on evidence.

Never invent metrics for the resume.

---

# Phase 13 — Circuit Breaker

## Goal

Protect workers from repeatedly unhealthy customer endpoints.

## Build

Implement:

```text
CLOSED
OPEN
HALF_OPEN
```

Track endpoint-level failure rates.

## Test

```text
endpoint down
→ repeated failures
→ circuit opens
→ delivery attempts stop temporarily
→ endpoint recovers
→ half-open probe succeeds
→ circuit closes
```

## Exit Criteria

You can explain why retries alone are insufficient for a persistently failing dependency.

---

# Phase 14 — Architecture Review

## Goal

Step back and decide what should change now that the system exists.

Review:

- bottlenecks
- consistency guarantees
- scaling limits
- failure modes
- operational complexity
- security weaknesses
- database indexes
- queue behavior

Write an architecture decision record for each major change.

Example:

```text
ADR-001: Why BullMQ instead of Kafka in v1
ADR-002: Why PostgreSQL is the source of truth
ADR-003: Why delivery is at-least-once
ADR-004: Why the outbox was introduced
```

## Exit Criteria

You can defend every major architectural choice without saying:

> "Because that's what production systems use."

---

# Phase 15 — Optional Kafka Experiment

## Do this only after Phase 12–14.

## Question to answer

What problem would Kafka solve that BullMQ/Redis does not solve sufficiently for this system?

Possible experiment:

```text
API
 ↓
PostgreSQL + Outbox
 ↓
Kafka
 ├── delivery consumer
 ├── analytics consumer
 └── audit consumer
```

Compare:

```text
BullMQ/Redis
vs
Kafka
```

on:

- delivery model
- consumer groups
- throughput
- operational complexity
- replay semantics
- ordering
- persistence

## Exit Criteria

Kafka is justified by a measured or clearly defined requirement, not by resume keyword collection.

---

# Final Project State

A mature version of Relay should look conceptually like:

```text
                         ┌─────────────────────┐
                         │      API Client     │
                         └──────────┬──────────┘
                                    │
                                    ▼
                         ┌─────────────────────┐
                         │      Relay API      │
                         └──────┬────────┬─────┘
                                │        │
                         PostgreSQL    Redis
                                │        │
                                ▼        ▼
                             Outbox   BullMQ
                                │        │
                                └───┬────┘
                                    ▼
                              Worker Pool
                                    │
                          ┌─────────┴─────────┐
                          ▼                   ▼
                   Customer API A      Customer API B
```

With:

```text
idempotency
retries
backoff + jitter
DLQ
replay
HMAC signing
rate limiting
failure recovery
observability
load testing
```

---

# Recommended Build Order Summary

```text
PHASE 0   Understand problem
   ↓
PHASE 1   Basic API + PostgreSQL
   ↓
PHASE 2   BullMQ + Redis + Worker
   ↓
PHASE 3   Delivery history
   ↓
PHASE 4   Retries
   ↓
PHASE 5   DLQ + Replay
   ↓
PHASE 6   Idempotency
   ↓
PHASE 7   Transactional Outbox
   ↓
PHASE 8   HMAC Security
   ↓
PHASE 9   Rate Limiting
   ↓
PHASE 10  Failure Engineering
   ↓
PHASE 11  Observability
   ↓
PHASE 12  Load Testing
   ↓
PHASE 13  Circuit Breaker
   ↓
PHASE 14  Architecture Review
   ↓
PHASE 15  Optional Kafka
```

The project is considered complete for portfolio purposes after **Phase 12–14**. Phase 15 is an optional advanced extension.

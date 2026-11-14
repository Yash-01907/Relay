# Relay — Product Requirements Document (PRD)

## 1. Product Overview

**Product:** Relay  
**Type:** Developer infrastructure / webhook delivery platform  
**Primary goal:** Reliably accept events from an application and deliver them to registered HTTP endpoints.

Relay is not an e-commerce app, social app, or generic CRUD project. It is a backend infrastructure product whose core problem is reliable asynchronous communication between systems.

### Core value proposition

A developer should be able to send an event to Relay and not have to worry about:

- waiting for the receiving service to respond
- retrying failed deliveries manually
- tracking which deliveries succeeded or failed
- handling duplicate delivery attempts
- replaying failed events
- authenticating webhook requests
- one customer overwhelming the entire platform

---

## 2. Problem Statement

A simple webhook implementation often looks like:

```text
Application -> HTTP POST -> Customer endpoint
```

This breaks down when:

- the customer endpoint is slow
- the customer endpoint is temporarily unavailable
- the sender receives a network timeout after the event was accepted
- the process crashes during delivery
- traffic spikes
- the same event is delivered more than once
- operators need to inspect or replay failed deliveries

Relay separates event ingestion from event delivery and provides reliability mechanisms around the delivery process.

---

## 3. Goals

### Primary goals

1. Accept events through a documented HTTP API.
2. Persist events durably.
3. Deliver events asynchronously through background workers.
4. Retry transient delivery failures using exponential backoff.
5. Track every delivery attempt.
6. Move permanently failed deliveries into a dead-letter queue.
7. Allow failed events to be replayed.
8. Provide idempotency for event creation.
9. Sign outgoing webhook requests with HMAC.
10. Rate-limit tenants so one tenant cannot consume unlimited resources.
11. Provide enough observability to understand system behavior under load.
12. Provide load-test evidence for throughput, latency, and failure handling.

### Secondary goals

- Multiple workers should be able to process deliveries concurrently.
- The system should recover after worker/process failures without losing accepted events.
- The project should be easy to run locally using Docker.
- The architecture should be understandable and defensible in a backend interview.

---

## 4. Non-Goals

The first version will **not** attempt to become a full commercial webhook SaaS.

Explicitly out of scope for the initial build:

- billing/subscriptions
- a public marketplace
- Kubernetes deployment
- multi-region deployment
- global distributed consensus
- exactly-once delivery claims
- Kafka in the first implementation
- a large microservice fleet
- mobile applications
- complex frontend analytics
- enterprise SSO

These can be considered future extensions only after the core system is reliable.

---

## 5. Target Users

### Primary user

A developer building an application that needs to send events to external HTTP services.

### Secondary user

An operator/developer who needs to inspect event deliveries, diagnose failures, and replay events.

---

## 6. Core User Stories

### Event sender

- As a developer, I can create an authenticated API key.
- As a developer, I can register a webhook endpoint.
- As a developer, I can send an event to Relay.
- As a developer, I receive an event ID immediately after Relay accepts the event.
- As a developer, I can use an idempotency key to safely retry an event submission.

### Delivery consumer

- As a receiving service, I receive signed webhook requests.
- As a receiving service, I can identify the exact event using its event ID.
- As a receiving service, I can reject invalid or unauthenticated requests.

### Operator

- As an operator, I can see delivery attempts.
- As an operator, I can see the last response code and error.
- As an operator, I can identify events currently retrying.
- As an operator, I can see events that entered the dead-letter queue.
- As an operator, I can replay a failed delivery.

---

## 7. Product Workflow

```text
1. Developer creates account
2. Developer creates API key
3. Developer registers endpoint
4. Application sends event to Relay
5. Relay validates request
6. Relay stores event
7. Relay creates delivery job
8. API responds to sender
9. Worker consumes delivery job
10. Worker sends signed HTTP request
11. Success -> delivery marked successful
12. Retryable failure -> delivery scheduled for retry
13. Permanent/exhausted failure -> dead-lettered
14. Operator can inspect and replay
```

---

## 8. Functional Requirements

## 8.1 Authentication and Tenancy

Relay must support multiple tenants.

Each tenant must have:

- a unique tenant identity
- one or more API keys
- isolated endpoints
- isolated events
- isolated delivery data

Every protected API request must resolve the tenant before accessing tenant-owned resources.

---

## 8.2 Endpoint Management

Users can:

- create an endpoint
- update an endpoint
- disable an endpoint
- list endpoints
- view endpoint status

Example:

```http
POST /v1/endpoints
```

```json
{
  "url": "https://example.com/webhooks/orders"
}
```

The platform generates or stores a signing secret associated with the endpoint.

---

## 8.3 Event Ingestion

Example:

```http
POST /v1/events
Idempotency-Key: abc123
```

```json
{
  "type": "order.created",
  "data": {
    "orderId": "ord_123",
    "amount": 49999
  }
}
```

Requirements:

- validate request body
- authenticate tenant
- validate idempotency key
- persist event
- create delivery record/job
- return event ID

The API should not wait for the receiving endpoint to respond.

---

## 8.4 Delivery

Every event must create a trackable delivery lifecycle.

Example states:

```text
PENDING
PROCESSING
RETRYING
SUCCEEDED
FAILED
DEAD_LETTERED
```

Each attempt records:

- attempt number
- start time
- completion time
- response status
- latency
- error category
- error message

---

## 8.5 Retry Policy

Transient failures should be retried.

Examples of retryable conditions:

- connection timeout
- connection reset
- 429
- 5xx responses

Permanent failures can include malformed requests or other explicitly non-retryable responses.

The first implementation should use configurable exponential backoff with a maximum number of attempts.

Illustrative policy:

```text
attempt 1 -> immediate
attempt 2 -> +5 seconds
attempt 3 -> +30 seconds
attempt 4 -> +2 minutes
attempt 5 -> +10 minutes
```

Actual values should remain configurable rather than hard-coded into business logic.

---

## 8.6 Dead-Letter Handling

When a delivery exceeds the retry policy:

- mark it as dead-lettered
- preserve all historical attempts
- make it visible to operators
- allow manual replay

Replay should create a new delivery attempt/history entry rather than silently mutating history.

---

## 8.7 Webhook Security

Outgoing requests must include:

- event ID
- timestamp
- HMAC signature

Example headers:

```http
X-Relay-Event-ID: evt_123
X-Relay-Timestamp: 1728123000
X-Relay-Signature: sha256=...
```

Consumers should be able to verify authenticity and reject stale/replayed requests.

---

## 8.8 Rate Limiting

Relay must enforce configurable per-tenant request limits.

The purpose is resource isolation, not just abuse prevention.

A tenant sending an unusually large number of events should not monopolize the API or worker infrastructure.

---

## 8.9 Replay

Operators must be able to replay a dead-lettered or failed delivery.

Example:

```http
POST /v1/deliveries/{deliveryId}/replay
```

Replay must preserve the original event ID while creating a new delivery attempt context.

---

## 8.10 Observability

The system must expose enough information to answer:

- How many events are being processed?
- How many deliveries are failing?
- What is delivery latency?
- How deep is the queue?
- Which endpoints are failing most often?
- Which worker is processing a job?
- Where is an individual event in the lifecycle?

---

## 9. Non-Functional Requirements

### Reliability

Accepted events should not disappear simply because a worker process crashes.

### Performance

Event ingestion should be fast because delivery is asynchronous.

### Scalability

Multiple worker processes should be able to process jobs concurrently.

### Security

Tenant data must be isolated. Secrets must not be returned unnecessarily. Webhook requests must be verifiable.

### Maintainability

Business logic must be separated into clear modules with explicit boundaries.

### Operability

Failures must be visible rather than hidden behind generic `500` responses or console logs.

---

## 10. Success Criteria

The project is successful when a user can demonstrate:

1. Submit an event and receive an event ID immediately.
2. Observe asynchronous delivery.
3. Force a receiving endpoint to return errors.
4. Observe retries with backoff.
5. Exhaust retries and see the delivery enter the dead-letter queue.
6. Replay the failed delivery.
7. Verify webhook signatures.
8. Submit duplicate events with the same idempotency key without creating duplicate event records.
9. Run multiple workers concurrently.
10. Kill a worker during processing and demonstrate recovery.
11. Generate load and show measured system behavior.
12. Inspect traces/metrics to diagnose a failure.

---

## 11. MVP Definition

The MVP ends after these capabilities work correctly:

```text
Authentication
Endpoint registration
Event ingestion
PostgreSQL persistence
BullMQ background delivery
Retry + backoff
Delivery history
Dead-letter handling
Replay
Idempotency
HMAC signatures
Basic rate limiting
Dockerized local environment
```

Kafka, advanced circuit breakers, and sophisticated distributed coordination are **post-MVP**, not prerequisites.

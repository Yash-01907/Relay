-- CreateEnum
CREATE TYPE "OrganizationStatus" AS ENUM ('ACTIVE', 'DELETED', 'SUSPENDED');

-- CreateEnum
CREATE TYPE "EndpointStatus" AS ENUM ('ACTIVE', 'DISABLED');

-- CreateEnum
CREATE TYPE "DeliveryStatus" AS ENUM ('PENDING', 'PROCESSING', 'RETRYING', 'DELIVERED', 'DEAD_LETTERED');

-- CreateEnum
CREATE TYPE "DeliveryAttemptStatus" AS ENUM ('IN_PROGRESS', 'SUCCEEDED', 'FAILED', 'INTERRUPTED');

-- CreateTable
CREATE TABLE "Organization" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "status" "OrganizationStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "Organization_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "WebhookEndpoint" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "url" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "secretEncrypted" TEXT NOT NULL,
    "status" "EndpointStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "WebhookEndpoint_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ApiKey" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "keyHash" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastUsedAt" TIMESTAMPTZ(6),
    "revokedAt" TIMESTAMPTZ(6),

    CONSTRAINT "ApiKey_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Event" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "occurredAt" TIMESTAMPTZ(6),
    "receivedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Event_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "EndpointEventSubscription" (
    "id" UUID NOT NULL,
    "endpointId" UUID NOT NULL,
    "eventType" TEXT NOT NULL,

    CONSTRAINT "EndpointEventSubscription_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Delivery" (
    "id" UUID NOT NULL,
    "eventId" UUID NOT NULL,
    "endpointId" UUID NOT NULL,
    "status" "DeliveryStatus" NOT NULL DEFAULT 'PENDING',
    "attemptCount" INTEGER NOT NULL DEFAULT 0,
    "organizationId" UUID NOT NULL,
    "lastAttemptAt" TIMESTAMPTZ(6),
    "nextAttemptAt" TIMESTAMPTZ(6),
    "deliveredAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "Delivery_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DeliveryAttempt" (
    "id" UUID NOT NULL,
    "deliveryId" UUID NOT NULL,
    "error" TEXT,
    "responseBody" TEXT,
    "status" "DeliveryAttemptStatus" NOT NULL DEFAULT 'IN_PROGRESS',
    "attemptNumber" INTEGER NOT NULL,
    "httpStatusCode" INTEGER,
    "startedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "finishedAt" TIMESTAMPTZ(6),

    CONSTRAINT "DeliveryAttempt_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IdempotencyKey" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "idempotencyKey" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMPTZ(6) NOT NULL,
    "eventId" UUID NOT NULL,
    "requestHash" TEXT NOT NULL,

    CONSTRAINT "IdempotencyKey_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "WebhookEndpoint_organizationId_id_key" ON "WebhookEndpoint"("organizationId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "ApiKey_keyHash_key" ON "ApiKey"("keyHash");

-- CreateIndex
CREATE INDEX "api_key_organization_id_idx" ON "ApiKey"("organizationId");

-- CreateIndex
CREATE INDEX "events_organization_id_idx" ON "Event"("organizationId", "receivedAt");

-- CreateIndex
CREATE UNIQUE INDEX "Event_organizationId_id_key" ON "Event"("organizationId", "id");

-- CreateIndex
CREATE INDEX "endpoint_event_subscription_event_type_idx" ON "EndpointEventSubscription"("eventType");

-- CreateIndex
CREATE UNIQUE INDEX "EndpointEventSubscription_endpointId_eventType_key" ON "EndpointEventSubscription"("endpointId", "eventType");

-- CreateIndex
CREATE INDEX "delivery_status_next_attempt_at_idx" ON "Delivery"("status", "nextAttemptAt");

-- CreateIndex
CREATE INDEX "Delivery_organizationId_eventId_idx" ON "Delivery"("organizationId", "eventId");

-- CreateIndex
CREATE INDEX "Delivery_organizationId_endpointId_idx" ON "Delivery"("organizationId", "endpointId");

-- CreateIndex
CREATE UNIQUE INDEX "Delivery_eventId_endpointId_key" ON "Delivery"("eventId", "endpointId");

-- CreateIndex
CREATE UNIQUE INDEX "DeliveryAttempt_deliveryId_attemptNumber_key" ON "DeliveryAttempt"("deliveryId", "attemptNumber");

-- CreateIndex
CREATE INDEX "IdempotencyKey_organizationId_eventId_idx" ON "IdempotencyKey"("organizationId", "eventId");

-- CreateIndex
CREATE UNIQUE INDEX "IdempotencyKey_organizationId_idempotencyKey_key" ON "IdempotencyKey"("organizationId", "idempotencyKey");

-- AddForeignKey
ALTER TABLE "WebhookEndpoint" ADD CONSTRAINT "WebhookEndpoint_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ApiKey" ADD CONSTRAINT "ApiKey_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Event" ADD CONSTRAINT "Event_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EndpointEventSubscription" ADD CONSTRAINT "EndpointEventSubscription_endpointId_fkey" FOREIGN KEY ("endpointId") REFERENCES "WebhookEndpoint"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Delivery" ADD CONSTRAINT "Delivery_organizationId_eventId_fkey" FOREIGN KEY ("organizationId", "eventId") REFERENCES "Event"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Delivery" ADD CONSTRAINT "Delivery_organizationId_endpointId_fkey" FOREIGN KEY ("organizationId", "endpointId") REFERENCES "WebhookEndpoint"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeliveryAttempt" ADD CONSTRAINT "DeliveryAttempt_deliveryId_fkey" FOREIGN KEY ("deliveryId") REFERENCES "Delivery"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IdempotencyKey" ADD CONSTRAINT "IdempotencyKey_organizationId_eventId_fkey" FOREIGN KEY ("organizationId", "eventId") REFERENCES "Event"("organizationId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

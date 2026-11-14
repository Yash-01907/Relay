To enforce database-level check that event and endpoint exists for the same organization when creating a delivery, we need to set it as a foreign key in delivery schema.

For any column or group of columns to be set as foreign key in a table, that column or group of columns should also exist in the parent table.

Therefore first created a unique column of `organizationId` and `eventId` in events table and `organizationId` and `endpointId` in webhooks tables using `@@unique([organizationId,eventId])` and set that table as foreign key in delivery table.

---

While creating foreign keys in Prisma we have to make 2 way contract.

For ex in child table we have a foreign key referencing to organization table named `organizationId` then in event table we have to write:

`organization Organization @relation(fields;[organizationId], references;[id])`

(Table datatype relation)

But we also need to write `events Event[]` in parent table (Organization). This is purely for TypeScript to help suggest columns, it does not create a table in DB.
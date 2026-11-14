To inforce database level check that event and endpoint exists for the same organization when creating a delivery , we need to set it as a foreign key in delivery schema. 
For any column or group of columns to be set as foreign key in a table, that  column or group of columns should also exists in the parent table.
There fore first created a unique column of organizationId and eventId in events table and organizaiton id and endpointId in webhooks tables using @@unique([organizationId,eventId]) and set that table as foreign key in delievery table


while creating foreign keys in prisma we have to make 2 way contract. For ex in child table we have a foreign key referencing to organization table named organizationId then in event table we have to write 
organization Organization @relation(fields;[organizationId], references;[id])
(table datatype relation)
but we also need to write events Event[] in parent table (Organization) this is purely for typescript to help suggest columns , it does not create a table in db
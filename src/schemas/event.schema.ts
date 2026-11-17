import {z} from "zod";

export const eventSchema = z.object({
    type: z.string().min(1, { message: "Type is required" }),
    payload: z.record(z.string(),z.unknown()),
    occuredAt: z.iso.datetime().optional()
})

export type EventInput = z.infer<typeof eventSchema>;
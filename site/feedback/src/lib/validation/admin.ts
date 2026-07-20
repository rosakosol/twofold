import { z } from "zod";
import { featureStatusSchema } from "@/lib/validation/feature";

export const updateStatusSchema = z.object({
  status: featureStatusSchema,
});

export const mergeRequestSchema = z.object({
  sourceId: z.string().uuid(),
  targetId: z.string().uuid(),
});

export const developerUpdateSchema = z.object({
  body: z
    .string()
    .trim()
    .min(1, "Update can't be empty.")
    .max(4000, "Update can't be longer than 4000 characters."),
});

export type UpdateStatusInput = z.infer<typeof updateStatusSchema>;
export type MergeRequestInput = z.infer<typeof mergeRequestSchema>;
export type DeveloperUpdateInput = z.infer<typeof developerUpdateSchema>;

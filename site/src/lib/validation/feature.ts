import { z } from "zod";
import { CATEGORY_VALUES, STATUS_VALUES } from "@/lib/utils/constants";

export const featureCategorySchema = z.enum(CATEGORY_VALUES);
export const featureStatusSchema = z.enum(STATUS_VALUES);

export const createFeatureRequestSchema = z.object({
  title: z
    .string()
    .trim()
    .min(3, "Title needs to be at least 3 characters.")
    .max(140, "Title can't be longer than 140 characters."),
  description: z
    .string()
    .trim()
    .max(4000, "Description can't be longer than 4000 characters.")
    .default(""),
  category: featureCategorySchema,
});

export type CreateFeatureRequestInput = z.infer<typeof createFeatureRequestSchema>;

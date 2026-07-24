import { z } from "zod";

export const createCommentSchema = z.object({
  body: z
    .string()
    .trim()
    .min(1, "Comment can't be empty.")
    .max(4000, "Comment can't be longer than 4000 characters."),
});

export type CreateCommentInput = z.infer<typeof createCommentSchema>;

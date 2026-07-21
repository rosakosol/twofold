"use client";

import { useEffect, useState } from "react";
import { useRouter, usePathname } from "next/navigation";
import { toast } from "sonner";
import { Plus, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { DuplicateSuggestions } from "@/components/feedback/DuplicateSuggestions";
import { useUser } from "@/lib/auth/useUser";
import { useCreateFeature } from "@/lib/queries/useCreateFeature";
import { useDuplicateSearch } from "@/lib/queries/useDuplicateSearch";
import { createFeatureRequestSchema } from "@/lib/validation/feature";
import { isTypingTarget } from "@/lib/utils/keyboard";
import { CATEGORY_LABELS, CATEGORY_VALUES, type FeatureCategory } from "@/lib/utils/constants";

export function FeatureSubmitDialog() {
  const { user } = useUser();
  const router = useRouter();
  const pathname = usePathname();
  const createFeature = useCreateFeature();

  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [debouncedTitle, setDebouncedTitle] = useState("");
  const [description, setDescription] = useState("");
  const [category, setCategory] = useState<FeatureCategory | "">("");
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [confirmedNotDuplicate, setConfirmedNotDuplicate] = useState(false);

  useEffect(() => {
    const timeout = setTimeout(() => setDebouncedTitle(title), 300);
    return () => clearTimeout(timeout);
  }, [title]);

  // Changing the title after already confirming should re-check for duplicates —
  // don't let a stale confirmation carry over to a materially different title.
  useEffect(() => {
    setConfirmedNotDuplicate(false);
  }, [debouncedTitle]);

  const duplicates = useDuplicateSearch(debouncedTitle);
  const showDuplicates = !confirmedNotDuplicate && (duplicates.data?.length ?? 0) > 0;

  function reset() {
    setTitle("");
    setDebouncedTitle("");
    setDescription("");
    setCategory("");
    setErrors({});
    setConfirmedNotDuplicate(false);
  }

  function handleOpenChange(next: boolean) {
    if (!user && next) {
      router.push(`/auth/sign-in?next=${encodeURIComponent(pathname)}`);
      return;
    }
    setOpen(next);
    if (!next) reset();
  }

  // "c" opens the compose dialog from anywhere on the board, same convention as
  // GitHub's "create issue" shortcut.
  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key !== "c" || event.metaKey || event.ctrlKey || event.altKey) return;
      if (isTypingTarget(event.target)) return;
      event.preventDefault();
      handleOpenChange(true);
    }
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user]);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!user || showDuplicates) return;

    const result = createFeatureRequestSchema.safeParse({ title, description, category });
    if (!result.success) {
      const fieldErrors: Record<string, string> = {};
      for (const issue of result.error.issues) {
        fieldErrors[String(issue.path[0])] = issue.message;
      }
      setErrors(fieldErrors);
      return;
    }
    setErrors({});

    try {
      const created = await createFeature.mutateAsync({ input: result.data, userId: user.id });
      toast.success("Feature request submitted");
      setOpen(false);
      reset();
      router.push(`/feedback/${created.slug}`);
    } catch {
      toast.error("Something went wrong — try again.");
    }
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger
        render={
          <Button>
            <Plus className="h-4 w-4" />
            New request
            <kbd className="ml-1 rounded border border-primary-foreground/30 px-1.5 py-0.5 text-[10px] opacity-70">
              c
            </kbd>
          </Button>
        }
      />
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Request a feature</DialogTitle>
            <DialogDescription>
              What would make Twofold better? Be specific — it helps other couples find and
              upvote the same idea instead of creating a duplicate.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4 py-4">
            <div className="space-y-1.5">
              <Label htmlFor="title">Title</Label>
              <Input
                id="title"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder="e.g. Spotify integration for shared playlists"
                maxLength={140}
              />
              {errors.title && <p className="text-sm text-destructive">{errors.title}</p>}
            </div>

            {showDuplicates ? (
              <DuplicateSuggestions
                items={duplicates.data ?? []}
                onConfirmNotDuplicate={() => setConfirmedNotDuplicate(true)}
              />
            ) : (
              <>
                <div className="space-y-1.5">
                  <Label htmlFor="category">Category</Label>
                  <Select value={category} onValueChange={(v) => setCategory(v as FeatureCategory)}>
                    <SelectTrigger id="category" className="w-full">
                      <SelectValue placeholder="Choose a category" />
                    </SelectTrigger>
                    <SelectContent>
                      {CATEGORY_VALUES.map((value) => (
                        <SelectItem key={value} value={value}>
                          {CATEGORY_LABELS[value]}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {errors.category && <p className="text-sm text-destructive">{errors.category}</p>}
                </div>

                <div className="space-y-1.5">
                  <Label htmlFor="description">Description</Label>
                  <Textarea
                    id="description"
                    value={description}
                    onChange={(e) => setDescription(e.target.value)}
                    placeholder="What problem does this solve? How would it work?"
                    rows={4}
                  />
                  {errors.description && <p className="text-sm text-destructive">{errors.description}</p>}
                </div>
              </>
            )}
          </div>

          {!showDuplicates && (
            <DialogFooter>
              <Button type="submit" disabled={createFeature.isPending}>
                {createFeature.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
                Submit request
              </Button>
            </DialogFooter>
          )}
        </form>
      </DialogContent>
    </Dialog>
  );
}

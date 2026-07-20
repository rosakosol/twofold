"use client";

import { use, useEffect, useState } from "react";
import Link from "next/link";
import { toast } from "sonner";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { DeveloperUpdateComposer } from "@/components/admin/DeveloperUpdateComposer";
import { useAdminFeature } from "@/lib/queries/useAdminFeatures";
import { useUpdateFeatureDetails } from "@/lib/queries/useAdminMutations";
import { CATEGORY_LABELS, CATEGORY_VALUES, type FeatureCategory } from "@/lib/utils/constants";

export default function AdminEditFeaturePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const { data: feature, isLoading } = useAdminFeature(id);
  const updateDetails = useUpdateFeatureDetails(id);

  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [category, setCategory] = useState<FeatureCategory | "">("");

  useEffect(() => {
    if (feature) {
      setTitle(feature.title);
      setDescription(feature.description);
      setCategory(feature.category as FeatureCategory);
    }
  }, [feature]);

  async function handleSave() {
    if (!category) {
      toast.error("Choose a category first.");
      return;
    }
    try {
      await updateDetails.mutateAsync({ title, description, category });
      toast.success("Saved");
    } catch {
      toast.error("Couldn't save changes.");
    }
  }

  if (isLoading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }

  if (!feature) {
    return <p className="text-sm text-muted-foreground">Request not found.</p>;
  }

  return (
    <div>
      <Link href="/admin" className="text-sm text-muted-foreground hover:text-foreground">
        ← Back to admin
      </Link>

      <h1 className="mt-4 text-xl font-semibold tracking-tight">Edit request</h1>

      <div className="mt-6 max-w-lg space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="title">Title</Label>
          <Input id="title" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={140} />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="category">Category</Label>
          <Select value={category} onValueChange={(v) => setCategory(v as FeatureCategory)}>
            <SelectTrigger id="category" className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {CATEGORY_VALUES.map((value) => (
                <SelectItem key={value} value={value}>
                  {CATEGORY_LABELS[value]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="description">Description</Label>
          <Textarea id="description" value={description} onChange={(e) => setDescription(e.target.value)} rows={5} />
        </div>

        <Button onClick={handleSave} disabled={updateDetails.isPending}>
          {updateDetails.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
          Save changes
        </Button>
      </div>

      <Separator className="my-8" />

      <div className="max-w-lg">
        <h2 className="text-sm font-semibold">Post a developer update</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Visible to everyone, and notifies voters/subscribers once notifications are wired up.
        </p>
        <div className="mt-4">
          <DeveloperUpdateComposer featureId={feature.id} />
        </div>
      </div>
    </div>
  );
}

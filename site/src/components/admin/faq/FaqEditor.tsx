"use client";

import { useMemo, useState } from "react";
import { toast } from "sonner";
import { Pencil, Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { ConsoleEmpty, ConsoleError } from "@/components/console/ConsoleUI";
import { describeDbError } from "@/lib/supabase/dbError";
import {
  useCreateFaqEntry,
  useDeleteFaqEntry,
  useFaqEntries,
  useUpdateFaqEntry,
  type FaqEntryRow,
} from "@/lib/queries/useFaqEntries";

const NO_CATEGORY = "(no category)";

/** Grouped the way /faq and the app group them: by category, in the order of each group's first
 *  (lowest sort_order) entry. See groupFaqEntriesByCategory in lib/marketing/faq.ts. */
function groupByCategory(rows: FaqEntryRow[]): [string, FaqEntryRow[]][] {
  const groups = new Map<string, FaqEntryRow[]>();
  for (const row of rows) {
    const key = row.category ?? NO_CATEGORY;
    const list = groups.get(key);
    if (list) list.push(row);
    else groups.set(key, [row]);
  }
  return Array.from(groups.entries());
}

function DeleteButton({ row }: { row: FaqEntryRow }) {
  const [open, setOpen] = useState(false);
  const del = useDeleteFaqEntry();

  async function handleConfirm() {
    try {
      await del.mutateAsync(row.id);
      toast.success("Deleted");
      setOpen(false);
    } catch (error) {
      toast.error(describeDbError(error, "Couldn't delete this entry."));
    }
  }

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogTrigger
        render={
          <Button
            variant="ghost"
            size="icon-sm"
            className="text-muted-foreground hover:text-destructive"
            aria-label={`Delete "${row.question}"`}
          >
            <Trash2 className="h-4 w-4" aria-hidden />
          </Button>
        }
      />
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Delete this question?</AlertDialogTitle>
          <AlertDialogDescription>
            &ldquo;{row.question}&rdquo; comes off the website&apos;s FAQ and the app&apos;s Support screen. This can&apos;t be
            undone.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction
            onClick={handleConfirm}
            disabled={del.isPending}
            className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
          >
            Delete
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

function FaqForm({
  editingRow,
  categories,
  open,
  onOpenChange,
}: {
  editingRow: FaqEntryRow | null;
  categories: string[];
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const create = useCreateFaqEntry();
  const update = useUpdateFaqEntry();
  const [category, setCategory] = useState("");
  const [question, setQuestion] = useState("");
  const [answer, setAnswer] = useState("");
  const [sortOrder, setSortOrder] = useState("0");

  // Seeded during render, keyed on the row, as ContentForm does: an effect would paint one frame
  // of the previous row's values as the sheet opens.
  const seedKey = open ? (editingRow?.id ?? "new") : null;
  const [seededKey, setSeededKey] = useState<string | null>(null);
  if (seedKey !== seededKey) {
    setSeededKey(seedKey);
    if (seedKey) {
      setCategory(editingRow?.category ?? "");
      setQuestion(editingRow?.question ?? "");
      setAnswer(editingRow?.answer ?? "");
      setSortOrder(String(editingRow?.sort_order ?? 0));
    }
  }

  const canSave = question.trim() !== "" && answer.trim() !== "";
  const isSaving = create.isPending || update.isPending;

  async function handleSave() {
    const row = {
      category: category.trim() || null,
      question: question.trim(),
      answer: answer.trim(),
      sort_order: Number.parseInt(sortOrder, 10) || 0,
    };
    try {
      if (editingRow) {
        await update.mutateAsync({ id: editingRow.id, patch: row });
        toast.success("Saved");
      } else {
        await create.mutateAsync(row);
        toast.success("Added");
      }
      onOpenChange(false);
    } catch (error) {
      toast.error(describeDbError(error, "Couldn't save. Check the fields and try again."));
    }
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="flex flex-col overflow-y-auto">
        <SheetHeader>
          <SheetTitle>{editingRow ? "Edit question" : "New question"}</SheetTitle>
          <SheetDescription>Shows on the website&apos;s FAQ and in the app&apos;s Support screen.</SheetDescription>
        </SheetHeader>

        <div className="flex flex-col gap-4 px-4">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="faq-category">Category</Label>
            <Input
              id="faq-category"
              list="faq-categories"
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              placeholder="e.g. Getting started"
            />
            {/* The category is a display label that both the site and the app group on as typed, so
                "Billing" and "billing" are two groups. Offering the existing ones avoids that. */}
            <datalist id="faq-categories">
              {categories.map((c) => (
                <option key={c} value={c} />
              ))}
            </datalist>
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="faq-question">Question</Label>
            <Input id="faq-question" value={question} onChange={(e) => setQuestion(e.target.value)} />
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="faq-answer">Answer</Label>
            <Textarea id="faq-answer" value={answer} onChange={(e) => setAnswer(e.target.value)} rows={8} />
            <p className="text-xs text-muted-foreground">
              Line breaks become paragraphs. Use a plain hyphen, not an em or en dash.
            </p>
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="faq-sort">Sort order</Label>
            <Input
              id="faq-sort"
              type="number"
              inputMode="numeric"
              value={sortOrder}
              onChange={(e) => setSortOrder(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              Lower shows first. A category sits where its lowest entry does.
            </p>
          </div>
        </div>

        <SheetFooter>
          <Button onClick={handleSave} disabled={!canSave || isSaving}>
            {isSaving ? "Saving…" : "Save"}
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}

export function FaqEditor() {
  const query = useFaqEntries();
  const [editingRow, setEditingRow] = useState<FaqEntryRow | null>(null);
  const [formOpen, setFormOpen] = useState(false);

  const rows = useMemo(() => query.data ?? [], [query.data]);
  const grouped = useMemo(() => groupByCategory(rows), [rows]);
  const categories = useMemo(
    () => Array.from(new Set(rows.map((r) => r.category).filter((c): c is string => Boolean(c)))),
    [rows]
  );

  function openForm(row: FaqEntryRow | null) {
    setEditingRow(row);
    setFormOpen(true);
  }

  if (query.isLoading) return <Skeleton className="h-64 w-full rounded-lg" />;
  if (query.isError) return <ConsoleError title="The FAQ didn't load" onRetry={() => void query.refetch()} />;

  return (
    <div>
      <div className="mb-3 flex items-center justify-between">
        <p className="text-sm text-muted-foreground">{rows.length} questions</p>
        <Button size="sm" onClick={() => openForm(null)}>
          <Plus className="h-4 w-4" aria-hidden /> New question
        </Button>
      </div>

      {rows.length === 0 ? (
        <ConsoleEmpty title="No questions yet">
          The website is showing its built-in copy until there are some.
        </ConsoleEmpty>
      ) : (
        <div className="flex flex-col gap-6">
          {grouped.map(([category, entries]) => (
            <section key={category}>
              <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">{category}</h2>
              <div className="console-table-wrap">
                <table className="console-table">
                  <thead>
                    <tr>
                      <th scope="col">Question</th>
                      <th scope="col" className="num">
                        Order
                      </th>
                      <th scope="col">
                        <span className="sr-only">Actions</span>
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {entries.map((row) => (
                      <tr key={row.id}>
                        <td className="max-w-[40rem]">
                          <span className="block font-medium">{row.question}</span>
                          <span className="mt-1 line-clamp-2 text-sm text-muted-foreground">{row.answer}</span>
                        </td>
                        <td className="num muted">{row.sort_order}</td>
                        <td>
                          <div className="flex items-center justify-end gap-1">
                            <Button
                              variant="ghost"
                              size="icon-sm"
                              className="text-muted-foreground"
                              aria-label={`Edit "${row.question}"`}
                              onClick={() => openForm(row)}
                            >
                              <Pencil className="h-4 w-4" aria-hidden />
                            </Button>
                            <DeleteButton row={row} />
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          ))}
        </div>
      )}

      <FaqForm editingRow={editingRow} categories={categories} open={formOpen} onOpenChange={setFormOpen} />
    </div>
  );
}

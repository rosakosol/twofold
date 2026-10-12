"use client";

import { useState } from "react";
import { toast } from "sonner";
import { BookmarkPlus, FileText, Loader2, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { createClient } from "@/lib/supabase/client";

interface Macro {
  id: string;
  title: string;
  body: string;
}

/** `{{name}}` becomes the correspondent's first name, or "there" when we don't have one, so a
 * template reads "Hi there," rather than "Hi {{name}}," or "Hi ,". */
export function fillMacro(body: string, name: string | null): string {
  const first = name?.trim().split(/\s+/)[0];
  return body.replaceAll("{{name}}", first || "there");
}

/**
 * Saved replies for the support composer: pick one to put it in the reply box, where it is edited
 * like anything typed by hand before it is sent; save what is in the box as a new one; delete the
 * ones that are no longer right. Editing a saved reply is insert, change, save as new, delete the
 * old: one way to do it rather than an editor beside the editor.
 */
export function SupportMacros({
  currentBody,
  recipientName,
  onInsert,
  disabled,
}: {
  currentBody: string;
  recipientName: string | null;
  onInsert: (text: string) => void;
  disabled: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [macros, setMacros] = useState<Macro[] | null>(null);
  const [newTitle, setNewTitle] = useState("");
  const [saving, setSaving] = useState(false);

  async function load() {
    const supabase = createClient();
    const { data, error } = await supabase
      .from("support_macros")
      .select("id, title, body")
      .order("title", { ascending: true });
    if (error) {
      toast.error("Couldn't load saved replies.");
      setMacros([]);
      return;
    }
    setMacros(data as Macro[]);
  }

  async function saveCurrent() {
    const title = newTitle.trim();
    if (!title || currentBody.trim().length < 2) return;
    setSaving(true);
    const supabase = createClient();
    const { error } = await supabase.from("support_macros").insert({ title, body: currentBody.trim() });
    setSaving(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success(`Saved "${title}".`);
    setNewTitle("");
    await load();
  }

  async function remove(macro: Macro) {
    const supabase = createClient();
    const { error } = await supabase.from("support_macros").delete().eq("id", macro.id);
    if (error) {
      toast.error(error.message);
      return;
    }
    setMacros((list) => list?.filter((m) => m.id !== macro.id) ?? null);
  }

  return (
    <Popover
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        // Loaded the first time it opens, not with every conversation: most replies don't use one.
        if (next && macros === null) void load();
      }}
    >
      <PopoverTrigger
        render={
          <button
            type="button"
            disabled={disabled}
            className="inline-flex items-center gap-1.5 rounded-md px-1.5 py-1 text-xs text-muted-foreground hover:bg-accent hover:text-foreground disabled:opacity-50"
          >
            <FileText className="h-3.5 w-3.5" />
            Saved replies
          </button>
        }
      />
      <PopoverContent align="start" className="w-80">
        {macros === null ? (
          <div className="flex justify-center py-4">
            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
          </div>
        ) : macros.length === 0 ? (
          <p className="px-1 text-xs text-muted-foreground">No saved replies yet.</p>
        ) : (
          <ul className="max-h-64 space-y-0.5 overflow-y-auto">
            {macros.map((macro) => (
              <li key={macro.id} className="group flex items-center gap-1">
                <button
                  type="button"
                  className="min-w-0 flex-1 rounded-md px-2 py-1.5 text-left hover:bg-accent"
                  onClick={() => {
                    onInsert(fillMacro(macro.body, recipientName));
                    setOpen(false);
                  }}
                >
                  <span className="block truncate text-sm">{macro.title}</span>
                  <span className="block truncate text-xs text-muted-foreground">{macro.body}</span>
                </button>
                <button
                  type="button"
                  aria-label={`Delete "${macro.title}"`}
                  className="rounded-md p-1.5 text-muted-foreground opacity-0 hover:text-destructive group-hover:opacity-100 focus:opacity-100"
                  onClick={() => void remove(macro)}
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              </li>
            ))}
          </ul>
        )}

        <div className="border-t pt-2.5">
          <p className="mb-1.5 px-1 text-xs text-muted-foreground">
            Save what&apos;s in the reply box. Write <code>{"{{name}}"}</code> where their first name goes.
          </p>
          <div className="flex gap-1.5">
            <Input
              value={newTitle}
              placeholder="Title"
              onChange={(e) => setNewTitle(e.target.value)}
              className="h-8 text-sm"
              maxLength={80}
            />
            <Button
              size="sm"
              variant="outline"
              disabled={saving || !newTitle.trim() || currentBody.trim().length < 2}
              onClick={saveCurrent}
            >
              {saving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <BookmarkPlus className="h-3.5 w-3.5" />}
              Save
            </Button>
          </div>
        </div>
      </PopoverContent>
    </Popover>
  );
}

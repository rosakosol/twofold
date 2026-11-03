import { describe, expect, it, vi } from "vitest";
import { createAuthStore, type AuthSource } from "./authStore";

type Listener = (event: string, session: { user: { id: string } } | null) => void;

function fakeAuth(user: { id: string } | null = { id: "u1" }) {
  let listener: Listener | null = null;
  const unsubscribe = vi.fn();
  const source = {
    getUser: vi.fn(async () => ({ data: { user } })),
    onAuthStateChange: vi.fn((cb: Listener) => {
      listener = cb;
      return { data: { subscription: { unsubscribe } } };
    }),
  };
  return { source: source as unknown as AuthSource, raw: source, emit: (s: { user: { id: string } } | null) => listener?.("SIGNED_IN", s) };
}

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("createAuthStore", () => {
  it("asks Supabase Auth once however many components read it", async () => {
    // One VoteButton per request card used to mean one auth.getUser() round trip, and one
    // onAuthStateChange listener, per card.
    const { source, raw } = fakeAuth();
    const store = createAuthStore(source);
    for (let i = 0; i < 25; i++) store.subscribe(() => {});
    await flush();
    expect(raw.getUser).toHaveBeenCalledTimes(1);
    expect(raw.onAuthStateChange).toHaveBeenCalledTimes(1);
  });

  it("starts loading, then has the user", async () => {
    const { source } = fakeAuth({ id: "u1" });
    const store = createAuthStore(source);
    expect(store.getSnapshot()).toEqual({ user: null, isLoading: true });
    store.subscribe(() => {});
    await flush();
    expect(store.getSnapshot()).toEqual({ user: { id: "u1" }, isLoading: false });
  });

  it("tells every subscriber about a sign-in or sign-out", async () => {
    const { source, emit } = fakeAuth(null);
    const store = createAuthStore(source);
    const a = vi.fn();
    const b = vi.fn();
    store.subscribe(a);
    store.subscribe(b);
    await flush();
    emit({ user: { id: "u2" } });
    expect(store.getSnapshot().user).toEqual({ id: "u2" });
    emit(null);
    expect(store.getSnapshot().user).toBeNull();
    expect(a).toHaveBeenCalled();
    expect(b).toHaveBeenCalled();
  });

  it("settles as signed out if the lookup fails", async () => {
    const { source, raw } = fakeAuth();
    raw.getUser.mockRejectedValueOnce(new Error("offline"));
    const store = createAuthStore(source);
    store.subscribe(() => {});
    await flush();
    expect(store.getSnapshot()).toEqual({ user: null, isLoading: false });
  });

  it("keeps a stable snapshot between changes, as useSyncExternalStore requires", () => {
    const store = createAuthStore(fakeAuth().source);
    expect(store.getSnapshot()).toBe(store.getSnapshot());
  });
});

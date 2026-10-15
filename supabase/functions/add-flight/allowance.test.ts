// isWithinAllowance decides whether add-flight starts ~85c of AeroAPI polling. Its two failure modes
// both spend money: a zero limit read as unlimited, and an unreadable allowance read as room.
import { assertEquals } from "jsr:@std/assert";
import { isWithinAllowance } from "./allowance.ts";

Deno.test("under the limit is tracked", () => {
  assertEquals(isWithinAllowance({ limit: 5, used: 4 }), true);
});

Deno.test("at the limit is not", () => {
  assertEquals(isWithinAllowance({ limit: 5, used: 5 }), false);
});

// A zero override is how an admin freezes an account's tracking (20261018000000), and
// enable_flight_tracking already refuses it. add-flight used to treat it as unlimited.
Deno.test("a zero limit freezes tracking rather than lifting the cap", () => {
  assertEquals(isWithinAllowance({ limit: 0, used: 0 }), false);
  assertEquals(isWithinAllowance({ limit: 0, used: 37 }), false);
});

// What a failed or empty RPC response looks like. Each used to come out as limit 0, i.e. unlimited.
Deno.test("no allowance is no room", () => {
  assertEquals(isWithinAllowance(null), false);
  assertEquals(isWithinAllowance(undefined), false);
  assertEquals(isWithinAllowance({}), false);
});

Deno.test("an allowance that is not numbers is no room", () => {
  assertEquals(isWithinAllowance({ limit: "5", used: 0 }), false);
  assertEquals(isWithinAllowance({ limit: 5, used: null }), false);
  assertEquals(isWithinAllowance({ limit: Number.NaN, used: 0 }), false);
});

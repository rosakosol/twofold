// Tests for recognising the number someone typed in AeroAPI's answers.
//
// The bug this pins: searching QF35 for a date weeks out listed a row for every partner airline's
// number on that flight — each badged "Codeshare", all above QF35 itself — because /schedules
// includes codeshares by default and every row was kept.
//
// Run with: deno test supabase/functions/_shared/flight-designator.test.ts

import { assert, assertEquals } from "jsr:@std/assert";
import { isSearchedScheduleRow, splitFlightDesignator } from "./flight-designator.ts";

const qf35 = splitFlightDesignator("QF35")!;

Deno.test("a search for QF35 keeps QF35 and drops partners' numbers for it", () => {
  const rows = [
    { ident: "AAL7363", ident_iata: "AA7363", ident_icao: "AAL7363", actual_ident: "QFA35", actual_ident_iata: "QF35" },
    { ident: "EKX5035", ident_iata: "EK5035", ident_icao: "UAE5035", actual_ident: "QFA35", actual_ident_iata: "QF35" },
    { ident: "QFA35", ident_iata: "QF35", ident_icao: "QFA35" },
  ];
  assertEquals(rows.filter((r) => isSearchedScheduleRow(r, qf35)).map((r) => r.ident_iata), ["QF35"]);
});

Deno.test("a search for a partner's number keeps that partner's row", () => {
  // Their ticket says AA7363, so that is the row they are looking for — still a codeshare.
  const aa7363 = splitFlightDesignator("AA7363")!;
  const row = { ident: "AAL7363", ident_iata: "AA7363", ident_icao: "AAL7363", actual_ident_iata: "QF35" };
  assert(isSearchedScheduleRow(row, aa7363));
  assert(!isSearchedScheduleRow({ ident: "QFA35", ident_iata: "QF35", ident_icao: "QFA35" }, aa7363));
});

Deno.test("matches across leading zeros and ICAO codes", () => {
  assert(isSearchedScheduleRow({ ident: "QFA035", ident_iata: null, ident_icao: null }, qf35));
  assert(isSearchedScheduleRow({ ident: "QFA35" }, splitFlightDesignator("qf035")!));
});

Deno.test("a different flight number under the same airline is not a match", () => {
  assert(!isSearchedScheduleRow({ ident: "QFA36", ident_iata: "QF36" }, qf35));
  assert(!isSearchedScheduleRow({ ident: "QFA350", ident_iata: "QF350" }, qf35));
});

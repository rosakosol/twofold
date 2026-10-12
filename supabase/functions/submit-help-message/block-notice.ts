// The email support receives when someone blocks a person.
//
// A block used to reach nobody. App Review's guidance for apps where one person can reach another
// asks that blocking also notify the developer, and a block is the clearest signal there is that
// something went wrong between two people, often clearer than a report, because a frightened
// person blocks before they write.
//
// Composed here, server-side, from the block itself: the app sends who was blocked and from where,
// never the wording, so a notice can't be used to put arbitrary text in front of support.
//
// In its own module, not index.ts, because index.ts calls Deno.serve at the top level and importing
// it from a test would start a server. See block-notice.test.ts.

export interface BlockNoticeInput {
  display_name?: string;
  surface?: string;
}

/// Anything that would end a header line, flattened, and capped: the display name is
/// attacker-controlled and reaches the Subject header.
function oneLine(value: string, max: number): string {
  return value.replace(/[\r\n\u2028\u2029]+/g, " ").replace(/\s+/g, " ").trim().slice(0, max);
}

const SURFACES: Record<string, string> = {
  "partner": "their current partner, from Disconnect partner",
  "connection request": "someone who sent them a connection request",
};

export function blockNotice(input: BlockNoticeInput): { subject: string; message: string } {
  const name = oneLine(input.display_name ?? "", 80) || "someone";
  const who = SURFACES[input.surface ?? ""] ?? "another account";
  return {
    subject: `[Blocked] ${name}`,
    message: [
      `This account blocked ${who}.`,
      "",
      "Sent automatically: they didn't write a report. If they choose to, it will arrive as a " +
      "separate Report Abuse message. The person blocked has not been told.",
    ].join("\n"),
  };
}

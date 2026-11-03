import { beforeEach, describe, expect, it, vi } from "vitest";

// Stand-in for the Sanity client. Each test sets what `fetch` does; the module under test creates
// its client at import, so the mock has to be in place before the import below.
const fetchMock = vi.fn();
vi.mock("@sanity/client", () => ({ createClient: () => ({ fetch: fetchMock }) }));

const { getLegalPage, getPlans, getResolvedPlans, getQuizQuestions, getQuizResults } = await import("./sanity");
const { PLANS } = await import("./config");

beforeEach(() => {
  fetchMock.mockReset();
  vi.spyOn(console, "warn").mockImplementation(() => {});
});

describe("Sanity getters during an outage", () => {
  beforeEach(() => {
    fetchMock.mockRejectedValue(new Error("getaddrinfo ENOTFOUND api.sanity.io"));
  });

  it("legal pages fall back to the in-code summary instead of throwing", async () => {
    await expect(getLegalPage("privacy")).resolves.toBeNull();
  });

  it("plans fall back to the code copy", async () => {
    await expect(getPlans()).resolves.toEqual({ plus: null, premium: null });
    const plans = await getResolvedPlans();
    expect(plans.plus.name).toBe(PLANS.plus.name);
    expect(plans.premium.features).toEqual(PLANS.premium.features);
  });

  it("the quiz reads as not ready rather than failing the page", async () => {
    await expect(getQuizQuestions()).resolves.toEqual([]);
    await expect(getQuizResults()).resolves.toEqual({ plus: null, premium: null });
  });
});

describe("Sanity getters with content", () => {
  it("pass the documents through", async () => {
    fetchMock.mockResolvedValue([{ _id: "plan-plus", name: "Plus (edited)" }]);
    const plans = await getPlans();
    expect(plans.plus?.name).toBe("Plus (edited)");
    expect(plans.premium).toBeNull();
  });

  it("treat a missing document as absent", async () => {
    fetchMock.mockResolvedValue(null);
    await expect(getLegalPage("terms")).resolves.toBeNull();
  });
});

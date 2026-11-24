import { createElement } from "lwc";
import JourneyConfigCheck from "c/journeyConfigCheck";
import getConfigHealth from "@salesforce/apex/JourneyController.getConfigHealth";

jest.mock(
  "@salesforce/apex/JourneyController.getConfigHealth",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());

function create() {
  const el = createElement("c-journey-config-check", {
    is: JourneyConfigCheck
  });
  document.body.appendChild(el);
  return el;
}
const q = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);

describe("c-journey-config-check", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists configuration issues", async () => {
    getConfigHealth.mockResolvedValue(["Issue one", "Issue two"]);
    const el = create();
    await flush();
    const items = [...el.shadowRoot.querySelectorAll('[data-id="issue"]')];
    expect(items.map((i) => i.textContent)).toEqual(["Issue one", "Issue two"]);
    expect(q(el, "ok")).toBeNull();
  });

  it("shows Configuration OK when there are no issues", async () => {
    getConfigHealth.mockResolvedValue([]);
    const el = create();
    await flush();
    expect(q(el, "ok").textContent).toBe("Configuration OK");
    expect(el.shadowRoot.querySelectorAll('[data-id="issue"]')).toHaveLength(0);
  });

  it("shows the error message when the call fails", async () => {
    getConfigHealth.mockRejectedValue({ body: { message: "No access" } });
    const el = create();
    await flush();
    expect(q(el, "error").textContent).toBe("No access");
    expect(q(el, "ok")).toBeNull();
  });
});

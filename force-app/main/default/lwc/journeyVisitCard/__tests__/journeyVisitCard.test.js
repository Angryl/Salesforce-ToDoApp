import { createElement } from "lwc";
import JourneyVisitCard from "c/journeyVisitCard";
import { getCurrentLocation } from "c/locationUtil";
import checkIn from "@salesforce/apex/JourneyController.checkIn";
import checkOut from "@salesforce/apex/JourneyController.checkOut";
import { getRecord, notifyRecordUpdateAvailable } from "lightning/uiRecordApi";

jest.mock("c/locationUtil", () => ({
  getCurrentLocation: jest.fn(),
  locationErrorMessage:
    jest.requireActual("c/locationUtil").locationErrorMessage
}));
jest.mock(
  "@salesforce/apex/JourneyController.checkIn",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/JourneyController.checkOut",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const LOC = {
  latitude: 28.6,
  longitude: 77.2,
  accuracyMeters: 20,
  source: "Browser"
};
const RESULT = {
  eventId: "00U1",
  journeyId: "a001",
  lowAccuracy: false,
  legKm: 1,
  minutesSpent: 5
};

const flush = () => Promise.resolve().then(() => Promise.resolve());
const flushAll = () =>
  Array.from({ length: 8 }).reduce((p) => p.then(flush), Promise.resolve());

function create(props) {
  const el = createElement("c-journey-visit-card", { is: JourneyVisitCard });
  Object.assign(el, props);
  document.body.appendChild(el);
  return el;
}
const visit = (extra) => ({
  id: "00U1",
  subject: "Call ACME",
  status: "Planned",
  ...extra
});
const buttonByLabel = (el, label) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );
const errorText = (el) => {
  const node = el.shadowRoot.querySelector('[data-id="error"]');
  return node ? node.textContent : null;
};

describe("c-journey-visit-card", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows Check in for a Planned visit (null status too)", async () => {
    const el = create({ visit: visit({ status: null }) });
    await flush();
    expect(buttonByLabel(el, "Check in")).toBeTruthy();
    expect(buttonByLabel(el, "Check out")).toBeFalsy();
  });

  it("shows summary textarea and Check out for a Checked In visit", async () => {
    const el = create({ visit: visit({ status: "Checked In" }) });
    await flush();
    const ta = el.shadowRoot.querySelector("lightning-textarea");
    expect(ta.label).toBe("Meeting summary");
    expect(buttonByLabel(el, "Check out")).toBeTruthy();
    expect(buttonByLabel(el, "Check in")).toBeFalsy();
  });

  it("shows read-only details for a Completed visit", async () => {
    const el = create({
      visit: visit({
        status: "Completed",
        minutesSpent: 65,
        legKm: 3.456,
        summary: "All good"
      })
    });
    await flush();
    expect(el.shadowRoot.querySelectorAll("lightning-button").length).toBe(0);
    const text = el.shadowRoot.textContent;
    expect(text).toContain("1h 5m");
    expect(text).toContain("3.46 km");
    expect(text).toContain("All good");
  });

  it("formats minutes under an hour as Xm", async () => {
    const el = create({
      visit: visit({ status: "Completed", minutesSpent: 45, legKm: 0 })
    });
    await flush();
    expect(el.shadowRoot.textContent).toContain("45m");
    expect(el.shadowRoot.textContent).not.toContain("0h");
  });

  it("checks in, fires visitchange and shows a success toast", async () => {
    getCurrentLocation.mockResolvedValue(LOC);
    checkIn.mockResolvedValue(RESULT);
    const el = create({ visit: visit() });
    const onChange = jest.fn();
    const onToast = jest.fn();
    el.addEventListener("visitchange", onChange);
    el.addEventListener("lightning__showtoast", onToast);
    await flush();
    buttonByLabel(el, "Check in").click();
    await flushAll();
    expect(checkIn).toHaveBeenCalledWith({ eventId: "00U1", loc: LOC });
    expect(onChange).toHaveBeenCalledTimes(1);
    expect(onChange.mock.calls[0][0].detail).toEqual({ eventId: "00U1" });
    expect(onChange.mock.calls[0][0].bubbles).toBe(false);
    expect(onChange.mock.calls[0][0].composed).toBe(false);
    expect(onToast).toHaveBeenCalledTimes(1);
    expect(onToast.mock.calls[0][0].detail).toMatchObject({
      variant: "success",
      title: "Checked in"
    });
  });

  it("checks out with the summary text", async () => {
    getCurrentLocation.mockResolvedValue(LOC);
    checkOut.mockResolvedValue(RESULT);
    const el = create({ visit: visit({ status: "Checked In" }) });
    const onToast = jest.fn();
    el.addEventListener("lightning__showtoast", onToast);
    await flush();
    const ta = el.shadowRoot.querySelector("lightning-textarea");
    ta.value = "Done deal";
    ta.dispatchEvent(new CustomEvent("change"));
    buttonByLabel(el, "Check out").click();
    await flushAll();
    expect(checkOut).toHaveBeenCalledWith({
      eventId: "00U1",
      loc: LOC,
      summary: "Done deal"
    });
    expect(onToast.mock.calls[0][0].detail.title).toBe("Checked out");
  });

  it.each([
    [
      "DENIED",
      "Location permission is off. Allow location for the Salesforce app in your phone settings, then tap Retry."
    ],
    [
      "UNAVAILABLE",
      "Couldn't get your location. Move to an open area and tap Retry."
    ],
    ["TIMEOUT", "Getting your location took too long. Tap Retry."]
  ])("location %s shows message and does not call Apex", async (code, msg) => {
    const err = new Error("x");
    err.code = code;
    getCurrentLocation.mockRejectedValue(err);
    const el = create({ visit: visit() });
    await flush();
    buttonByLabel(el, "Check in").click();
    await flushAll();
    expect(checkIn).not.toHaveBeenCalled();
    expect(errorText(el)).toContain(msg);
    expect(buttonByLabel(el, "Retry")).toBeTruthy();
  });

  it("Retry repeats the same action", async () => {
    const err = new Error("x");
    err.code = "TIMEOUT";
    getCurrentLocation.mockRejectedValueOnce(err).mockResolvedValue(LOC);
    checkIn.mockResolvedValue(RESULT);
    const el = create({ visit: visit() });
    await flush();
    buttonByLabel(el, "Check in").click();
    await flushAll();
    buttonByLabel(el, "Retry").click();
    await flushAll();
    expect(checkIn).toHaveBeenCalledTimes(1);
    expect(errorText(el)).toBeNull();
  });

  it("shows the Apex error message inline", async () => {
    getCurrentLocation.mockResolvedValue(LOC);
    checkIn.mockRejectedValue({ body: { message: "Already checked in" } });
    const el = create({ visit: visit() });
    await flush();
    buttonByLabel(el, "Check in").click();
    await flushAll();
    expect(errorText(el)).toContain("Already checked in");
  });

  it("falls back to a generic Apex error message", async () => {
    getCurrentLocation.mockResolvedValue(LOC);
    checkIn.mockRejectedValue({});
    const el = create({ visit: visit() });
    await flush();
    buttonByLabel(el, "Check in").click();
    await flushAll();
    expect(errorText(el)).toContain("Something went wrong. Please try again.");
  });

  it("disables the button while a call is in flight", async () => {
    let resolveLoc;
    getCurrentLocation.mockReturnValue(
      new Promise((r) => {
        resolveLoc = r;
      })
    );
    checkIn.mockResolvedValue(RESULT);
    const el = create({ visit: visit() });
    await flush();
    buttonByLabel(el, "Check in").click();
    await flush();
    expect(buttonByLabel(el, "Check in").disabled).toBe(true);
    buttonByLabel(el, "Check in").click();
    resolveLoc(LOC);
    await flushAll();
    expect(checkIn).toHaveBeenCalledTimes(1);
    expect(buttonByLabel(el, "Check in").disabled).toBe(false);
  });

  it("shows a low accuracy warning toast after success", async () => {
    getCurrentLocation.mockResolvedValue(LOC);
    checkIn.mockResolvedValue({ ...RESULT, lowAccuracy: true });
    const el = create({ visit: visit() });
    const onToast = jest.fn();
    el.addEventListener("lightning__showtoast", onToast);
    await flush();
    buttonByLabel(el, "Check in").click();
    await flushAll();
    const details = onToast.mock.calls.map((c) => c[0].detail);
    expect(details).toContainEqual(
      expect.objectContaining({
        variant: "warning",
        title: "Low GPS accuracy",
        message: "Your location may be off by a few hundred metres."
      })
    );
  });

  describe("record page mode", () => {
    const record = (status) => ({
      fields: {
        Subject: { value: "Visit X" },
        Visit_Status__c: { value: status },
        Meeting_Summary__c: { value: "Notes" },
        Time_Spent_Minutes__c: { value: 65 },
        Distance_From_Previous_Km__c: { value: 2 }
      }
    });

    it("renders from the wired record and refreshes it after an action", async () => {
      getCurrentLocation.mockResolvedValue(LOC);
      checkIn.mockResolvedValue(RESULT);
      const el = create({ recordId: "00U9" });
      getRecord.emit(record("Planned"));
      await flush();
      expect(buttonByLabel(el, "Check in")).toBeTruthy();
      buttonByLabel(el, "Check in").click();
      await flushAll();
      expect(checkIn).toHaveBeenCalledWith({ eventId: "00U9", loc: LOC });
      expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
        { recordId: "00U9" }
      ]);
    });

    it("renders a completed record read-only", async () => {
      const el = create({ recordId: "00U9" });
      getRecord.emit(record("Completed"));
      await flush();
      expect(el.shadowRoot.textContent).toContain("1h 5m");
      expect(el.shadowRoot.textContent).toContain("2.00 km");
    });
  });
});

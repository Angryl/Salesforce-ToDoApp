import { createElement } from "lwc";
import JourneyPlanner from "c/journeyPlanner";
import { getCurrentLocation } from "c/locationUtil";
import getDay from "@salesforce/apex/JourneyController.getDay";
import createVisit from "@salesforce/apex/JourneyController.createVisit";
import rescheduleVisit from "@salesforce/apex/JourneyController.rescheduleVisit";
import startDay from "@salesforce/apex/JourneyController.startDay";
import endDay from "@salesforce/apex/JourneyController.endDay";

jest.mock("c/locationUtil", () => ({
  getCurrentLocation: jest.fn(),
  locationErrorMessage:
    jest.requireActual("c/locationUtil").locationErrorMessage
}));
jest.mock(
  "@salesforce/apex/JourneyController.getDay",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/JourneyController.createVisit",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/JourneyController.rescheduleVisit",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/JourneyController.startDay",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/JourneyController.endDay",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());
const flushAll = () =>
  Array.from({ length: 8 }).reduce((p) => p.then(flush), Promise.resolve());
const pad = (n) => String(n).padStart(2, "0");
const ymd = (d) =>
  `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const dayOffset = (n) => {
  const d = new Date();
  d.setDate(d.getDate() + n);
  return ymd(d);
};
const at = (h, m = 0) => new Date(2026, 10, 24, h, m).toISOString();
const LOC = { latitude: 1, longitude: 2, accuracyMeters: 5, source: "Browser" };
const OPTIONS = [
  {
    apiName: "Account",
    relationField: "WhatId",
    label: "Account",
    iconName: "standard:account",
    displayField: "Name"
  }
];
const day = (extra) => ({
  journey: null,
  visits: [],
  objectOptions: OPTIONS,
  defaultVisitMinutes: 45,
  ...extra
});

function create() {
  const el = createElement("c-journey-planner", { is: JourneyPlanner });
  document.body.appendChild(el);
  return el;
}
const q = (el, sel) => el.shadowRoot.querySelector(sel);
const buttonByLabel = (el, label) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

describe("c-journey-planner", () => {
  beforeEach(() => {
    getDay.mockResolvedValue(day());
    createVisit.mockResolvedValue({ eventId: "00U9", overlaps: [] });
    rescheduleVisit.mockResolvedValue({ eventId: "00U1", overlaps: [] });
    startDay.mockResolvedValue({});
    endDay.mockResolvedValue({});
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.resetAllMocks();
  });

  it("loads today on connect", async () => {
    create();
    await flushAll();
    expect(getDay).toHaveBeenCalledWith({ dayDate: dayOffset(0) });
  });

  it("Previous, Next and Today reload getDay for the new date", async () => {
    const el = create();
    await flushAll();
    buttonByLabel(el, "Next").click();
    await flushAll();
    expect(getDay).toHaveBeenLastCalledWith({ dayDate: dayOffset(1) });
    buttonByLabel(el, "Previous").click();
    buttonByLabel(el, "Previous").click();
    await flushAll();
    expect(getDay).toHaveBeenLastCalledWith({ dayDate: dayOffset(-1) });
    buttonByLabel(el, "Today").click();
    await flushAll();
    expect(getDay).toHaveBeenLastCalledWith({ dayDate: dayOffset(0) });
  });

  it("shows visits, km (2 dp) and Xh Ym from the journey", async () => {
    getDay.mockResolvedValue(
      day({
        visits: [
          { id: "1", status: "Planned" },
          { id: "2", status: null, allDay: true },
          { id: "3", status: "Completed" },
          { id: "4", status: "Checked In" }
        ],
        journey: {
          Id: "a001",
          Total_Km__c: 12.3456,
          Total_Visit_Minutes__c: 135,
          Visit_Count__c: 3
        }
      })
    );
    const el = create();
    await flushAll();
    expect(q(el, '[data-id="summary"]').textContent).toBe(
      "1 planned · 3 completed · 12.35 km · 2h 15m"
    );
  });

  it("shows zeros when there is no journey", async () => {
    const el = create();
    await flushAll();
    expect(q(el, '[data-id="summary"]').textContent).toBe(
      "0 planned · 0 completed · 0.00 km · 0h 0m"
    );
  });

  it("slot select opens the form prefilled with start and default duration", async () => {
    const el = create();
    await flushAll();
    q(el, "c-journey-timeline").dispatchEvent(
      new CustomEvent("slotselect", { detail: { start: at(9) } })
    );
    await flushAll();
    const form = q(el, "c-journey-event-form");
    expect(form.mode).toBe("create");
    expect(form.start).toBe(at(9));
    expect(form.end).toBe(at(9, 45));
    expect(form.objectOptions).toEqual(OPTIONS);
  });

  async function openAndSave(el) {
    q(el, "c-journey-timeline").dispatchEvent(
      new CustomEvent("slotselect", { detail: { start: at(9) } })
    );
    await flushAll();
    q(el, "c-journey-event-form").dispatchEvent(
      new CustomEvent("save", {
        detail: {
          subject: "Call ACME",
          relatedId: "001A",
          start: at(9),
          end: at(10)
        }
      })
    );
    await flushAll();
  }

  it("saves a new visit, closes the form and reloads", async () => {
    const el = create();
    await flushAll();
    await openAndSave(el);
    expect(createVisit).toHaveBeenCalledWith({
      subject: "Call ACME",
      startTime: at(9),
      endTime: at(10),
      relatedId: "001A"
    });
    expect(q(el, "c-journey-event-form")).toBeNull();
    expect(q(el, '[data-id="overlap"]')).toBeNull();
    expect(getDay).toHaveBeenCalledTimes(2);
  });

  it("warns with overlapping subjects; Keep both dismisses", async () => {
    createVisit.mockResolvedValue({
      eventId: "00U9",
      overlaps: [
        { id: "00U1", subject: "Lunch" },
        { id: "00U2", subject: "Demo" }
      ]
    });
    const el = create();
    await flushAll();
    await openAndSave(el);
    const warn = q(el, '[data-id="overlap"]');
    expect(warn.textContent).toContain("Lunch");
    expect(warn.textContent).toContain("Demo");
    buttonByLabel(el, "Keep both").click();
    await flushAll();
    expect(q(el, '[data-id="overlap"]')).toBeNull();
    expect(rescheduleVisit).not.toHaveBeenCalled();
  });

  it("Change time reopens the form in edit mode and reschedules", async () => {
    createVisit.mockResolvedValue({
      eventId: "00U9",
      overlaps: [{ id: "00U1", subject: "Lunch" }]
    });
    const el = create();
    await flushAll();
    await openAndSave(el);
    buttonByLabel(el, "Change time").click();
    await flushAll();
    const form = q(el, "c-journey-event-form");
    expect(form.mode).toBe("edit");
    expect(form.eventId).toBe("00U9");
    expect(form.start).toBe(at(9));
    expect(form.end).toBe(at(10));
    form.dispatchEvent(
      new CustomEvent("save", {
        detail: { eventId: "00U9", start: at(13), end: at(14) }
      })
    );
    await flushAll();
    expect(rescheduleVisit).toHaveBeenCalledWith({
      eventId: "00U9",
      startTime: at(13),
      endTime: at(14)
    });
    expect(q(el, "c-journey-event-form")).toBeNull();
    expect(q(el, '[data-id="overlap"]')).toBeNull();
  });

  it("visitmove reschedules, and a still-overlapping result warns again", async () => {
    rescheduleVisit.mockResolvedValue({
      eventId: "00U1",
      overlaps: [{ id: "00U2", subject: "Demo" }]
    });
    const el = create();
    await flushAll();
    q(el, "c-journey-timeline").dispatchEvent(
      new CustomEvent("visitmove", {
        detail: { eventId: "00U1", start: at(11), end: at(12) }
      })
    );
    await flushAll();
    expect(rescheduleVisit).toHaveBeenCalledWith({
      eventId: "00U1",
      startTime: at(11),
      endTime: at(12)
    });
    expect(q(el, '[data-id="overlap"]').textContent).toContain("Demo");
  });

  it("shows an Apex error from createVisit and keeps the form open", async () => {
    createVisit.mockRejectedValue({ body: { message: "No access" } });
    const el = create();
    await flushAll();
    await openAndSave(el);
    const form = q(el, "c-journey-event-form");
    expect(form).toBeTruthy();
    expect(
      form.shadowRoot.querySelector('[data-id="error"]').textContent
    ).toContain("No access");
    expect(q(el, '[data-id="error"]')).toBeNull();
  });

  it("reloads when a visit card reports a change", async () => {
    const el = create();
    await flushAll();
    q(el, "c-journey-timeline").dispatchEvent(
      new CustomEvent("visitchange", { detail: { eventId: "00U1" } })
    );
    await flushAll();
    expect(getDay).toHaveBeenCalledTimes(2);
  });

  it("Start day and End day send today's date and location, then reload", async () => {
    getCurrentLocation.mockResolvedValue(LOC);
    const el = create();
    await flushAll();
    const onToast = jest.fn();
    el.addEventListener("lightning__showtoast", onToast);
    buttonByLabel(el, "Start day").click();
    await flushAll();
    expect(startDay).toHaveBeenCalledWith({ d: dayOffset(0), loc: LOC });
    buttonByLabel(el, "End day").click();
    await flushAll();
    expect(endDay).toHaveBeenCalledWith({ d: dayOffset(0), loc: LOC });
    expect(getDay).toHaveBeenCalledTimes(3);
    expect(onToast.mock.calls[0][0].detail.title).toBe("Day started");
  });

  it("hides Start day and End day when not viewing today", async () => {
    const el = create();
    await flushAll();
    buttonByLabel(el, "Next").click();
    await flushAll();
    expect(buttonByLabel(el, "Start day")).toBeUndefined();
    expect(buttonByLabel(el, "End day")).toBeUndefined();
  });

  it.each([
    ["DENIED", "Location permission is off."],
    ["UNAVAILABLE", "Couldn't get your location."],
    ["TIMEOUT", "took too long"]
  ])("location %s blocks Start day with a message", async (code, text) => {
    const err = new Error("x");
    err.code = code;
    getCurrentLocation.mockRejectedValue(err);
    const el = create();
    await flushAll();
    buttonByLabel(el, "Start day").click();
    await flushAll();
    expect(startDay).not.toHaveBeenCalled();
    expect(q(el, '[data-id="error"]').textContent).toContain(text);
  });
});

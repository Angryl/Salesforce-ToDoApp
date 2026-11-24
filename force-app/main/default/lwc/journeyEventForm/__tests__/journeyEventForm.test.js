import { createElement } from "lwc";
import JourneyEventForm from "c/journeyEventForm";

const flush = () => Promise.resolve().then(() => Promise.resolve());
const START = new Date(2026, 10, 24, 9, 0).toISOString();
const END = new Date(2026, 10, 24, 10, 0).toISOString();
const OPTIONS = [
  { apiName: "Account", label: "Account", relationField: "WhatId" },
  { apiName: "Contact", label: "Contact", relationField: "WhoId" }
];

function create(props) {
  const el = createElement("c-journey-event-form", { is: JourneyEventForm });
  Object.assign(el, props);
  document.body.appendChild(el);
  return el;
}
const q = (el, sel) => el.shadowRoot.querySelector(sel);
const change = (node, detail) =>
  node.dispatchEvent(new CustomEvent("change", { detail }));
const buttonByLabel = (el, label) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );
const errorText = (el) => {
  const node = q(el, '[data-id="error"]');
  return node ? node.textContent : null;
};

describe("c-journey-event-form", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("create mode prefills start and end and shows object and record fields", async () => {
    const el = create({
      mode: "create",
      objectOptions: OPTIONS,
      start: START,
      end: END
    });
    await flush();
    expect(q(el, '[data-id="start"]').value).toBe(START);
    expect(q(el, '[data-id="end"]').value).toBe(END);
    expect(q(el, '[data-id="object"]').options.map((o) => o.value)).toEqual([
      "Account",
      "Contact"
    ]);
    expect(q(el, '[data-id="record"]')).toBeNull();
    change(q(el, '[data-id="object"]'), { value: "Contact" });
    await flush();
    expect(q(el, '[data-id="record"]').objectApiName).toBe("Contact");
  });

  it("edit mode hides subject-less object and record fields", async () => {
    const el = create({
      mode: "edit",
      objectOptions: OPTIONS,
      start: START,
      end: END
    });
    await flush();
    expect(q(el, '[data-id="object"]')).toBeNull();
    expect(q(el, '[data-id="record"]')).toBeNull();
    expect(q(el, '[data-id="subject"]')).toBeNull();
    expect(q(el, '[data-id="start"]')).toBeTruthy();
  });

  it("emits save with the entered values in create mode", async () => {
    const el = create({
      mode: "create",
      objectOptions: OPTIONS,
      start: START,
      end: END
    });
    const onSave = jest.fn();
    el.addEventListener("save", onSave);
    await flush();
    change(q(el, '[data-id="subject"]'), { value: "Call ACME" });
    change(q(el, '[data-id="object"]'), { value: "Account" });
    await flush();
    change(q(el, '[data-id="record"]'), { recordId: "001A" });
    buttonByLabel(el, "Save").click();
    expect(onSave).toHaveBeenCalledTimes(1);
    expect(onSave.mock.calls[0][0].detail).toEqual({
      eventId: undefined,
      subject: "Call ACME",
      relatedId: "001A",
      start: START,
      end: END
    });
  });

  it("requires subject and record in create mode", async () => {
    const el = create({
      mode: "create",
      objectOptions: OPTIONS,
      start: START,
      end: END
    });
    const onSave = jest.fn();
    el.addEventListener("save", onSave);
    await flush();
    buttonByLabel(el, "Save").click();
    await flush();
    expect(onSave).not.toHaveBeenCalled();
    expect(errorText(el)).toContain("Subject is required");
    change(q(el, '[data-id="subject"]'), { value: "X" });
    buttonByLabel(el, "Save").click();
    await flush();
    expect(onSave).not.toHaveBeenCalled();
    expect(errorText(el)).toContain("Choose a record");
  });

  it("rejects end not after start", async () => {
    const el = create({
      mode: "edit",
      eventId: "00U1",
      start: START,
      end: END
    });
    const onSave = jest.fn();
    el.addEventListener("save", onSave);
    await flush();
    change(q(el, '[data-id="end"]'), { value: START });
    buttonByLabel(el, "Save").click();
    await flush();
    expect(onSave).not.toHaveBeenCalled();
    expect(errorText(el)).toContain("End must be after start");
  });

  it("edit mode saves new times with the event id", async () => {
    const el = create({
      mode: "edit",
      eventId: "00U1",
      start: START,
      end: END
    });
    const onSave = jest.fn();
    el.addEventListener("save", onSave);
    await flush();
    const later = new Date(2026, 10, 24, 11, 0).toISOString();
    change(q(el, '[data-id="end"]'), { value: later });
    buttonByLabel(el, "Save").click();
    expect(onSave.mock.calls[0][0].detail).toMatchObject({
      eventId: "00U1",
      start: START,
      end: later
    });
  });

  it("emits cancel", async () => {
    const el = create({ mode: "edit", start: START, end: END });
    const onCancel = jest.fn();
    el.addEventListener("cancel", onCancel);
    await flush();
    buttonByLabel(el, "Cancel").click();
    expect(onCancel).toHaveBeenCalledTimes(1);
  });

  it("renders a server error inside the modal", async () => {
    const el = create({
      mode: "edit",
      start: START,
      end: END,
      serverError: "No access"
    });
    await flush();
    expect(errorText(el)).toContain("No access");
  });
});

import { createElement } from "lwc";
import JourneyTimeline from "c/journeyTimeline";

const flush = () => Promise.resolve().then(() => Promise.resolve());
const at = (h, m = 0) => new Date(2026, 10, 24, h, m).toISOString();

function create(props) {
  const el = createElement("c-journey-timeline", { is: JourneyTimeline });
  Object.assign(el, props);
  document.body.appendChild(el);
  return el;
}
const visit = (extra) => ({
  id: "00U1",
  subject: "Call ACME",
  startTime: at(9),
  endTime: at(10),
  allDay: false,
  status: "Planned",
  overlapsWith: [],
  ...extra
});
const all = (el, sel) => [...el.shadowRoot.querySelectorAll(sel)];
const buttonByLabel = (el, label) =>
  all(el, "lightning-button").find((b) => b.label === label);

describe("c-journey-timeline", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders 28 half-hour slots from 07:00 to 20:30", async () => {
    const el = create({ date: "2026-11-24", visits: [] });
    await flush();
    const slots = all(el, "[data-slot]");
    expect(slots.length).toBe(28);
    expect(slots[0].textContent).toContain("07:00");
    expect(slots[27].textContent).toContain("20:30");
  });

  it("emits slotselect with the slot start as ISO", async () => {
    const el = create({ date: "2026-11-24", visits: [] });
    const onSlot = jest.fn();
    el.addEventListener("slotselect", onSlot);
    await flush();
    all(el, "[data-slot]")[4].click(); // 09:00
    expect(onSlot.mock.calls[0][0].detail).toEqual({ start: at(9) });
  });

  it("positions a card by start and end", async () => {
    const el = create({
      date: "2026-11-24",
      visits: [visit({ startTime: at(9), endTime: at(10, 30) })]
    });
    await flush();
    const wrap = el.shadowRoot.querySelector("[data-card='00U1']");
    expect(wrap.style.top).toBe("192px"); // 4 rows x 48px
    expect(wrap.style.height).toBe("144px"); // 3 rows
    expect(el.shadowRoot.querySelector("c-journey-visit-card")).toBeTruthy();
  });

  it("lists all-day visits in a strip above the grid", async () => {
    const el = create({
      date: "2026-11-24",
      visits: [visit({ id: "00U2", allDay: true })]
    });
    await flush();
    expect(el.shadowRoot.querySelector("[data-id='allday']")).toBeTruthy();
    expect(el.shadowRoot.querySelector("[data-card='00U2']")).toBeNull();
    expect(el.shadowRoot.querySelectorAll("c-journey-visit-card").length).toBe(
      1
    );
  });

  it("shows a warning marker only on overlapping cards", async () => {
    const el = create({
      date: "2026-11-24",
      visits: [
        visit({ id: "00U1", overlapsWith: ["00U2"] }),
        visit({
          id: "00U2",
          overlapsWith: [],
          startTime: at(12),
          endTime: at(13)
        })
      ]
    });
    await flush();
    const marked = (id) =>
      el.shadowRoot.querySelector(
        `[data-card='${id}'] [data-id='overlap-marker']`
      );
    expect(marked("00U1").iconName).toBe("utility:warning");
    expect(marked("00U1").alternativeText).toBe("Overlaps another visit");
    expect(marked("00U2")).toBeNull();
  });

  it("Move on a Planned card opens the form and emits visitmove on save", async () => {
    const el = create({ date: "2026-11-24", visits: [visit()] });
    const onMove = jest.fn();
    el.addEventListener("visitmove", onMove);
    await flush();
    buttonByLabel(el, "Move").click();
    await flush();
    const form = el.shadowRoot.querySelector("c-journey-event-form");
    expect(form.mode).toBe("edit");
    expect(form.start).toBe(at(9));
    expect(form.end).toBe(at(10));
    form.dispatchEvent(
      new CustomEvent("save", {
        detail: { eventId: "00U1", start: at(11), end: at(12) }
      })
    );
    await flush();
    expect(onMove.mock.calls[0][0].detail).toEqual({
      eventId: "00U1",
      start: at(11),
      end: at(12)
    });
    expect(el.shadowRoot.querySelector("c-journey-event-form")).toBeNull();
  });

  it("offers no Move and emits no visitmove for non-Planned cards", async () => {
    const el = create({
      date: "2026-11-24",
      visits: [
        visit({ id: "00U1", status: "Checked In" }),
        visit({
          id: "00U3",
          status: "Completed",
          startTime: at(14),
          endTime: at(15)
        })
      ]
    });
    const onMove = jest.fn();
    el.addEventListener("visitmove", onMove);
    await flush();
    expect(buttonByLabel(el, "Move")).toBeUndefined();
    expect(onMove).not.toHaveBeenCalled();
  });

  it("re-emits visitchange from a card", async () => {
    const el = create({ date: "2026-11-24", visits: [visit()] });
    const onChange = jest.fn();
    el.addEventListener("visitchange", onChange);
    await flush();
    el.shadowRoot
      .querySelector("c-journey-visit-card")
      .dispatchEvent(
        new CustomEvent("visitchange", { detail: { eventId: "00U1" } })
      );
    expect(onChange).toHaveBeenCalledTimes(1);
  });

  it("places overlapping cards side by side and keeps others full width", async () => {
    const el = create({
      date: "2026-11-24",
      visits: [
        visit({ id: "A", startTime: at(9), endTime: at(10, 30) }),
        visit({ id: "B", startTime: at(10), endTime: at(11) }),
        visit({ id: "C", startTime: at(13), endTime: at(14) })
      ]
    });
    await flush();
    const style = (id) =>
      el.shadowRoot.querySelector(`[data-card='${id}']`).style;
    expect(style("A").left).toBe("0%");
    expect(style("A").width).toBe("50%");
    expect(style("B").left).toBe("50%");
    expect(style("B").width).toBe("50%");
    expect(style("C").left).toBe("0%");
    expect(style("C").width).toBe("100%");
  });
});

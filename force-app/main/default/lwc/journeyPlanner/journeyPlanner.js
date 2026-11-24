import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getCurrentLocation, locationErrorMessage } from "c/locationUtil";
import getDayApex from "@salesforce/apex/JourneyController.getDay";
import createVisitApex from "@salesforce/apex/JourneyController.createVisit";
import rescheduleVisitApex from "@salesforce/apex/JourneyController.rescheduleVisit";
import startDayApex from "@salesforce/apex/JourneyController.startDay";
import endDayApex from "@salesforce/apex/JourneyController.endDay";

const GENERIC_ERROR = "Something went wrong. Please try again.";
const pad = (n) => String(n).padStart(2, "0");
const toYmd = (d) =>
  `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const fromYmd = (s) => {
  const [y, m, d] = s.split("-").map(Number);
  return new Date(y, m - 1, d);
};
const errorOf = (e) => (e && e.body && e.body.message) || GENERIC_ERROR;

export default class JourneyPlanner extends LightningElement {
  dateValue = toYmd(new Date());
  day = { journey: null, visits: [], objectOptions: [] };
  defaultMinutes = 30;
  form; // { mode, eventId, start, end }
  overlaps; // [{ id, subject }] from the last save
  lastSaved; // { eventId, start, end } behind the overlap warning
  errorMessage;
  busy = false;

  connectedCallback() {
    return this.load();
  }

  async load() {
    try {
      const data = await getDayApex({ dayDate: this.dateValue });
      this.day = data;
      this.defaultMinutes = data.defaultVisitMinutes || this.defaultMinutes;
    } catch (e) {
      this.errorMessage = errorOf(e);
    }
  }

  get title() {
    return fromYmd(this.dateValue).toLocaleDateString(undefined, {
      weekday: "long",
      day: "numeric",
      month: "long",
      year: "numeric"
    });
  }

  get isToday() {
    return this.dateValue === toYmd(new Date());
  }

  get summary() {
    const journey = this.day.journey;
    const completed = (journey && journey.Visit_Count__c) || 0;
    const planned = (this.day.visits || []).filter(
      (v) => !v.allDay && (v.status || "Planned") === "Planned"
    ).length;
    const km = Number((journey && journey.Total_Km__c) || 0).toFixed(2);
    const total = Math.round((journey && journey.Total_Visit_Minutes__c) || 0);
    return `${planned} planned · ${completed} completed · ${km} km · ${Math.floor(total / 60)}h ${total % 60}m`;
  }

  get hasError() {
    return !!this.errorMessage && !this.form;
  }

  get hasOverlaps() {
    return !!(this.overlaps && this.overlaps.length);
  }

  get overlapNames() {
    return (this.overlaps || []).map((o) => o.subject).join(", ");
  }

  get hasForm() {
    return !!this.form;
  }

  shiftDay(delta) {
    const d = fromYmd(this.dateValue);
    d.setDate(d.getDate() + delta);
    this.dateValue = toYmd(d);
    this.overlaps = undefined;
    return this.load();
  }

  handlePrevious() {
    return this.shiftDay(-1);
  }

  handleNext() {
    return this.shiftDay(1);
  }

  handleToday() {
    this.dateValue = toYmd(new Date());
    this.overlaps = undefined;
    return this.load();
  }

  handleSlotSelect(event) {
    const start = new Date(event.detail.start);
    const end = new Date(start.getTime() + this.defaultMinutes * 60000);
    this.errorMessage = undefined;
    this.form = {
      mode: "create",
      start: start.toISOString(),
      end: end.toISOString()
    };
  }

  handleFormCancel() {
    this.form = undefined;
    this.errorMessage = undefined;
  }

  handleFormSave(event) {
    const { eventId, subject, relatedId, start, end } = event.detail;
    return eventId
      ? this.reschedule(eventId, start, end)
      : this.create(subject, relatedId, start, end);
  }

  handleVisitMove(event) {
    const { eventId, start, end } = event.detail;
    return this.reschedule(eventId, start, end);
  }

  handleVisitChange() {
    return this.load();
  }

  async create(subject, relatedId, start, end) {
    await this.save(
      () =>
        createVisitApex({ subject, startTime: start, endTime: end, relatedId }),
      start,
      end
    );
  }

  async reschedule(eventId, start, end) {
    await this.save(
      () => rescheduleVisitApex({ eventId, startTime: start, endTime: end }),
      start,
      end
    );
  }

  async save(call, start, end) {
    this.errorMessage = undefined;
    this.overlaps = undefined;
    try {
      const result = await call();
      this.form = undefined;
      if (result.overlaps && result.overlaps.length) {
        this.overlaps = result.overlaps;
        this.lastSaved = { eventId: result.eventId, start, end };
      }
    } catch (e) {
      this.errorMessage = errorOf(e);
      return;
    }
    await this.load();
  }

  handleKeepBoth() {
    this.overlaps = undefined;
    this.lastSaved = undefined;
  }

  handleChangeTime() {
    this.form = { mode: "edit", ...this.lastSaved };
    this.overlaps = undefined;
  }

  handleStartDay() {
    return this.dayAction(startDayApex, "Day started");
  }

  handleEndDay() {
    return this.dayAction(endDayApex, "Day ended");
  }

  async dayAction(apex, title) {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorMessage = undefined;
    try {
      let loc;
      try {
        loc = await getCurrentLocation();
      } catch (e) {
        this.errorMessage = locationErrorMessage(e && e.code);
        return;
      }
      try {
        await apex({ d: this.dateValue, loc });
      } catch (e) {
        this.errorMessage = errorOf(e);
        return;
      }
      this.dispatchEvent(new ShowToastEvent({ variant: "success", title }));
      await this.load();
    } finally {
      this.busy = false;
    }
  }
}

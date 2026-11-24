import { LightningElement, api } from "lwc";

const FIRST_MINUTE = 7 * 60;
const LAST_MINUTE = 21 * 60;
const SLOT_MINUTES = 30;
const ROW_PX = 48;
const PX_PER_MINUTE = ROW_PX / SLOT_MINUTES;

const pad = (n) => String(n).padStart(2, "0");

export default class JourneyTimeline extends LightningElement {
  @api date; // yyyy-MM-dd
  @api visits = [];

  moving;

  get dayStart() {
    const [y, m, d] = (this.date || "").split("-").map(Number);
    return new Date(y, m - 1, d);
  }

  get slots() {
    const slots = [];
    for (let min = FIRST_MINUTE; min < LAST_MINUTE; min += SLOT_MINUTES) {
      const start = new Date(this.dayStart);
      start.setMinutes(min);
      slots.push({
        key: min,
        label: `${pad(Math.floor(min / 60))}:${pad(min % 60)}`,
        start: start.toISOString()
      });
    }
    return slots;
  }

  get gridStyle() {
    return `height:${((LAST_MINUTE - FIRST_MINUTE) / SLOT_MINUTES) * ROW_PX}px`;
  }

  minutesFromMidnight(iso) {
    return (new Date(iso) - this.dayStart) / 60000;
  }

  decorate(visit) {
    const status = visit.status || "Planned";
    return {
      visit,
      id: visit.id,
      overlaps: !!(visit.overlapsWith && visit.overlapsWith.length),
      canMove: status === "Planned" && !visit.allDay
    };
  }

  get allDayVisits() {
    return (this.visits || [])
      .filter((v) => v.allDay)
      .map((v) => this.decorate(v));
  }

  get hasAllDay() {
    return this.allDayVisits.length > 0;
  }

  get timedVisits() {
    const items = (this.visits || [])
      .filter((v) => !v.allDay && v.startTime && v.endTime)
      .map((v) => {
        const startMin = Math.max(
          FIRST_MINUTE,
          Math.min(LAST_MINUTE, this.minutesFromMidnight(v.startTime))
        );
        const endMin = Math.max(
          startMin + SLOT_MINUTES,
          Math.min(LAST_MINUTE, this.minutesFromMidnight(v.endTime))
        );
        return { ...this.decorate(v), startMin, endMin };
      });
    this.assignColumns(items);
    return items.map((item) => {
      const top = (item.startMin - FIRST_MINUTE) * PX_PER_MINUTE;
      const height = (item.endMin - item.startMin) * PX_PER_MINUTE;
      const width = 100 / item.columns;
      return {
        ...item,
        style: `top:${top}px;height:${height}px;left:${item.column * width}%;width:${width}%`
      };
    });
  }

  // Side-by-side layout: items that overlap (transitively) share a cluster;
  // each takes the first free column, and the cluster splits its width evenly.
  assignColumns(items) {
    const sorted = [...items].sort(
      (a, b) => a.startMin - b.startMin || a.endMin - b.endMin
    );
    let cluster = [];
    let columnEnds = [];
    let clusterEnd = -1;
    const close = () => {
      cluster.forEach((i) => {
        i.columns = columnEnds.length;
      });
      cluster = [];
      columnEnds = [];
    };
    sorted.forEach((item) => {
      if (cluster.length && item.startMin >= clusterEnd) {
        close();
      }
      let col = columnEnds.findIndex((end) => end <= item.startMin);
      if (col === -1) {
        col = columnEnds.length;
      }
      columnEnds[col] = item.endMin;
      item.column = col;
      clusterEnd = cluster.length
        ? Math.max(clusterEnd, item.endMin)
        : item.endMin;
      cluster.push(item);
    });
    close();
  }

  get hasMoving() {
    return !!this.moving;
  }

  handleSlotClick(event) {
    this.dispatchEvent(
      new CustomEvent("slotselect", {
        detail: { start: event.currentTarget.dataset.start }
      })
    );
  }

  handleMove(event) {
    const visit = (this.visits || []).find(
      (v) => v.id === event.currentTarget.dataset.id
    );
    if (visit && (visit.status || "Planned") === "Planned") {
      this.moving = visit;
    }
  }

  handleMoveSave(event) {
    const { start, end } = event.detail;
    const visit = this.moving;
    this.moving = undefined;
    if (visit && (visit.status || "Planned") === "Planned") {
      this.dispatchEvent(
        new CustomEvent("visitmove", {
          detail: { eventId: visit.id, start, end }
        })
      );
    }
  }

  handleMoveCancel() {
    this.moving = undefined;
  }

  handleVisitChange(event) {
    event.stopPropagation();
    this.dispatchEvent(
      new CustomEvent("visitchange", { detail: event.detail })
    );
  }
}

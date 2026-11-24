import { LightningElement, api } from "lwc";

export default class JourneyEventForm extends LightningElement {
  @api mode = "create";
  @api eventId;
  @api objectOptions = [];
  @api start;
  @api end;

  subject = "";
  apiName;
  relatedId;
  startValue;
  endValue;
  errorMessage;

  connectedCallback() {
    this.startValue = this.start;
    this.endValue = this.end;
  }

  get isCreate() {
    return this.mode === "create";
  }

  get title() {
    return this.isCreate ? "New visit" : "Change time";
  }

  get options() {
    return (this.objectOptions || []).map((o) => ({
      label: o.label,
      value: o.apiName
    }));
  }

  get hasObject() {
    return !!this.apiName;
  }

  get hasError() {
    return !!this.errorMessage;
  }

  handleSubject(event) {
    this.subject = event.detail.value;
  }

  handleObject(event) {
    this.apiName = event.detail.value;
    this.relatedId = undefined;
  }

  handleRecord(event) {
    this.relatedId = event.detail.recordId;
  }

  handleStart(event) {
    this.startValue = event.detail.value;
  }

  handleEnd(event) {
    this.endValue = event.detail.value;
  }

  validate() {
    if (this.isCreate && !(this.subject || "").trim()) {
      return "Subject is required.";
    }
    if (this.isCreate && !this.relatedId) {
      return "Choose a record for the visit.";
    }
    const start = new Date(this.startValue);
    const end = new Date(this.endValue);
    if (isNaN(start) || isNaN(end)) {
      return "Start and end are required.";
    }
    if (end <= start) {
      return "End must be after start.";
    }
    return undefined;
  }

  handleSave() {
    this.errorMessage = this.validate();
    if (this.errorMessage) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("save", {
        detail: {
          eventId: this.eventId,
          subject: this.isCreate ? this.subject.trim() : undefined,
          relatedId: this.isCreate ? this.relatedId : undefined,
          start: this.startValue,
          end: this.endValue
        }
      })
    );
  }

  handleCancel() {
    this.dispatchEvent(new CustomEvent("cancel"));
  }
}

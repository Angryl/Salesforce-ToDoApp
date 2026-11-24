import { LightningElement, api, wire } from "lwc";
import { getRecord, notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getCurrentLocation, locationErrorMessage } from "c/locationUtil";
import checkInApex from "@salesforce/apex/JourneyController.checkIn";
import checkOutApex from "@salesforce/apex/JourneyController.checkOut";
import SUBJECT from "@salesforce/schema/Event.Subject";
import STATUS from "@salesforce/schema/Event.Visit_Status__c";
import SUMMARY from "@salesforce/schema/Event.Meeting_Summary__c";
import MINUTES from "@salesforce/schema/Event.Time_Spent_Minutes__c";
import LEG_KM from "@salesforce/schema/Event.Distance_From_Previous_Km__c";

const GENERIC_ERROR = "Something went wrong. Please try again.";

export default class JourneyVisitCard extends LightningElement {
  @api recordId;
  @api visit;

  recordData;
  summaryText = "";
  busy = false;
  errorMessage;
  lastAction;

  @wire(getRecord, {
    recordId: "$wireRecordId",
    fields: [SUBJECT, STATUS, SUMMARY, MINUTES, LEG_KM]
  })
  wiredRecord({ data }) {
    if (data) {
      const f = data.fields;
      this.recordData = {
        id: this.recordId,
        subject: f.Subject?.value,
        status: f.Visit_Status__c?.value,
        summary: f.Meeting_Summary__c?.value,
        minutesSpent: f.Time_Spent_Minutes__c?.value,
        legKm: f.Distance_From_Previous_Km__c?.value
      };
    }
  }

  get wireRecordId() {
    return this.visit ? undefined : this.recordId;
  }

  get current() {
    return this.visit || this.recordData || {};
  }

  get eventId() {
    return this.visit ? this.visit.id : this.recordId;
  }

  get subject() {
    return this.current.subject;
  }

  get status() {
    return this.current.status || "Planned";
  }

  get isPlanned() {
    return this.status === "Planned";
  }

  get isCheckedIn() {
    return this.status === "Checked In";
  }

  get isCompleted() {
    return this.status === "Completed";
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get completedSummary() {
    return this.current.summary;
  }

  get timeSpent() {
    const total = this.current.minutesSpent;
    if (total === null || total === undefined) {
      return "";
    }
    const hours = Math.floor(total / 60);
    const mins = Math.round(total % 60);
    return hours > 0 ? `${hours}h ${mins}m` : `${mins}m`;
  }

  get legDistance() {
    const km = this.current.legKm;
    return km === null || km === undefined ? "" : `${Number(km).toFixed(2)} km`;
  }

  get summaryValue() {
    return this.summaryText || this.current.summary || "";
  }

  handleSummaryChange(event) {
    this.summaryText = event.target.value;
  }

  handleCheckIn() {
    return this.run("in");
  }

  handleCheckOut() {
    return this.run("out");
  }

  handleRetry() {
    return this.run(this.lastAction);
  }

  async run(action) {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorMessage = undefined;
    this.lastAction = action;
    try {
      let loc;
      try {
        loc = await getCurrentLocation();
      } catch (e) {
        this.errorMessage = locationErrorMessage(e && e.code);
        return;
      }
      let result;
      try {
        result =
          action === "in"
            ? await checkInApex({ eventId: this.eventId, loc })
            : await checkOutApex({
                eventId: this.eventId,
                loc,
                summary: this.summaryValue
              });
      } catch (e) {
        this.errorMessage = (e && e.body && e.body.message) || GENERIC_ERROR;
        return;
      }
      this.lastAction = undefined;
      this.dispatchEvent(
        new ShowToastEvent({
          variant: "success",
          title: action === "in" ? "Checked in" : "Checked out"
        })
      );
      if (result && result.lowAccuracy) {
        this.dispatchEvent(
          new ShowToastEvent({
            variant: "warning",
            title: "Low GPS accuracy",
            message: "Your location may be off by a few hundred metres."
          })
        );
      }
      if (!this.visit) {
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      }
      this.dispatchEvent(
        new CustomEvent("visitchange", {
          detail: { eventId: this.eventId },
          bubbles: false,
          composed: false
        })
      );
    } finally {
      this.busy = false;
    }
  }
}

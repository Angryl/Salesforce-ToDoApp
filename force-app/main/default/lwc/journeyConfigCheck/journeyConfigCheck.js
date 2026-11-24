import { LightningElement } from "lwc";
import getConfigHealth from "@salesforce/apex/JourneyController.getConfigHealth";

const GENERIC_ERROR = "Unable to check the configuration.";

export default class JourneyConfigCheck extends LightningElement {
  issues = [];
  errorMessage;
  loaded = false;

  connectedCallback() {
    getConfigHealth()
      .then((result) => {
        this.issues = (result || []).map((text, index) => ({
          key: `issue-${index}`,
          text
        }));
        this.errorMessage = undefined;
      })
      .catch((error) => {
        this.errorMessage =
          (error && error.body && error.body.message) || GENERIC_ERROR;
      })
      .finally(() => {
        this.loaded = true;
      });
  }

  get hasError() {
    return this.loaded && !!this.errorMessage;
  }

  get isOk() {
    return this.loaded && !this.errorMessage && this.issues.length === 0;
  }

  get hasIssues() {
    return this.loaded && !this.errorMessage && this.issues.length > 0;
  }
}

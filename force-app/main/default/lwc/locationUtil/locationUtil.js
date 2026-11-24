import { getLocationService } from "lightning/mobileCapabilities";

const SOURCE_MOBILE = "Mobile GPS";
const SOURCE_BROWSER = "Browser";
const DENIED_MOBILE_CODES = [
  "USER_DENIED_PERMISSION",
  "LOCATION_SERVICE_DISABLED"
];

function locationError(code, message) {
  const err = new Error(message);
  err.code = code;
  return err;
}

function toResult(position, source) {
  const { latitude, longitude, accuracy } = position.coords;
  return { latitude, longitude, accuracyMeters: accuracy, source };
}

function mapMobileError(error) {
  if (error && DENIED_MOBILE_CODES.includes(error.code)) {
    return locationError(
      "DENIED",
      "Location permission was denied. Enable location access and try again."
    );
  }
  return locationError("UNAVAILABLE", "Your location could not be determined.");
}

function timeoutError() {
  return locationError("TIMEOUT", "Getting your location took too long.");
}

function getFromMobile(service, timeoutMs) {
  return new Promise((resolve, reject) => {
    // The platform LocationService has no timeout option, so enforce it here.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    const timer = setTimeout(() => reject(timeoutError()), timeoutMs);
    service
      .getCurrentPosition({ enableHighAccuracy: true })
      .then((position) => resolve(toResult(position, SOURCE_MOBILE)))
      .catch((error) => reject(mapMobileError(error)))
      .finally(() => clearTimeout(timer));
  });
}

function getFromBrowser(timeoutMs) {
  return new Promise((resolve, reject) => {
    navigator.geolocation.getCurrentPosition(
      (position) => resolve(toResult(position, SOURCE_BROWSER)),
      (error) => {
        if (error && error.code === 1) {
          reject(
            locationError(
              "DENIED",
              "Location permission was denied. Enable location access and try again."
            )
          );
        } else if (error && error.code === 3) {
          reject(timeoutError());
        } else {
          reject(
            locationError(
              "UNAVAILABLE",
              "Your location could not be determined."
            )
          );
        }
      },
      { enableHighAccuracy: true, timeout: timeoutMs, maximumAge: 0 }
    );
  });
}

/**
 * One-shot location capture. Call only from a user-initiated action; this
 * module never watches or polls position.
 * Rejects with an Error whose `code` is DENIED, UNAVAILABLE or TIMEOUT.
 */
export function getCurrentLocation({ timeoutMs = 15000 } = {}) {
  const service = getLocationService();
  if (service && service.isAvailable()) {
    return getFromMobile(service, timeoutMs);
  }
  if (typeof navigator !== "undefined" && navigator.geolocation) {
    return getFromBrowser(timeoutMs);
  }
  return Promise.reject(
    locationError("UNAVAILABLE", "Location is not available on this device.")
  );
}

const LOCATION_MESSAGES = {
  DENIED:
    "Location permission is off. Allow location for the Salesforce app in your phone settings, then tap Retry.",
  UNAVAILABLE:
    "Couldn't get your location. Move to an open area and tap Retry.",
  TIMEOUT: "Getting your location took too long. Tap Retry."
};
const GENERIC_ERROR = "Something went wrong. Please try again.";

/** User-facing message for a getCurrentLocation rejection code. */
export function locationErrorMessage(code) {
  return LOCATION_MESSAGES[code] || GENERIC_ERROR;
}

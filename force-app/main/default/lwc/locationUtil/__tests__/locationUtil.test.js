import { getLocationService } from "lightning/mobileCapabilities";
import { getCurrentLocation, locationErrorMessage } from "c/locationUtil";

const originalGeolocation = Object.getOwnPropertyDescriptor(
  navigator,
  "geolocation"
);

function setGeolocation(value) {
  Object.defineProperty(navigator, "geolocation", {
    value,
    configurable: true
  });
}

describe("c-location-util getCurrentLocation", () => {
  afterEach(() => {
    getLocationService.mockReset();
    getLocationService.mockReturnValue(undefined);
    if (originalGeolocation) {
      Object.defineProperty(navigator, "geolocation", originalGeolocation);
    } else {
      delete navigator.geolocation;
    }
    jest.useRealTimers();
  });

  it("uses the mobile location service when available", async () => {
    const getCurrentPosition = jest.fn().mockResolvedValue({
      coords: { latitude: 28.61, longitude: 77.2, accuracy: 12.5 }
    });
    getLocationService.mockReturnValue({
      isAvailable: () => true,
      getCurrentPosition
    });

    const result = await getCurrentLocation();

    expect(getCurrentPosition).toHaveBeenCalledWith({
      enableHighAccuracy: true
    });
    expect(result).toEqual({
      latitude: 28.61,
      longitude: 77.2,
      accuracyMeters: 12.5,
      source: "Mobile GPS"
    });
  });

  it("falls back to the browser when the mobile service is unavailable", async () => {
    getLocationService.mockReturnValue({ isAvailable: () => false });
    const getCurrentPosition = jest.fn((success) =>
      success({
        coords: { latitude: 19.07, longitude: 72.87, accuracy: 30 }
      })
    );
    setGeolocation({ getCurrentPosition });

    const result = await getCurrentLocation({ timeoutMs: 5000 });

    expect(getCurrentPosition).toHaveBeenCalledWith(
      expect.any(Function),
      expect.any(Function),
      { enableHighAccuracy: true, timeout: 5000, maximumAge: 0 }
    );
    expect(result).toEqual({
      latitude: 19.07,
      longitude: 72.87,
      accuracyMeters: 30,
      source: "Browser"
    });
  });

  it("rejects DENIED when the browser permission is denied", async () => {
    setGeolocation({
      getCurrentPosition: (success, error) =>
        error({ code: 1, message: "denied" })
    });
    await expect(getCurrentLocation()).rejects.toMatchObject({
      code: "DENIED"
    });
  });

  it("rejects UNAVAILABLE for browser position unavailable", async () => {
    setGeolocation({
      getCurrentPosition: (success, error) =>
        error({ code: 2, message: "unavailable" })
    });
    await expect(getCurrentLocation()).rejects.toMatchObject({
      code: "UNAVAILABLE"
    });
  });

  it("rejects TIMEOUT for browser timeout", async () => {
    setGeolocation({
      getCurrentPosition: (success, error) =>
        error({ code: 3, message: "timeout" })
    });
    await expect(getCurrentLocation()).rejects.toMatchObject({
      code: "TIMEOUT"
    });
  });

  it.each(["USER_DENIED_PERMISSION", "LOCATION_SERVICE_DISABLED"])(
    "maps mobile error %s to DENIED",
    async (code) => {
      getLocationService.mockReturnValue({
        isAvailable: () => true,
        getCurrentPosition: jest.fn().mockRejectedValue({ code })
      });
      await expect(getCurrentLocation()).rejects.toMatchObject({
        code: "DENIED"
      });
    }
  );

  it("maps other mobile errors to UNAVAILABLE", async () => {
    getLocationService.mockReturnValue({
      isAvailable: () => true,
      getCurrentPosition: jest
        .fn()
        .mockRejectedValue({ code: "SOMETHING_ELSE" })
    });
    await expect(getCurrentLocation()).rejects.toMatchObject({
      code: "UNAVAILABLE"
    });
  });

  it("rejects UNAVAILABLE when neither source exists", async () => {
    setGeolocation(undefined);
    const err = await getCurrentLocation().catch((e) => e);
    expect(err).toBeInstanceOf(Error);
    expect(err.code).toBe("UNAVAILABLE");
    expect(err.message).toBeTruthy();
  });

  it("rejects TIMEOUT when the mobile service never answers", async () => {
    jest.useFakeTimers();
    getLocationService.mockReturnValue({
      isAvailable: () => true,
      getCurrentPosition: jest.fn(() => new Promise(() => {}))
    });

    let caught;
    const pending = getCurrentLocation({ timeoutMs: 1000 }).catch((e) => {
      caught = e;
    });
    jest.advanceTimersByTime(1000);
    await pending;
    expect(caught).toBeInstanceOf(Error);
    expect(caught.code).toBe("TIMEOUT");
  });
});

describe("c-location-util locationErrorMessage", () => {
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
  ])("maps %s to its message", (code, message) => {
    expect(locationErrorMessage(code)).toBe(message);
  });

  it("falls back to a generic message", () => {
    expect(locationErrorMessage("WHAT")).toBe(
      "Something went wrong. Please try again."
    );
    expect(locationErrorMessage(undefined)).toBe(
      "Something went wrong. Please try again."
    );
  });
});

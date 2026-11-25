// Pure helpers for the Waydroid shell integration.
//
// `waydroid status` is tab-separated and prints only the keys that apply to
// the current session state. The shell service keeps this parsing free of
// process/QML dependencies so it can be tested headlessly.

function parseStatus(text) {
    const result = {
        session: "",
        container: "",
        vendorType: "",
        ipAddress: "",
        sessionUser: "",
        waylandDisplay: ""
    };
    const keys = {
        "Session": "session",
        "Container": "container",
        "Vendor type": "vendorType",
        "IP address": "ipAddress",
        "Session user": "sessionUser",
        "Wayland display": "waylandDisplay"
    };
    for (const line of String(text ?? "").split(/\r?\n/)) {
        const colon = line.indexOf(":");
        if (colon < 0) continue;
        const key = line.slice(0, colon).trim();
        const target = keys[key];
        if (target !== undefined) result[target] = line.slice(colon + 1).trim();
    }
    return result;
}

function parseBootCompleted(text) {
    return String(text ?? "").trim() === "1";
}

function appsAvailable(status, bootCompleted) {
    return status?.session === "RUNNING" &&
           status?.container === "RUNNING" &&
           bootCompleted === true;
}

function statusText(status, bootCompleted) {
    if (status?.session !== "RUNNING") return "Stopped";
    if (status?.container !== "RUNNING") return "Container stopped";
    if (bootCompleted !== true) return "Session running, guest not booted";
    return "Apps ready";
}

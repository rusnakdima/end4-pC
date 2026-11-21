// Escape in the settings window always protects the keybind editor: it can
// cancel a capture or close the edit form, but it never closes settings.
//
// The QML handlers (settings key scope, dashboard and keyboard page) all
// report the context to this pure function and act on the returned decision,
// so the one user-facing rule lives in one place and can be tested headlessly.
// No Qt or Quickshell imports, like the other modules/common/functions files.

function decide(context) {
    const source = String(context?.source ?? "");
    const decision = {
        closeSettings: false,
        accept: false,
        closeForm: false,
        stopCapture: false,
        back: false
    };

    if (source === "global") {
        decision.accept = true;
        return decision;
    }

    if (source === "dashboard") {
        decision.accept = true;
        decision.back = !!(context?.isPresetsPage && context?.hasSelection);
        return decision;
    }

    if (source === "capture") {
        if (context?.capturing === true) {
            decision.accept = true;
            decision.stopCapture = true;
        } else if (context?.formOpen === true) {
            decision.accept = true;
            decision.closeForm = true;
        }
        return decision;
    }

    return decision;
}

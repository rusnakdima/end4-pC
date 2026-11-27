// Tab/Backtab in the settings window cycle pages only when the active content
// exposes a page list. The categories layout navigates with its own rail and
// page list, so it exposes none and Tab must stay available for native focus
// navigation. Keeping the decision here makes that rule headlessly testable.

function decide(pages, currentPage, direction) {
    const count = Array.isArray(pages) ? pages.length : 0;
    if (count === 0)
        return { accept: false, currentPage: currentPage ?? 0 };
    const step = direction === "back" ? -1 : 1;
    const next = (((currentPage ?? 0) + step) % count + count) % count;
    return { accept: true, currentPage: next };
}

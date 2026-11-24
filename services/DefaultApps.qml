pragma Singleton

import QtQuick
import Quickshell
import qs.services
import "../modules/common/functions/DefaultAppsStore.js" as Store

/*
 * Default apps = quick-launch targets, not XDG mime associations.
 *
 * Every role owns ids from the frozen catalog's Apps section. Picking an app
 * writes a command override for all of those ids through ManagedKeybinds,
 * which regenerates the Lua files and the command bridge. With no override
 * the row shows the first installed app of the catalog's fallback chain.
 * There is no second settings file: the overlay is the only state.
 */
Singleton {
    id: root

    function isOverridden(bindId) {
        return Store.isOverriddenIn(ManagedKeybinds.overlay, bindId);
    }

    function commandFor(bindId) {
        return Store.commandForOverlay(ManagedKeybinds.overlay, bindId);
    }

    function comboFor(bindId) {
        const override = ManagedKeybinds.overlay?.overrides?.[bindId];
        const combo = String(override?.combo ?? "");
        if (combo !== "") return combo;
        return String(ManagedKeybinds.catalogBind(bindId)?.combo ?? "");
    }

    // The command is a shell line; the first word is the executable that
    // desktop entries can be matched against.
    function entryForCommand(command) {
        const normalized = Store.commandFromExec(command);
        if (normalized === "") return null;
        return DesktopEntries.heuristicLookup(normalized.split(/\s+/)[0]) ?? null;
    }

    function fallbackEntry(role) {
        for (const hint of (role?.hints ?? [])) {
            const entry = DesktopEntries.heuristicLookup(hint);
            if (entry !== null && entry !== undefined) return entry;
        }
        return null;
    }

    readonly property var roles: Store.ROLES.map(role => {
        const bindId = role.bindIds[0];
        const overridden = root.isOverridden(bindId);
        const command = root.commandFor(bindId);
        const entry = overridden ? root.entryForCommand(command) : root.fallbackEntry(role);
        return Object.assign({}, role, {
            command: command,
            appName: String(entry?.name ?? ""),
            appIcon: String(entry?.icon ?? ""),
            combo: root.comboFor(bindId),
            overridden: overridden
        });
    })

    function roleFor(id) {
        return root.roles.find(role => role.id === id) ?? null;
    }

    // An entry is a Quickshell DesktopEntry. Reset is expressed as
    // choose(role, null) so the page has one action for both outcomes.
    function choose(roleId, entry) {
        const role = Store.roleById(roleId);
        if (role === null) return { ok: false, error: "unknown-role" };

        if (entry === null || entry === undefined) {
            let resetError = "";
            for (const id of role.bindIds) {
                const result = ManagedKeybinds.clearOverride(id);
                // A bind that was never overridden is already at its default.
                if (!result.ok && result.error !== "not-found" && resetError === "")
                    resetError = result.error;
            }
            return { ok: resetError === "", error: resetError };
        }

        const command = Store.commandFromExec(entry.execString);
        if (command === "") return { ok: false, error: "empty-command" };

        let firstError = "";
        for (const id of role.bindIds) {
            const result = ManagedKeybinds.updateCatalogBind(id, { command: command });
            if (!result.ok && firstError === "") firstError = result.error;
        }
        return { ok: firstError === "", error: firstError, command: command };
    }
}

pragma Singleton

import QtQuick
import Quickshell

/**
 * Pure helpers for Windows-style display projection on Hyprland.
 *
 * The functions here never touch the compositor or the filesystem: given a
 * list of monitor descriptors they only compute the set of changes that
 * realizes a projection mode. Keeping the layout math here makes it testable
 * with the hosted QML suite, and keeps MonitorConfigOption responsible only
 * for applying and persisting the result.
 *
 * A monitor descriptor is the object MonitorConfigOption exposes, with the
 * optional `base*` fields holding the layout to restore when leaving a mode:
 *   { name, description, currentMode, x, y, scale, transform,
 *     baseMode, baseX, baseY, baseScale, baseTransform }
 */
Singleton {
    id: root

    readonly property var modes: [
        { value: "pc",        label: "PC screen only",     icon: "laptop" },
        { value: "duplicate", label: "Duplicate",          icon: "content_copy" },
        { value: "extend",    label: "Extend",             icon: "desktop_windows" },
        { value: "second",    label: "Second screen only", icon: "tv" }
    ]

    readonly property var placements: [
        { value: "right", label: "Right",  icon: "arrow_forward" },
        { value: "left",  label: "Left",   icon: "arrow_back" },
        { value: "above", label: "Above",  icon: "arrow_upward" },
        { value: "below", label: "Below",  icon: "arrow_downward" }
    ]

    /** The laptop panel is the projection source. Ports and EDID text are
     *  both used: some docks expose the internal panel with a generic name. */
    function isInternal(monitor) {
        if (!monitor) return false
        const name = String(monitor.name ?? "")
        const desc = String(monitor.description ?? "")
        if (/^(eDP|LVDS|DSI|EDP)-?/i.test(name)) return true
        return /\b(eDP|LVDS|DSI)\b/i.test(desc)
    }

    function parseMode(value) {
        const match = String(value ?? "").match(/(\d+)x(\d+)@([\d.]+)/)
        if (!match) return null
        return { width: parseInt(match[1]), height: parseInt(match[2]), hz: parseFloat(match[3]) }
    }

    /** Width/height after rotation, before scale (what hyprctl reports). */
    function logicalWidth(monitor) {
        if (!monitor) return 0
        const t = Number(monitor.transform ?? 0)
        return (t === 1 || t === 3) ? Number(monitor.height ?? 0) : Number(monitor.width ?? 0)
    }

    function logicalHeight(monitor) {
        if (!monitor) return 0
        const t = Number(monitor.transform ?? 0)
        return (t === 1 || t === 3) ? Number(monitor.width ?? 0) : Number(monitor.height ?? 0)
    }

    /** Hyprland positions are in scaled coordinates. */
    function layoutWidth(monitor) {
        const scale = Number(root.baseScale(monitor)) || 1
        return Math.round(root.logicalWidth(monitor) / scale)
    }

    function layoutHeight(monitor) {
        const scale = Number(root.baseScale(monitor)) || 1
        return Math.round(root.logicalHeight(monitor) / scale)
    }

    function baseMode(monitor)   { return monitor?.baseMode   ?? monitor?.currentMode ?? "preferred" }
    function baseScale(monitor)  { return monitor?.baseScale  ?? monitor?.scale ?? 1 }
    function baseTransform(monitor) { return monitor?.baseTransform ?? monitor?.transform ?? 0 }
    function baseX(monitor)      { return monitor?.baseX ?? monitor?.x ?? 0 }
    function baseY(monitor)      { return monitor?.baseY ?? monitor?.y ?? 0 }

    /** A full monitor config block using the saved values, so switching back
     *  from a projection mode restores the layout from before the switch. */
    function fullChanges(monitor) {
        return {
            disabled: false,
            mirror: "",
            currentMode: root.baseMode(monitor),
            scale: Number(root.baseScale(monitor)),
            transform: Number(root.baseTransform(monitor)),
            x: Number(root.baseX(monitor)),
            y: Number(root.baseY(monitor))
        }
    }

    /** For Duplicate: reuse the source's mode only when the target advertises
     *  it; otherwise fall back to the target's own preferred/current mode. */
    function duplicateMode(source, target) {
        const wanted = root.parseMode(source?.currentMode ?? source?.baseMode)
        if (wanted) {
            const modes = target?.availableModes ?? []
            for (let i = 0; i < modes.length; ++i) {
                const candidate = root.parseMode(modes[i])
                if (candidate && candidate.width === wanted.width
                        && candidate.height === wanted.height
                        && Math.abs(candidate.hz - wanted.hz) < 1)
                    return modes[i]
            }
        }
        return target?.currentMode ?? target?.baseMode ?? "preferred"
    }

    function nextPosition(cursorX, cursorY, monitor, placement) {
        const w = root.layoutWidth(monitor)
        const h = root.layoutHeight(monitor)
        switch (placement) {
            case "left":  return { x: cursorX - w, y: cursorY, nextX: cursorX - w, nextY: cursorY }
            case "above": return { x: cursorX, y: cursorY - h, nextX: cursorX, nextY: cursorY - h }
            case "below": return { x: cursorX, y: cursorY, nextX: cursorX, nextY: cursorY + h }
            default:      return { x: cursorX, y: cursorY, nextX: cursorX + w, nextY: cursorY }
        }
    }

    /**
     * Compute the projection layout.
     * Returns [{ name, changes }, ...] — one patch per connected monitor.
     * `mode` is one of pc | duplicate | extend | second; `placement` is
     * right | left | above | below and only affects extend/second.
     */
    function project(monitors, mode, placement) {
        const list = (monitors ?? []).filter(m => m && m.name)
        if (list.length === 0) return []

        const internalIndex = list.findIndex(root.isInternal)
        const primaryIndex = internalIndex >= 0 ? internalIndex : 0
        const primary = list[primaryIndex]
        const others = list.filter((m, i) => i !== primaryIndex)
        const place = placement ?? "right"
        const patches = []

        if (mode === "pc") {
            patches.push({ name: primary.name, changes: root.fullChanges(primary) })
            for (const external of others)
                patches.push({ name: external.name, changes: { disabled: true, mirror: "" } })
            return patches
        }

        if (mode === "duplicate") {
            patches.push({ name: primary.name, changes: root.fullChanges(primary) })
            for (const external of others) {
                patches.push({
                    name: external.name,
                    changes: {
                        disabled: false,
                        mirror: primary.name,
                        currentMode: root.duplicateMode(primary, external),
                        scale: Number(root.baseScale(primary)),
                        transform: Number(root.baseTransform(primary)),
                        x: Number(root.baseX(primary)),
                        y: Number(root.baseY(primary))
                    }
                })
            }
            return patches
        }

        // Extend and Second screen only share the chaining logic; they differ
        // in whether the internal panel stays on and where the chain starts.
        const secondaryOnly = mode === "second"
        if (secondaryOnly)
            patches.push({ name: primary.name, changes: { disabled: true, mirror: "" } })
        else
            patches.push({ name: primary.name, changes: root.fullChanges(primary) })

        let cursorX = 0
        let cursorY = 0
        if (!secondaryOnly) {
            if (place === "right")  cursorX = Number(root.baseX(primary)) + root.layoutWidth(primary)
            if (place === "left")   cursorX = Number(root.baseX(primary))
            if (place === "below")  cursorY = Number(root.baseY(primary)) + root.layoutHeight(primary)
            if (place === "above")  cursorY = Number(root.baseY(primary))
        }

        for (const external of others) {
            const pos = root.nextPosition(cursorX, cursorY, external, place)
            cursorX = pos.nextX
            cursorY = pos.nextY
            const changes = root.fullChanges(external)
            changes.x = pos.x
            changes.y = pos.y
            if (secondaryOnly && patches.length === 1) {
                changes.x = 0
                changes.y = 0
            }
            patches.push({ name: external.name, changes: changes })
        }
        return patches
    }
}

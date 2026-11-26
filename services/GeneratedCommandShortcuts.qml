pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.modules.common.functions

/**
 * Runs the shell commands that sync.sh generates for Hyprland binds.
 *
 * Hyprland 0.57.2 made hl.dsp.exec_cmd() a no-op, so the generated binds
 * dispatch hl.dsp.global("quickshell:runCommand:<id>") instead. This service
 * owns the other half: it reads state/generated-commands.json and registers
 * one global shortcut per id, which runs that id's stored command.
 *
 * The file is watched, so adding/removing a command while the shell is
 * running updates the shortcuts without a restart. reload() is public for
 * the same reason (and for probes that recreate the file).
 *
 * Ids are only ever taken from the JSON. runCommand() refuses anything that
 * is not a key of the parsed map, so no other source can inject a command.
 */
Singleton {
    id: root

    readonly property string commandsPath: FileUtils.trimFileProtocol(
        Quickshell.shellPath("state/generated-commands.json"))

    // qsConfig is the Hyprland env var that points at this config checkout.
    // Generated commands use $qsConfig the way any other Hyprland command
    // does; Hyprland expands it for normal binds, so we do the same here.
    readonly property string qsConfig: "end4-pC"

    // id -> { command, description, category }, straight from the JSON.
    property var commands: ({})
    // Avoid rebuilding the shortcuts when a reread finds the same content.
    property string lastSignature: ""

    // The only ids allowed to become shortcuts or be executed.
    readonly property var shortcutIds: Object.keys(root.commands).sort()
    // Unload every command shortcut while a keybind is being recorded, so
    // pressing the combination cannot run the command it is bound to.
    readonly property var activeShortcutIds: GlobalStates.keybindCaptureArmed
        ? [] : root.shortcutIds

    Component.onCompleted: root.reload()

    FileView {
        id: commandsFile
        path: root.commandsPath
        preload: true
        watchChanges: true
        printErrors: false

        onLoaded: root.reload()
        onFileChanged: root.reload()
        onLoadFailed: error => {
            // A missing file is the normal state before the first sync; a
            // file that was removed must not leave stale shortcuts behind.
            if (error !== FileViewError.FileNotFound)
                console.log("[gen-cmds] load failed for " + root.commandsPath + ": " + error);
            root.clear();
        }
    }

    // FileView.watchChanges does not reliably report a file that is created
    // after startup (the common case here: sync.sh writes the first version
    // while the shell is already running). A quiet reread covers that gap;
    // reload() is a no-op when the parsed content has not changed.
    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: commandsFile.reload()
    }

    // One shortcut per generated id. Instantiator (not Repeater) is used
    // because GlobalShortcut is a non-visual type. Rebuilding the model also
    // unregisters shortcuts whose ids disappeared from the JSON.
    Instantiator {
        id: shortcutInstantiator
        model: root.activeShortcutIds

        delegate: GlobalShortcut {
            required property string modelData

            // Hyprland's global-shortcut protocol prefixes the client appid,
            // so this registers as quickshell:runCommand:<id> — the name the
            // generated Hyprland binds dispatch to.
            name: "runCommand:" + modelData
            description: root.commands[modelData]?.description ?? ""
            onPressed: root.runCommand(modelData)
        }
    }

    // Number of registered shortcut objects; useful when probing a reload.
    readonly property int shortcutCount: shortcutInstantiator.count

    // Drop every shortcut. Used when the file disappears or becomes invalid.
    function clear() {
        if (root.lastSignature === "{}") return;
        root.lastSignature = "{}";
        root.commands = ({});
    }

    // Parse the JSON again. Safe to call at any time; a bad file clears the
    // map instead of leaving shortcuts pointing at stale commands.
    function reload() {
        let raw;
        try {
            raw = commandsFile.text() ?? "";
        } catch (e) {
            // Not loaded yet (the FileView signals will call us again).
            return;
        }
        if (raw.trim() === "") return;

        let data;
        try {
            data = JSON.parse(raw);
        } catch (e) {
            console.log("[gen-cmds] cannot parse " + root.commandsPath + ": " + e);
            root.clear();
            return;
        }
        if (data === null || typeof data !== "object" || Array.isArray(data)) {
            console.log("[gen-cmds] " + root.commandsPath + " is not an object");
            root.clear();
            return;
        }

        const parsed = {};
        for (const id of Object.keys(data)) {
            const entry = data[id];
            if (typeof id !== "string" || id.length === 0) continue;
            if (entry === null || typeof entry !== "object" || Array.isArray(entry)) continue;
            if (typeof entry.command !== "string" || entry.command.trim() === "") continue;

            parsed[id] = {
                command: entry.command,
                description: typeof entry.description === "string" ? entry.description : "",
                category: typeof entry.category === "string" ? entry.category : ""
            };
        }
        const signature = JSON.stringify(parsed);
        if (signature === root.lastSignature) return;
        root.lastSignature = signature;
        root.commands = parsed;
        console.log("[gen-cmds] loaded " + Object.keys(parsed).length
            + " command(s) from " + root.commandsPath);
    }

    // Expand the Hyprland-style variables in a generated command locally.
    // Everything else (including $1, $(...), ...) is left for bash.
    function expand(command) {
        const home = Quickshell.env("HOME") || "";
        return String(command)
            .replace(/\$\{HOME\}|\$HOME/g, home)
            .replace(/\$\{qsConfig\}|\$qsConfig/g, root.qsConfig);
    }

    // Run a generated command by id. Unknown ids are rejected: only keys
    // read from generated-commands.json can reach this point.
    function runCommand(id) {
        if (typeof id !== "string" || !Object.prototype.hasOwnProperty.call(root.commands, id)) {
            console.log("[gen-cmds] refusing unknown id: " + id);
            return false;
        }

        const expanded = root.expand(root.commands[id].command);
        const proc = runnerComponent.createObject(root, {
            commandId: id,
            command: ["bash", "-lc", expanded],
            running: true
        });
        if (proc === null) {
            console.log("[gen-cmds] could not create a process for " + id);
            return false;
        }
        console.log("[gen-cmds] run " + id + ": " + expanded);
        return true;
    }

    // Public entry point for manual/probe runs. Same guard as onPressed.
    function testRun(id) {
        return root.runCommand(id);
    }

    // Each invocation gets its own process so a long running command cannot
    // block or replace another one. The process removes itself on exit.
    property Component runnerComponent: Component {
        Process {
            id: runner
            required property string commandId
            property string errorText: ""

            stderr: StdioCollector {
                onStreamFinished: runner.errorText += text
            }

            onExited: (exitCode, exitStatus) => {
                if (exitCode !== 0) {
                    console.log("[gen-cmds] " + runner.commandId + " exited with "
                        + exitCode + ": " + runner.errorText.trim());
                }
                runner.destroy();
            }
        }
    }
}

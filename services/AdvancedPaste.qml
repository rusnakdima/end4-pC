pragma Singleton
pragma ComponentBehavior: Bound

import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Advanced Paste — the clipboard transform hub.
 *
 * Reads the current clipboard, detects its format (JSON, Markdown, URL, code,
 * CSV, …) and rewrites it into a chosen format before pasting it back into the
 * focused application. All local transforms run through a stdlib-only Python
 * helper so the feature works completely offline. The optional "AI" transform
 * uses the existing Ai singleton and falls back to a local transform whenever
 * no API key is configured or the request fails.
 *
 * UI lives in modules/ii/advancedPaste. Trigger with the compositor global
 * shortcut "advancedPaste" (bind it in Hyprland) or:
 *   qs ipc call advancedPaste toggle
 */
Singleton {
    id: root

    property bool open: false
    property string sourceText: ""
    property var detection: ({ primary: "text", candidates: [], language: null, length: 0 })
    property string transform: "plain"
    property string aiResult: ""
    property bool aiBusy: false
    property real anchorX: -1
    property real anchorY: -1

    readonly property string scriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/clipboard/advanced_paste.py`)
    readonly property real pasteDelay: Config.options?.advancedPaste?.pasteDelay ?? 0.08
    readonly property string pressPasteCommand: Config.options?.advancedPaste?.pasteCommand
        ?? "ydotool key -d 1 29:1 47:1 47:0 29:0"

    signal opened()
    signal closed()

    // ----- generic shell-job runner ------------------------------------------------

    property var jobQueue: []
    property bool jobRunning: false

    function _run(commandLine, callback) {
        root.jobQueue.push({ command: commandLine, callback: callback });
        root._pump();
    }

    function _pump() {
        if (root.jobRunning || root.jobQueue.length === 0) return;
        const job = root.jobQueue.shift();
        root.jobRunning = true;
        runner.resultText = "";
        runner.callback = job.callback;
        runner.command = ["bash", "-c", job.command];
        runner.running = true;
    }

    Process {
        id: runner
        property string resultText: ""
        property var callback: null
        stdout: SplitParser {
            onRead: (line) => {
                runner.resultText += line + "\n";
            }
        }
        onExited: (exitCode) => {
            const cb = runner.callback;
            const result = runner.resultText.replace(/\n$/, "");
            runner.callback = null;
            root.jobRunning = false;
            if (cb) cb(result, exitCode);
            root._pump();
        }
    }

    function _py(args, text) {
        return `printf '%s' '${StringUtils.shellSingleQuoteEscape(text)}' | python3 -I '${root.scriptPath}' ${args}`;
    }

    // ----- lifecycle ---------------------------------------------------------------

    function toggle(): void {
        if (root.open || GlobalStates.advancedPasteOpen) root.close();
        else root.openFromClipboard();
    }

    function openFromClipboard(): void {
        root._locateCursor(() => {
            root._run("wl-paste -n 2>/dev/null || true", (clipboardText) => {
                const text = clipboardText.replace(/\n$/, "");
                if (text.trim().length === 0) {
                    root.close();
                    return;
                }
                root._openWithText(text);
            });
        });
    }

    // Used by the OCR fold-in: open the popup with a supplied string instead of
    // the clipboard contents.
    function openWithText(text): void {
        root._locateCursor(() => root._openWithText(text.replace(/\n$/, "")));
    }

    function _openWithText(text): void {
        if (text.trim().length === 0) {
            root.close();
            return;
        }
        root.sourceText = text;
        root.aiResult = "";
        root.aiBusy = false;
        root.transform = Config.options?.advancedPaste?.defaultTransform ?? "plain";
        root.open = true;
        GlobalStates.advancedPasteOpen = true;
        autoCloseTimer.restart();
        root.opened();
        root._run(root._py("detect", text), (result) => {
            try {
                root.detection = JSON.parse(result);
            } catch (error) {
                root.detection = { primary: "text", candidates: [], language: null, length: text.length };
            }
        });
    }

    function _locateCursor(done): void {
        if (WM.compositor !== "hyprland") {
            root.anchorX = -1;
            root.anchorY = -1;
            done();
            return;
        }
        root._run("hyprctl cursorpos -j 2>/dev/null || echo '{}'", (result) => {
            try {
                const point = JSON.parse(result);
                root.anchorX = Number(point.x) || -1;
                root.anchorY = Number(point.y) || -1;
            } catch (error) {
                root.anchorX = -1;
                root.anchorY = -1;
            }
            done();
        });
    }

    function close(): void {
        // Always clear the window state, even if the internal flag already got
        // reset — otherwise a desync leaves an invisible fullscreen keyboard
        // grab in place and the user cannot type anywhere.
        const wasOpen = root.open || GlobalStates.advancedPasteOpen;
        root.open = false;
        GlobalStates.advancedPasteOpen = false;
        root.aiBusy = false;
        autoCloseTimer.stop();
        if (wasOpen) root.closed();
    }

    function forceClose(): void {
        root.jobQueue = [];
        root.jobRunning = false;
        runner.running = false;
        root.close();
    }

    // Safety net: never hold the keyboard forever, even if focus handling
    // fails or the popup is left open by mistake.
    Timer {
        id: autoCloseTimer
        interval: 20000
        repeat: false
        onTriggered: root.close()
    }

    // ----- transforms --------------------------------------------------------------

    function applyTransform(name, aiPrompt): void {
        if (name === "ai") {
            root.runAiTransform(aiPrompt ?? root.defaultAiPrompt());
            return;
        }
        root._run(root._py(`convert ${name}`, root.sourceText), (result) => root.commit(result));
    }

    function defaultAiPrompt(): string {
        return Config.options?.advancedPaste?.aiPrompt ?? "Rewrite this text clearly and concisely.";
    }

    function commitAiResult(): void {
        if (root.aiResult.length === 0) return;
        root._run(root._py("ai-clean", root.aiResult), (result) => root.commit(result));
    }

    function commit(text): void {
        if (text.length === 0) {
            root.close();
            return;
        }
        const command = `printf '%s' '${StringUtils.shellSingleQuoteEscape(text)}' | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`;
        root.close();
        Quickshell.execDetached(["bash", "-c", command]);
    }

    // ----- AI (optional, with offline fallback) ------------------------------------

    function _offlineFallback(prompt): void {
        const lower = (prompt ?? "").toLowerCase();
        let transform = "plain";
        if (/markdown|format|heading|bold|table/.test(lower)) transform = "markdown";
        else if (/json|escape|structur/.test(lower)) transform = "json_escape";
        else if (/upper|capital/.test(lower)) transform = "upper";
        else if (/lower/.test(lower)) transform = "lower";
        root._run(root._py(`convert ${transform}`, root.sourceText), (result) => {
            root.aiResult = result;
            root.aiBusy = false;
        });
    }

    function runAiTransform(prompt): void {
        root.aiResult = "";
        if (!Ai.currentModelHasApiKey || !Ai.models?.[Ai.currentModelId]) {
            root._offlineFallback(prompt);
            return;
        }

        root.aiBusy = true;
        const savedIds = Ai.messageIDs.slice();
        const savedByID = Object.assign({}, Ai.messageByID);
        const savedTool = Ai.currentTool;

        Ai.currentTool = "none";
        Ai.clearMessages();
        Ai.postResponseHook = () => {
            let content = "";
            const ids = Ai.messageIDs.slice();
            for (let i = ids.length - 1; i >= 0; i--) {
                const message = Ai.messageByID[ids[i]];
                if (message && message.role === "assistant") {
                    content = message.content || "";
                    break;
                }
            }
            Ai.messageIDs = savedIds;
            Ai.messageByID = savedByID;
            Ai.currentTool = savedTool;
            root.aiResult = content || root.sourceText;
            root.aiBusy = false;
        };
        Ai.sendUserMessage(
            `${prompt}\n\nReturn ONLY the transformed text, with no explanation, headings or commentary.\n\nText to transform:\n${root.sourceText}`
        );
    }

    // ----- external control --------------------------------------------------------

    IpcHandler {
        target: "advancedPaste"

        function toggle(): void { root.toggle() }
        function open(): void { if (!root.open) root.openFromClipboard() }
        function hide(): void { root.forceClose() }
        function setSource(text: string): void { root.openWithText(text) }
    }

    CompositorGlobalShortcut {
        name: "advancedPaste"
        description: "Advanced Paste — paste clipboard text in another format"
        onPressed: root.toggle()
    }
}

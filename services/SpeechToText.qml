pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Drives the Whisper speech-to-text backend (scripts/ai/stt/stt.py).
 *
 * The backend captures the microphone until a stop-marker file appears and
 * then transcribes the recording, printing exactly one line of JSON:
 *   {"text": "...", "language": "en", "duration": 1.23}
 * or, on failure:
 *   {"error": "..."}
 */
Singleton {
    id: root

    // Public state
    readonly property bool enabled: Config.options.stt.enabled
    readonly property bool recording: root.currentState === "recording"
    readonly property bool transcribing: root.currentState === "transcribing"
    readonly property bool busy: root.recording || root.transcribing
    readonly property string state: root.currentState
    readonly property bool disabled: !root.enabled
    readonly property string transcript: root.transcriptValue
    readonly property string error: root.errorValue
    readonly property int elapsedSeconds: root.elapsed
    readonly property string modelName: Config.options.stt.model

    // Bound copies of STT config for reactive change handling
    readonly property bool sttEnabled: Config.options.stt.enabled
    readonly property string sttModel: Config.options.stt.model
    readonly property string sttLanguage: Config.options.stt.language
    readonly property string sttDevice: Config.options.stt.device
    readonly property string sttComputeType: Config.options.stt.computeType
    readonly property string sttSource: Config.options.stt.source
    readonly property int sttMaxSeconds: Config.options.stt.maxSeconds
    readonly property string sttOutput: Config.options.stt.output
    readonly property bool sttStreaming: Config.options.stt.streaming

    // "0:07" — shared by the bar button and the listening pill.
    readonly property string elapsedLabel: {
        const minutes = Math.floor(root.elapsed / 60);
        const seconds = root.elapsed % 60;
        return `${minutes}:${seconds < 10 ? "0" : ""}${seconds}`;
    }

    // Delivery target for the current recording. Empty means "use the
    // configured output"; the AI chat mic sets "chat" for its own recordings.
    property string sessionTarget: ""
    readonly property string deliveryMode: root.sessionTarget !== "" ? root.sessionTarget : root.sttOutput

    // Live dictation only makes sense when the transcript is typed or sent to
    // the chat while speaking; clipboard-only mode stays one-shot.
    readonly property bool liveTyping: root.sttStreaming
        && (root.deliveryMode === "type" || root.deliveryMode === "both" || root.deliveryMode === "chat")

    // Internals
    property string currentState: "idle"
    property string transcriptValue: ""
    property string errorValue: ""
    property int elapsed: 0

    // Recording history: list of {id, timestamp, state, transcript, duration}
    property var recordings: []

    readonly property string captureDir: FileUtils.trimFileProtocol(`${Directories.state}/user/stt`)
    property string wavPath: ""
    property string stopPath: ""

    property string pendingText: ""
    property bool pendingHasText: false
    property string pendingError: ""
    property string stderrText: ""

    // Streaming session state
    property int streamedSegments: 0
    property string segmentBuffer: ""
    property string detectedLanguage: ""
    property var insertQueue: []
    property bool insertBusy: false
    property bool insertErrorNotified: false
    property bool insertQueueWarned: false
    property bool insertTimedOut: false

    // Each backend process is tagged with the generation it was started for.
    // Events from an older (killed) process must not overwrite the state of a
    // newer recording.
    property int captureGeneration: 0

    // The backend transcribes after the capture ends, so the process stays alive
    // for as long as the inference takes (up to 5 minutes of audio, which on a
    // CPU with the large model can take several minutes). Only kill it when it
    // clearly hangs.
    property int stopTimeoutMs: 600000

    signal transcriptReady(string text)
    signal transcriptSegment(string text)

    onEnabledChanged: {
        // Leaving the "disabled" state must not keep a stale error message around.
        if (root.enabled && root.currentState === "disabled") {
            root.currentState = "idle";
            root.errorValue = "";
        }
        // When STT is disabled, stop any active session. An in-flight
        // transcription is killed outright and its stale exit is ignored by
        // the generation guard, so "disabled" stays sticky until re-enabled.
        if (!root.enabled) {
            if (root.recording) {
                root.stopRecording();
            } else if (root.transcribing) {
                sttProcess.generation = -1;
                sttProcess.running = false;
                root.pendingHasText = false;
                root.pendingText = "";
                root.pendingError = "";
                root.cleanupFiles();
            }
            stopTimer.stop();
            root.errorValue = Translation.tr("Speech to text is disabled");
            root.currentState = "disabled";
        }
    }


    function startRecording(target = "") {
        if (!root.enabled) {
            // Not a failure: the feature is switched off. Report it as its own
            // state so consumers do not render it as a broken recording.
            root.errorValue = Translation.tr("Speech to text is disabled");
            root.currentState = "disabled";
            root.sessionTarget = "";
            return;
        }
        if (root.busy) return;

        // A muted microphone only records silence, so report it instead of
        // finishing with an empty transcript.
        const sourceNode = root.configuredSourceNode();
        if (sourceNode?.audio?.muted) {
            root.notify(Translation.tr("Speech to text"), Translation.tr("The microphone is muted"));
            return;
        }

        root.sessionTarget = target;

        const stamp = Date.now();
        root.wavPath = `${root.captureDir}/capture-${stamp}.wav`;
        root.stopPath = `${root.captureDir}/capture-${stamp}.stop`;

        root.errorValue = "";
        root.elapsed = 0;
        root.pendingHasText = false;
        root.pendingText = "";
        root.pendingError = "";
        root.stderrText = "";
        root.streamedSegments = 0;
        root.segmentBuffer = "";
        root.detectedLanguage = "";
        root.insertErrorNotified = false;
        root.insertQueueWarned = false;
        root.insertTimedOut = false;

        // Track this recording in history.
        const entry = {
            id: stamp,
            timestamp: new Date().toISOString(),
            state: "recording",
            transcript: "",
            duration: 0
        };
        const updated = root.recordings.slice();
        updated.unshift(entry);
        if (updated.length > 20) updated.pop();
        root.recordings = updated;

        root.launchCapture();
    }

    // Build the backend argv. Kept pure so tests can assert what the service
    // actually requests instead of searching the source file for flag names.
    function buildCommand(mode) {
        const script = `${FileUtils.trimFileProtocol(Directories.scriptPath)}/ai/stt/stt-venv.sh`;
        const command = mode === "stream"
            ? [
                "bash", script, "stream",
                "--stop-file", root.stopPath,
                "--model", root.sttModel,
                "--language", root.sttLanguage,
                "--device", root.sttDevice,
                "--compute-type", root.sttComputeType,
                "--max-seconds", String(root.sttMaxSeconds)
            ]
            : [
                "bash", script, "record",
                "--out", root.wavPath,
                "--stop-file", root.stopPath,
                "--model", root.sttModel,
                "--language", root.sttLanguage,
                "--device", root.sttDevice,
                "--compute-type", root.sttComputeType,
                "--max-seconds", String(root.sttMaxSeconds)
            ];
        if (root.sttSource.length > 0) {
            command.push("--source-target", root.sttSource);
        }
        return command;
    }

    function launchCapture() {
        root.currentState = "recording";
        // Invalidate the old process before killing it: its exit/stdout events
        // must not be applied to the recording that is about to start.
        sttProcess.generation = -1;
        if (sttProcess.running) {
            sttProcess.running = false;
        }
        root.captureGeneration += 1;
        sttProcess.command = root.buildCommand(root.liveTyping ? "stream" : "record");
        sttProcess.generation = root.captureGeneration;
        sttProcess.running = true;
        startWatchdog.restart();
    }

    // Single entry points for backend events, so tests can exercise the
    // generation guard without spawning a real process.
    function processOutput(gen, line) {
        if (gen !== root.captureGeneration) return;
        root.handleStdout(line);
    }

    function processExited(gen, exitCode) {
        if (gen !== root.captureGeneration) return;
        sttProcess.running = false;
        root.handleExit(exitCode);
    }

    function stopRecording() {
        if (!root.recording) return;

        // The backend stops capturing as soon as the marker file shows up and
        // then transcribes, so the process exits on its own afterwards. Paths
        // are passed as arguments (never interpolated into the shell script)
        // so quotes in XDG state directories cannot break the command.
        Quickshell.execDetached([
            "bash", "-c", 'mkdir -p -- "$1" && touch -- "$2"',
            "bash", root.captureDir, root.stopPath
        ]);
        root.currentState = "transcribing";
        stopTimer.restart();
    }

    function toggleRecording() {
        if (root.recording) {
            root.stopRecording();
        } else {
            root.startRecording();
        }
    }

    // One gesture from the bar button or the global shortcut: enabling the
    // feature and starting the recording used to need two clicks.
    function toggleDictation(target = "") {
        if (root.recording) {
            root.stopRecording();
            return;
        }
        if (root.busy) return;
        if (!root.enabled) {
            Config.options.stt.enabled = true;
        }
        root.startRecording(target);
    }

    function configuredSourceNode() {
        const name = root.sttSource;
        if (name.length === 0) return Audio.source ?? null;
        const devices = Audio.inputDevices;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].name === name) return devices[i];
        }
        return null;
    }

    function clearTranscript() {
        root.transcriptValue = "";
    }

    // Hands the finished text to wherever the user configured it to go.
    function deliverTranscript(text) {
        const trimmed = (text ?? "").trim();
        if (trimmed.length === 0) {
            root.notify(Translation.tr("Speech to text"), Translation.tr("No speech was detected"));
            return;
        }

        const mode = root.deliveryMode;
        if (mode === "chat") return; // AiChat consumes transcriptReady itself.

        if (mode === "clipboard" || mode === "both") {
            Quickshell.clipboardText = trimmed;
        }
        if (mode === "type" || mode === "both") {
            root.insertText(trimmed);
        }
    }

    function insertText(text) {
        if (!text || text.length === 0) return;
        // Queue instead of cancelling: a phrase every few seconds must not
        // truncate the phrase that is still being typed. Bound the queue so a
        // stuck typing helper cannot accumulate phrases indefinitely.
        const maxQueue = 32;
        if (root.insertQueue.length >= maxQueue) {
            root.insertQueue.shift();
            if (!root.insertQueueWarned) {
                root.insertQueueWarned = true;
                root.notify(Translation.tr("Speech to text"), "Transcript queue is full - older phrases were dropped");
            }
        }
        root.insertQueue.push(text);
        root.pumpInsertQueue();
    }

    function pumpInsertQueue() {
        if (root.insertBusy || root.insertQueue.length === 0) return;
        root.insertBusy = true;
        root.insertTimedOut = false;
        insertProcess.command = [
            "bash",
            `${FileUtils.trimFileProtocol(Directories.scriptPath)}/ai/stt/insert-text.sh`,
            root.insertQueue[0]
        ];
        insertProcess.running = true;
        insertWatchdog.restart();
    }

    function notify(summary, body) {
        Quickshell.execDetached(["notify-send", summary, body, "-a", "Quickshell"]);
    }

    function handleStdout(line) {
        const raw = (line ?? "").trim();
        if (raw.length === 0) return;

        let payload;
        try {
            payload = JSON.parse(raw);
        } catch (e) {
            return;
        }

        if (!payload || typeof payload !== "object") return;

        if (payload.error !== undefined && payload.error !== null) {
            root.pendingError = String(payload.error);
            // An error supersedes any text already buffered from this run.
            root.pendingText = "";
            root.pendingHasText = false;
            return;
        }

        if (payload.type === "segment") {
            const text = String(payload.text ?? "").trim();
            if (text.length === 0) return;
            if (payload.language) root.detectedLanguage = String(payload.language);
            root.segmentBuffer = root.segmentBuffer.length > 0
                ? `${root.segmentBuffer} ${text}`
                : text;
            root.streamedSegments += 1;
            root.transcriptSegment(text);
            if (root.deliveryMode === "type" || root.deliveryMode === "both") {
                root.insertText(`${text} `);
            }
            return;
        }

        if (payload.type === "result") {
            // The aggregate line after the last phrase. The phrases were
            // already delivered, so this only feeds history and the clipboard.
            root.pendingText = String(payload.text ?? root.segmentBuffer).trim();
            root.pendingHasText = root.pendingText.length > 0;
            if (payload.language) root.detectedLanguage = String(payload.language);
            return;
        }

        if (typeof payload.text === "string") {
            root.pendingText = payload.text;
            root.pendingHasText = true;
        }
    }

    function handleExit(exitCode) {
        stopTimer.stop();

        // Update the most recent recording entry with the result.
        const updated = root.recordings.slice();
        if (updated.length > 0) {
            const entry = Object.assign({}, updated[0]);
            entry.duration = root.elapsed;
            if (root.pendingHasText) {
                entry.state = "done";
                entry.transcript = root.pendingText;
            } else if (root.pendingError.length > 0) {
                entry.state = "error";
                entry.transcript = root.pendingError;
            } else if (exitCode !== 0) {
                const details = root.stderrText.length > 0 ? `: ${root.stderrText}` : "";
                entry.state = "error";
                entry.transcript = `Speech to text failed (exit code ${exitCode})${details}`;
            } else {
                entry.state = "error";
                entry.transcript = Translation.tr("Speech to text returned no result");
            }
            updated[0] = entry;
            root.recordings = updated;
        }

        // The feature was disabled while this backend process was still
        // finishing: keep history, but never deliver text or leave the
        // "disabled" state behind.
        if (!root.enabled) {
            root.sessionTarget = "";
            root.cleanupFiles();
            return;
        }

        if (root.pendingHasText) {
            root.transcriptValue = root.pendingText;
            root.errorValue = "";
            root.currentState = "idle";
            if (root.streamedSegments > 0) {
                // The phrases were typed/delivered as they were committed.
                // Only the clipboard needs the complete text.
                if (root.deliveryMode === "clipboard" || root.deliveryMode === "both") {
                    Quickshell.clipboardText = root.transcriptValue;
                }
            } else {
                // AiChat reads deliveryMode synchronously in this signal, so
                // the per-recording target is cleared only after delivery.
                root.transcriptReady(root.transcriptValue);
                root.deliverTranscript(root.transcriptValue);
            }
        } else if (root.pendingError.length > 0) {
            root.errorValue = root.pendingError;
            root.currentState = "error";
        } else if (exitCode === 0 && root.liveTyping) {
            // Live dictation that heard nothing is not a failure.
            root.errorValue = Translation.tr("No speech was detected");
            root.currentState = "idle";
            root.notify(Translation.tr("Speech to text"), Translation.tr("No speech was detected"));
        } else if (exitCode !== 0) {
            const details = root.stderrText.length > 0 ? `: ${root.stderrText}` : "";
            root.errorValue = `Speech to text failed (exit code ${exitCode})${details}`;
            root.currentState = "error";
        } else {
            root.errorValue = Translation.tr("Speech to text returned no result");
            root.currentState = "error";
        }

        root.sessionTarget = "";
        root.cleanupFiles();
    }

    function cleanupFiles() {
        if (root.wavPath.length === 0 && root.stopPath.length === 0) return;
        Quickshell.execDetached(["rm", "-f", root.wavPath, root.stopPath]);
        root.wavPath = "";
        root.stopPath = "";
    }

    Process {
        id: sttProcess
        // Generation of the capture this process belongs to. Set to -1 when
        // the process is superseded so its late events are discarded.
        property int generation: 0
        stdout: SplitParser {
            onRead: data => {
                root.processOutput(sttProcess.generation, data);
            }
        }
        stderr: StdioCollector {
            id: sttStderr
            onStreamFinished: {
                if (sttProcess.generation === root.captureGeneration) {
                    root.stderrText = sttStderr.text.trim();
                }
            }
        }
        onStarted: {
            startWatchdog.stop();
        }
        onExited: (exitCode, exitStatus) => {
            root.processExited(sttProcess.generation, exitCode);
        }
    }

    Process {
        id: insertProcess
        onExited: (exitCode, exitStatus) => {
            insertWatchdog.stop();
            root.insertBusy = false;
            if (root.insertQueue.length > 0) root.insertQueue.shift();
            if (root.insertTimedOut) {
                root.insertTimedOut = false;
            } else if (exitCode !== 0 && !root.insertErrorNotified) {
                root.insertErrorNotified = true;
                root.notify(Translation.tr("Speech to text"), Translation.tr("Could not type the transcript"));
            }
            root.pumpInsertQueue();
        }
    }

    Timer {
        // A stuck typing helper must not block every later phrase forever.
        id: insertWatchdog
        interval: 10000
        repeat: false
        onTriggered: {
            if (!root.insertBusy) return;
            root.insertTimedOut = true;
            insertProcess.running = false;
        }
    }

    Timer {
        // Same limit that is passed to the backend as --max-seconds. Stopping
        // from here also flips the UI to "transcribing" at the right moment.
        id: maxDurationTimer
        interval: Math.max(10, root.sttMaxSeconds) * 1000
        running: root.recording
        onTriggered: root.stopRecording()
    }

    Timer {
        id: elapsedTimer
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.elapsed++
    }

    Timer {
        // The backend is spawned through a shell wrapper; if the interpreter or
        // the script is missing the process fails to start and never exits.
        id: startWatchdog
        interval: 5000
        repeat: false
        onTriggered: {
            if (root.currentState === "recording" && !sttProcess.running) {
                root.errorValue = Translation.tr("Speech to text failed to start");
                root.currentState = "error";
                root.cleanupFiles();
            }
        }
    }

    Timer {
        // Safety net: kill the backend when it does not finish in time.
        id: stopTimer
        interval: root.stopTimeoutMs
        repeat: false
        onTriggered: {
            if (!sttProcess.running) return;
            const pid = sttProcess.processId;
            Quickshell.execDetached([
                "bash", "-c",
                'pkill -TERM -P "$1" 2>/dev/null; kill -TERM "$1" 2>/dev/null; true',
                "bash", String(pid)
            ]);
        }
    }
}

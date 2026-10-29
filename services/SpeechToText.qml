pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
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

    // The backend transcribes after the capture ends, so the process stays alive
    // for as long as the inference takes (up to 5 minutes of audio, which on a
    // CPU with the large model can take several minutes). Only kill it when it
    // clearly hangs.
    property int stopTimeoutMs: 600000

    signal transcriptReady(string text)

    onEnabledChanged: {
        // Leaving the "disabled" state must not keep a stale error message around.
        if (root.enabled && root.currentState === "disabled") {
            root.currentState = "idle";
            root.errorValue = "";
        }
        // When STT is disabled, stop any active recording and mark as disabled.
        if (!root.enabled) {
            if (root.recording) {
                root.stopRecording();
            }
            root.errorValue = Translation.tr("Speech to text is disabled");
            root.currentState = "disabled";
        }
    }


    function startRecording() {
        if (!root.enabled) {
            // Not a failure: the feature is switched off. Report it as its own
            // state so consumers do not render it as a broken recording.
            root.errorValue = Translation.tr("Speech to text is disabled");
            root.currentState = "disabled";
            return;
        }
        if (root.busy) return;

        const stamp = Date.now();
        root.wavPath = `${root.captureDir}/capture-${stamp}.wav`;
        root.stopPath = `${root.captureDir}/capture-${stamp}.stop`;

        root.errorValue = "";
        root.elapsed = 0;
        root.pendingHasText = false;
        root.pendingText = "";
        root.pendingError = "";
        root.stderrText = "";

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

    function launchCapture() {
        root.currentState = "recording";
        // Ensure any previous instance is stopped before setting a new command
        if (sttProcess.running) {
            sttProcess.running = false;
        }

        sttProcess.command = [
            "bash",
            `${FileUtils.trimFileProtocol(Directories.scriptPath)}/ai/stt/stt-venv.sh`,
            "record",
            "--out", root.wavPath,
            "--stop-file", root.stopPath,
            "--model", root.sttModel,
            "--language", root.sttLanguage,
            "--device", root.sttDevice,
            "--compute-type", root.sttComputeType
        ];
        sttProcess.running = true;
        startWatchdog.restart();
    }

    function stopRecording() {
        if (!root.recording) return;

        // The backend stops capturing as soon as the marker file shows up and
        // then transcribes, so the process exits on its own afterwards.
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${root.captureDir}' && touch '${root.stopPath}'`]);
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

    function clearTranscript() {
        root.transcriptValue = "";
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

        if (root.pendingHasText) {
            root.transcriptValue = root.pendingText;
            root.errorValue = "";
            root.currentState = "idle";
            root.transcriptReady(root.transcriptValue);
        } else if (root.pendingError.length > 0) {
            root.errorValue = root.pendingError;
            root.currentState = "error";
        } else if (exitCode !== 0) {
            const details = root.stderrText.length > 0 ? `: ${root.stderrText}` : "";
            root.errorValue = `Speech to text failed (exit code ${exitCode})${details}`;
            root.currentState = "error";
        } else {
            root.errorValue = Translation.tr("Speech to text returned no result");
            root.currentState = "error";
        }

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
        stdout: SplitParser {
            onRead: data => {
                root.handleStdout(data);
            }
        }
        stderr: StdioCollector {
            id: sttStderr
            onStreamFinished: {
                root.stderrText = sttStderr.text.trim();
            }
        }
        onStarted: {
            startWatchdog.stop();
        }
        onExited: (exitCode, exitStatus) => {
            sttProcess.running = false;
            root.handleExit(exitCode);
        }
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
            Quickshell.execDetached(["bash", "-c", `pkill -TERM -P ${pid} 2>/dev/null; kill -TERM ${pid} 2>/dev/null; true`]);
        }
    }
}

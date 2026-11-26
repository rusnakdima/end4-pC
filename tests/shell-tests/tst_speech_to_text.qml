import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common

/**
 * Behavioral tests for the speech to text service.
 *
 * The tests drive the service's own public entry points (buildCommand,
 * processOutput, processExited, insertText) with canned data. No real backend
 * process or microphone is involved, and no source file is grep'd for flag
 * names: a refactor that keeps the behavior must keep these tests passing.
 */
TestCase {
    id: testCase
    name: "SpeechToText"
    when: true

    function indexOf(list, value) {
        for (let i = 0; i < list.length; ++i) {
            if (list[i] === value) return i;
        }
        return -1;
    }

    function option(list, name) {
        const at = indexOf(list, name);
        return at < 0 ? undefined : list[at + 1];
    }

    function test_the_enabled_flag_mirrors_the_config() {
        compare(SpeechToText.enabled, Config.options.stt.enabled);
        compare(SpeechToText.disabled, !Config.options.stt.enabled);
        compare(SpeechToText.sttEnabled, Config.options.stt.enabled);
    }

    function test_the_config_values_reach_the_service() {
        compare(SpeechToText.sttModel, Config.options.stt.model);
        compare(SpeechToText.sttLanguage, Config.options.stt.language);
        compare(SpeechToText.sttDevice, Config.options.stt.device);
        compare(SpeechToText.sttComputeType, Config.options.stt.computeType);
        compare(SpeechToText.sttSource, Config.options.stt.source);
        compare(SpeechToText.sttMaxSeconds, Config.options.stt.maxSeconds);
        compare(SpeechToText.sttOutput, Config.options.stt.output);
        compare(SpeechToText.modelName, Config.options.stt.model);
    }

    function test_the_record_command_carries_every_configured_option() {
        const savedWav = SpeechToText.wavPath;
        const savedStop = SpeechToText.stopPath;
        SpeechToText.wavPath = "/tmp/stt-test.wav";
        SpeechToText.stopPath = "/tmp/stt-test.stop";

        const command = SpeechToText.buildCommand("record");
        compare(command[2], "record");
        compare(option(command, "--out"), "/tmp/stt-test.wav");
        compare(option(command, "--stop-file"), "/tmp/stt-test.stop");
        compare(option(command, "--model"), Config.options.stt.model);
        compare(option(command, "--language"), Config.options.stt.language);
        compare(option(command, "--device"), Config.options.stt.device);
        compare(option(command, "--compute-type"), Config.options.stt.computeType);
        compare(option(command, "--max-seconds"), String(Config.options.stt.maxSeconds));
        compare(indexOf(command, "--source-target"), -1);

        SpeechToText.wavPath = savedWav;
        SpeechToText.stopPath = savedStop;
    }

    function test_the_stream_command_has_no_wav_and_can_select_a_source() {
        const blockWrites = Config.blockWrites;
        const savedSource = Config.options.stt.source;
        const savedStop = SpeechToText.stopPath;
        Config.blockWrites = true;
        SpeechToText.stopPath = "/tmp/stt-stream.stop";

        try {
            compare(Config.setNestedValue("stt.source", "test-source"), true);
            const command = SpeechToText.buildCommand("stream");
            compare(command[2], "stream");
            compare(indexOf(command, "--out"), -1);
            compare(option(command, "--stop-file"), "/tmp/stt-stream.stop");
            compare(option(command, "--source-target"), "test-source");
            compare(option(command, "--model"), Config.options.stt.model);
        } finally {
            Config.setNestedValue("stt.source", savedSource);
            Config.blockWrites = blockWrites;
            SpeechToText.stopPath = savedStop;
        }
    }

    function test_delivery_mode_defaults_to_the_config() {
        const savedTarget = SpeechToText.sessionTarget;
        const savedElapsed = SpeechToText.elapsed;
        SpeechToText.sessionTarget = "";
        SpeechToText.elapsed = 0;
        compare(SpeechToText.deliveryMode, Config.options.stt.output);
        compare(SpeechToText.elapsedLabel, "0:00");
        SpeechToText.elapsed = savedElapsed;
        SpeechToText.sessionTarget = savedTarget;
    }

    function test_live_dictation_follows_the_config_and_the_delivery_mode() {
        compare(SpeechToText.sttStreaming, Config.options.stt.streaming);
        const expected = Config.options.stt.streaming
            && (SpeechToText.deliveryMode === "type"
                || SpeechToText.deliveryMode === "both"
                || SpeechToText.deliveryMode === "chat");
        compare(SpeechToText.liveTyping, expected);
    }

    function test_segments_and_result_are_parsed_from_backend_lines() {
        const saved = {
            target: SpeechToText.sessionTarget,
            segments: SpeechToText.streamedSegments,
            buffer: SpeechToText.segmentBuffer,
            language: SpeechToText.detectedLanguage,
            text: SpeechToText.pendingText,
            hasText: SpeechToText.pendingHasText,
            error: SpeechToText.pendingError
        };
        SpeechToText.sessionTarget = "chat";
        SpeechToText.streamedSegments = 0;
        SpeechToText.segmentBuffer = "";
        SpeechToText.detectedLanguage = "";
        SpeechToText.pendingText = "";
        SpeechToText.pendingHasText = false;
        SpeechToText.pendingError = "";

        const gen = SpeechToText.captureGeneration;
        SpeechToText.processOutput(gen, '{"type":"segment","text":"hello","language":"en"}');
        compare(SpeechToText.segmentBuffer, "hello");
        compare(SpeechToText.streamedSegments, 1);
        compare(SpeechToText.detectedLanguage, "en");

        SpeechToText.processOutput(gen, '{"type":"segment","text":"world"}');
        compare(SpeechToText.segmentBuffer, "hello world");
        compare(SpeechToText.streamedSegments, 2);

        SpeechToText.processOutput(gen, '{"type":"result","text":"hello world"}');
        compare(SpeechToText.pendingText, "hello world");
        compare(SpeechToText.pendingHasText, true);

        // Malformed and non-object lines must be ignored, not raise errors.
        SpeechToText.processOutput(gen, "not json");
        SpeechToText.processOutput(gen, "[]");
        compare(SpeechToText.pendingText, "hello world");

        SpeechToText.sessionTarget = saved.target;
        SpeechToText.streamedSegments = saved.segments;
        SpeechToText.segmentBuffer = saved.buffer;
        SpeechToText.detectedLanguage = saved.language;
        SpeechToText.pendingText = saved.text;
        SpeechToText.pendingHasText = saved.hasText;
        SpeechToText.pendingError = saved.error;
    }

    function test_an_error_line_supersedes_buffered_text() {
        const saved = {
            target: SpeechToText.sessionTarget,
            text: SpeechToText.pendingText,
            hasText: SpeechToText.pendingHasText,
            error: SpeechToText.pendingError
        };
        SpeechToText.sessionTarget = "chat";
        SpeechToText.pendingText = "stale";
        SpeechToText.pendingHasText = true;
        SpeechToText.pendingError = "";

        SpeechToText.processOutput(SpeechToText.captureGeneration, '{"error":"boom"}');
        compare(SpeechToText.pendingError, "boom");
        compare(SpeechToText.pendingHasText, false);
        compare(SpeechToText.pendingText, "");

        SpeechToText.sessionTarget = saved.target;
        SpeechToText.pendingText = saved.text;
        SpeechToText.pendingHasText = saved.hasText;
        SpeechToText.pendingError = saved.error;
    }

    function test_exit_applies_success_and_failure() {
        const blockWrites = Config.blockWrites;
        const wasEnabled = Config.options.stt.enabled;
        const saved = {
            target: SpeechToText.sessionTarget,
            state: SpeechToText.state,
            transcript: SpeechToText.transcript,
            error: SpeechToText.error,
            wav: SpeechToText.wavPath,
            stop: SpeechToText.stopPath,
            text: SpeechToText.pendingText,
            hasText: SpeechToText.pendingHasText,
            pendingError: SpeechToText.pendingError,
            segments: SpeechToText.streamedSegments
        };
        Config.blockWrites = true;

        try {
            // A disabled service ignores process exits, so the live setting
            // must not decide whether this test exercises the success path.
            compare(Config.setNestedValue("stt.enabled", true), true);
            const gen = SpeechToText.captureGeneration;
            SpeechToText.sessionTarget = "chat";
            SpeechToText.wavPath = "";
            SpeechToText.stopPath = "";
            SpeechToText.streamedSegments = 0;

            SpeechToText.pendingText = "a final transcript";
            SpeechToText.pendingHasText = true;
            SpeechToText.pendingError = "";
            SpeechToText.processExited(gen, 0);
            compare(SpeechToText.state, "idle");
            compare(SpeechToText.transcript, "a final transcript");
            compare(SpeechToText.error, "");

            SpeechToText.pendingText = "";
            SpeechToText.pendingHasText = false;
            SpeechToText.pendingError = "backend failed";
            SpeechToText.processExited(gen, 2);
            compare(SpeechToText.state, "error");
            compare(SpeechToText.error, "backend failed");
        } finally {
            Config.setNestedValue("stt.enabled", wasEnabled);
            Config.blockWrites = blockWrites;
            SpeechToText.sessionTarget = saved.target;
            SpeechToText.currentState = saved.state;
            SpeechToText.transcriptValue = saved.transcript;
            SpeechToText.errorValue = saved.error;
            SpeechToText.wavPath = saved.wav;
            SpeechToText.stopPath = saved.stop;
            SpeechToText.pendingText = saved.text;
            SpeechToText.pendingHasText = saved.hasText;
            SpeechToText.pendingError = saved.pendingError;
            SpeechToText.streamedSegments = saved.segments;
        }
    }

    function test_stale_process_events_are_ignored() {
        const saved = {
            target: SpeechToText.sessionTarget,
            state: SpeechToText.state,
            transcript: SpeechToText.transcript,
            text: SpeechToText.pendingText,
            hasText: SpeechToText.pendingHasText,
            error: SpeechToText.error,
            wav: SpeechToText.wavPath,
            stop: SpeechToText.stopPath
        };
        SpeechToText.sessionTarget = "chat";
        SpeechToText.currentState = "transcribing";
        SpeechToText.pendingText = "current";
        SpeechToText.pendingHasText = true;
        SpeechToText.wavPath = "";
        SpeechToText.stopPath = "";

        SpeechToText.processOutput(-1, '{"text":"from an old process"}');
        compare(SpeechToText.pendingText, "current");
        SpeechToText.processExited(-1, 0);
        compare(SpeechToText.state, "transcribing");
        compare(SpeechToText.transcript, saved.transcript);

        SpeechToText.sessionTarget = saved.target;
        SpeechToText.currentState = saved.state;
        SpeechToText.transcriptValue = saved.transcript;
        SpeechToText.pendingText = saved.text;
        SpeechToText.pendingHasText = saved.hasText;
        SpeechToText.errorValue = saved.error;
        SpeechToText.wavPath = saved.wav;
        SpeechToText.stopPath = saved.stop;
    }

    function test_disabling_while_transcribing_stays_disabled() {
        const blockWrites = Config.blockWrites;
        const wasEnabled = Config.options.stt.enabled;
        const savedState = SpeechToText.state;
        const savedTranscript = SpeechToText.transcript;
        Config.blockWrites = true;

        try {
            compare(Config.setNestedValue("stt.enabled", true), true);
            SpeechToText.currentState = "transcribing";
            SpeechToText.pendingText = "should not be delivered";
            SpeechToText.pendingHasText = true;
            SpeechToText.wavPath = "";
            SpeechToText.stopPath = "";

            const gen = SpeechToText.captureGeneration;
            compare(Config.setNestedValue("stt.enabled", false), true);
            compare(SpeechToText.state, "disabled");

            // A late exit from the killed process cannot flip the state or
            // publish the transcript after the feature was switched off.
            SpeechToText.processExited(gen, 0);
            compare(SpeechToText.state, "disabled");
            compare(SpeechToText.transcript, savedTranscript);
        } finally {
            Config.setNestedValue("stt.enabled", wasEnabled);
            Config.blockWrites = blockWrites;
            SpeechToText.currentState = savedState;
            SpeechToText.transcriptValue = savedTranscript;
        }
    }

    function test_a_disabled_service_refuses_to_start_a_recording() {
        const blockWrites = Config.blockWrites;
        const wasEnabled = Config.options.stt.enabled;
        const generationBefore = SpeechToText.captureGeneration;
        Config.blockWrites = true;

        try {
            compare(Config.setNestedValue("stt.enabled", false), true);
            compare(SpeechToText.enabled, false);
            compare(SpeechToText.disabled, true);

            const recordingsBefore = SpeechToText.recordings.length;
            SpeechToText.startRecording();

            compare(SpeechToText.recordings.length, recordingsBefore);
            compare(SpeechToText.captureGeneration, generationBefore);
            compare(SpeechToText.state, "disabled");
            compare(SpeechToText.busy, false);
            compare(SpeechToText.error, Translation.tr("Speech to text is disabled"));
            compare(SpeechToText.wavPath, "");
            compare(SpeechToText.stopPath, "");
        } finally {
            Config.setNestedValue("stt.enabled", wasEnabled);
            Config.blockWrites = blockWrites;
        }
    }

    function test_the_insert_queue_is_bounded() {
        const savedBusy = SpeechToText.insertBusy;
        const savedQueue = SpeechToText.insertQueue;
        const savedWarned = SpeechToText.insertQueueWarned;
        SpeechToText.insertBusy = true; // no real typing helper is spawned
        SpeechToText.insertQueue = [];
        SpeechToText.insertQueueWarned = false;

        for (let i = 0; i < 40; ++i) {
            SpeechToText.insertText("phrase " + i);
        }

        compare(SpeechToText.insertQueue.length, 32);
        compare(SpeechToText.insertQueue[0], "phrase 8");
        compare(SpeechToText.insertQueueWarned, true);

        SpeechToText.insertBusy = savedBusy;
        SpeechToText.insertQueue = savedQueue;
        SpeechToText.insertQueueWarned = savedWarned;
    }

    function test_the_capture_paths_are_derived_from_the_state_directory() {
        verify(SpeechToText.captureDir.endsWith("/stt"));
        verify(!SpeechToText.captureDir.startsWith("file://"));
    }
}

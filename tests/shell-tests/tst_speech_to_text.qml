import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common

/**
 * Tests for the speech to text service.
 *
 * The service is switched on and off with the "stt.enabled" config option.
 * When it is disabled it must refuse to start a recording and it must say
 * why, and the model, the language, the device and the compute type of the
 * config must reach the request the backend receives.
 */
TestCase {
    id: testCase
    name: "SpeechToText"
    when: true

    // The backend that receives the request.
    FileView {
        id: backendView
        path: Quickshell.shellPath("../../scripts/ai/stt/stt.py")
    }

    // The service itself, read to pin the shape of the request it builds.
    FileView {
        id: serviceView
        path: Quickshell.shellPath("../../services/SpeechToText.qml")
    }

    function test_the_enabled_flag_mirrors_the_config() {
        compare(SpeechToText.enabled, Config.options.stt.enabled);
        compare(SpeechToText.disabled, !Config.options.stt.enabled);
        compare(SpeechToText.sttEnabled, Config.options.stt.enabled);
    }

    function test_the_model_and_the_language_reach_the_request() {
        // The values the service sends are bound copies of the config.
        compare(SpeechToText.sttModel, Config.options.stt.model);
        compare(SpeechToText.sttLanguage, Config.options.stt.language);
        compare(SpeechToText.sttDevice, Config.options.stt.device);
        compare(SpeechToText.sttComputeType, Config.options.stt.computeType);
        compare(SpeechToText.modelName, Config.options.stt.model);
    }

    function test_the_request_carries_the_model_the_language_and_the_device() {
        wait(500);
        verify(serviceView.loaded);
        const source = serviceView.text();
        verify(source.includes('"--model", root.sttModel'));
        verify(source.includes('"--language", root.sttLanguage'));
        verify(source.includes('"--device", root.sttDevice'));
        verify(source.includes('"--compute-type", root.sttComputeType'));
    }

    function test_the_backend_accepts_the_model_the_language_and_the_device() {
        wait(500);
        verify(backendView.loaded);
        const source = backendView.text();
        verify(source.includes('"--model"'));
        verify(source.includes('"--language"'));
        verify(source.includes('"--device"'));
        verify(source.includes('"--compute-type"'));
    }

    function test_a_disabled_service_refuses_to_start_a_recording() {
        // The config is only changed in memory: the writes are blocked, so the
        // user's config file stays untouched.
        const blockWrites = Config.blockWrites;
        const wasEnabled = Config.options.stt.enabled;
        Config.blockWrites = true;

        try {
            compare(Config.setNestedValue("stt.enabled", false), true);
            compare(SpeechToText.enabled, false);
            compare(SpeechToText.disabled, true);

            const recordingsBefore = SpeechToText.recordings.length;
            SpeechToText.startRecording();

            // The request was not sent: no recording was registered, the
            // service is idle-but-disabled and it says why.
            compare(SpeechToText.recordings.length, recordingsBefore);
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

    function test_the_capture_paths_are_derived_from_the_state_directory() {
        verify(SpeechToText.captureDir.endsWith("/stt"));
        verify(!SpeechToText.captureDir.startsWith("file://"));
    }
}

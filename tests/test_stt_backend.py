#!/usr/bin/env python3
"""Offline unit tests for scripts/ai/stt/stt.py.

The whisper model, the CUDA device and pw-record are all faked, so these tests
run without a microphone, a GPU, a network connection or a Wayland session.
Run with:  python3 -m unittest discover -s tests -p 'test_stt_*.py'
"""

import array
import contextlib
import importlib.util
import io
import json
import math
import os
import sys
import tempfile
import unittest
import wave

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKEND = os.path.join(REPO, "scripts", "ai", "stt", "stt.py")

spec = importlib.util.spec_from_file_location("stt_backend", BACKEND)
stt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stt)


class FakeSegment:
    def __init__(self, text):
        self.text = text


class FakeInfo:
    language = "en"
    duration = 1.25


class FakeWhisperModel:
    instances = []

    def __init__(self, *args, **kwargs):
        self.args = args
        self.kwargs = kwargs
        self.calls = []
        FakeWhisperModel.instances.append(self)

    def transcribe(self, audio, **kwargs):
        self.calls.append(kwargs)
        return iter([FakeSegment(" hello "), FakeSegment("world ")]), FakeInfo()


class FakeArgs:
    """Namespace for stream_audio / main with all parser defaults filled in."""

    def __init__(self, **overrides):
        values = dict(
            audio="", model="base", language="auto", device="cpu",
            compute_type="int8", max_seconds=5.0, source_target="",
            stop_file="", silence_ms=450.0, min_speech_ms=250.0,
            pad_ms=200.0, window_max_seconds=15.0, result_file="",
        )
        values.update(overrides)
        for key, value in values.items():
            setattr(self, key, value)


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.saved = {
            name: getattr(stt, name)
            for name in ("import_faster_whisper", "resolve_device", "load_model",
                         "pw_record_command")
        }
        stt.import_faster_whisper = lambda: FakeWhisperModel
        stt.resolve_device = lambda device: "cpu"
        stt.load_model = lambda model, name, device, compute: (model(), "cpu", "int8")
        FakeWhisperModel.instances = []
        self.tempdir = tempfile.mkdtemp(prefix="stt-tests-")

    def tearDown(self):
        for name, value in self.saved.items():
            setattr(stt, name, value)

    def wav_file(self, name="probe.wav", rate=16000, frames=8000, tone=False):
        path = os.path.join(self.tempdir, name)
        if tone:
            samples = array.array(
                "h",
                [
                    int(3000 * math.sin(index / 8.0)) if index < frames * 2 // 3 else 0
                    for index in range(frames)
                ],
            )
        else:
            samples = array.array("h", [0] * frames)
        with wave.open(path, "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(rate)
            handle.writeframes(samples.tobytes())
        return path

    def run_capture(self, function):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            value = function()
        return value, out.getvalue()

    # -- helpers ---------------------------------------------------------

    def test_resample_changes_length_and_preserves_endpoints(self):
        samples = [0.0, 0.5, 1.0, 0.5, 0.0]
        result = stt.resample(samples, 5, 10)
        self.assertEqual(len(result), 10)
        self.assertAlmostEqual(result[0], 0.0)
        self.assertAlmostEqual(result[-1], 0.0)
        self.assertEqual(stt.resample([], 16000, 8000), [])
        self.assertIs(stt.resample(samples, 16000, 16000), samples)

    def test_decode_and_load_audio(self):
        path = self.wav_file()
        decoded = stt.decode_wav_file(path)
        self.assertIsNotNone(decoded)
        samples, rate = decoded
        self.assertEqual((len(samples), rate), (8000, 16000))

        loaded = stt.load_audio(path)
        self.assertEqual(loaded.shape, (8000,))
        self.assertEqual(str(loaded.dtype), "float32")

        downsampled = stt.load_audio(self.wav_file("8k.wav", rate=8000, frames=4000))
        self.assertEqual(downsampled.shape, (8000,))

        self.assertIsNone(stt.decode_wav_file(os.path.join(self.tempdir, "missing.wav")))

    def test_write_json_result_is_atomic_and_valid(self):
        path = os.path.join(self.tempdir, "result.json")
        stt.write_json_result({"text": "ok"}, path)
        with open(path, encoding="utf-8") as handle:
            self.assertEqual(json.loads(handle.read()), {"text": "ok"})
        self.assertEqual(
            [name for name in os.listdir(self.tempdir) if name.startswith(".stt-")],
            [],
        )

    def test_stop_requested(self):
        missing = os.path.join(self.tempdir, "no.stop")
        self.assertFalse(stt.stop_requested(missing))
        self.assertFalse(stt.stop_requested(""))
        with open(missing, "w", encoding="utf-8"):
            pass
        self.assertTrue(stt.stop_requested(missing))

    def test_emit_error_writes_one_json_line_and_exits(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), self.assertRaises(SystemExit) as caught:
            stt.emit_error("boom", 7)
        self.assertEqual(caught.exception.code, 7)
        self.assertEqual(json.loads(out.getvalue()), {"error": "boom"})

    # -- transcription ----------------------------------------------------

    def test_transcribe_audio_contract(self):
        result = stt.transcribe_audio(self.wav_file(), "base", "en", "cpu", "int8")
        self.assertEqual(result["text"], "hello world")
        self.assertEqual(result["language"], "en")
        self.assertEqual(result["device"], "cpu")
        self.assertGreater(result["duration"], 0)

    def test_transcribe_audio_retries_on_cpu_after_device_failure(self):
        class CpuOnlyModel(FakeWhisperModel):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                self.tried = False

            def transcribe(self, audio, **kwargs):
                if self.kwargs.get("device") != "cpu" and not self.tried:
                    self.tried = True
                    raise RuntimeError("cuda unavailable")
                return super().transcribe(audio, **kwargs)

        stt.import_faster_whisper = lambda: CpuOnlyModel
        stt.load_model = lambda model, name, device, compute: (
            model(name, device=device, compute_type=compute), device, compute
        )
        result = stt.transcribe_audio(self.wav_file(), "base", "auto", "cuda", "int8")
        self.assertEqual(result["text"], "hello world")
        self.assertEqual(result["device"], "cpu")

    # -- streaming --------------------------------------------------------

    def test_stream_audio_emits_one_line_per_phrase_and_a_result(self):
        path = self.wav_file(name="speech.wav", frames=24000, tone=True)
        value, stdout = self.run_capture(
            lambda: stt.main(["stream", "--audio", path, "--model", "base",
                              "--language", "en", "--device", "cpu",
                              "--compute-type", "int8"])
        )
        self.assertEqual(value, 0)
        lines = [json.loads(line) for line in stdout.splitlines() if line.strip()]
        segments = [line for line in lines if line.get("type") == "segment"]
        results = [line for line in lines if line.get("type") == "result"]
        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0]["text"], "hello world")
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["text"], "hello world")
        self.assertEqual(results[0]["segments"], 1)

    def test_stream_audio_flush_handles_silence_only_input(self):
        path = self.wav_file(frames=16000)  # silence: no speech, no segment
        result, stdout = self.run_capture(
            lambda: stt.stream_audio(FakeArgs(audio=path, language="en"))
        )
        self.assertEqual(result["text"], "")
        self.assertEqual(result["segments"], 0)
        self.assertEqual(stdout.splitlines(), [])

    # -- capture ----------------------------------------------------------

    def test_capture_audio_writes_a_valid_wav(self):
        script = os.path.join(self.tempdir, "fake-pw-record.py")
        with open(script, "w", encoding="utf-8") as handle:
            handle.write(
                "import sys, time\n"
                "block = b'\\x00\\x00' * 16000\n"
                "while True:\n"
                "    sys.stdout.buffer.write(block)\n"
                "    sys.stdout.buffer.flush()\n"
                "    time.sleep(0.02)\n"
            )
        stt.pw_record_command = lambda source: [sys.executable, script]
        out_path = os.path.join(self.tempdir, "capture.wav")

        reason, _stderr = stt.capture_audio(out_path, "", 0.5, "")
        self.assertEqual(reason, "max-seconds")
        self.assertTrue(os.path.exists(out_path))
        self.assertGreater(stt.wav_duration(out_path), 0)

    # -- dispatch ---------------------------------------------------------

    def test_main_transcribe_prints_exactly_one_json_line(self):
        path = self.wav_file()
        value, stdout = self.run_capture(
            lambda: stt.main(["transcribe", "--audio", path, "--model", "base",
                              "--language", "en", "--device", "cpu",
                              "--compute-type", "int8"])
        )
        self.assertEqual(value, 0)
        lines = stdout.splitlines()
        self.assertEqual(len(lines), 1)
        self.assertEqual(json.loads(lines[0])["text"], "hello world")

    def test_main_reports_missing_model_dependency_as_json(self):
        def broken_import():
            stt.emit_error(stt.ERROR_IMPORT, 2)

        stt.import_faster_whisper = broken_import
        with contextlib.redirect_stdout(io.StringIO()) as out:
            with self.assertRaises(SystemExit) as caught:
                stt.main(["transcribe", "--audio", self.wav_file()])
        self.assertEqual(caught.exception.code, 2)
        self.assertEqual(json.loads(out.getvalue())["error"], stt.ERROR_IMPORT)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Whisper speech-to-text backend for the end4-pC shell.

Two subcommands:

  record      capture the microphone through pw-record into a 16 kHz mono WAV
              file and transcribe it.
  transcribe  transcribe an existing audio file.

Exactly one line of JSON is written to stdout in every case. Diagnostics go to
stderr. On failure ``{"error": "..."}`` is printed and the exit code is
non-zero.
"""

import argparse
import array
import json
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time
import wave

SAMPLE_RATE = 16000
CHANNELS = 1
SAMPLE_WIDTH = 2  # signed 16-bit little endian

MODEL_IDS = ("tiny", "base", "small", "medium", "large-v3")
DEVICE_IDS = ("cpu", "cuda", "auto")
COMPUTE_TYPES = ("int8", "int8_float16", "float16", "float32")

ERROR_IMPORT = "faster-whisper is not installed in the shell venv"


def log(message):
    """Diagnostics only - stdout is reserved for the single JSON line."""
    print(message, file=sys.stderr, flush=True)


def emit_error(message, code=1):
    sys.stdout.write(json.dumps({"error": str(message)}) + "\n")
    sys.stdout.flush()
    sys.exit(code)


def write_json_result(payload, result_file):
    """Write the payload to result_file atomically (temp file + os.replace)."""
    if not result_file:
        return
    directory = os.path.dirname(os.path.abspath(result_file)) or "."
    try:
        os.makedirs(directory, exist_ok=True)
        fd, tmp_path = tempfile.mkstemp(prefix=".stt-", suffix=".json", dir=directory)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(json.dumps(payload) + "\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(tmp_path, result_file)
        except BaseException:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
            raise
    except OSError as exc:
        log("stt: could not write result file %s: %s" % (result_file, exc))


def import_faster_whisper():
    """Import faster_whisper, exiting with code 2 when it is missing."""
    try:
        from faster_whisper import WhisperModel  # noqa: F401
    except ImportError:
        emit_error(ERROR_IMPORT, 2)
    except Exception as exc:  # broken install, missing shared libs, ...
        emit_error("faster-whisper could not be imported: %s" % exc, 2)
    return WhisperModel


def resolve_device(device):
    """Map the requested device onto an actually usable one."""
    if device == "auto" or device == "cuda":
        try:
            import ctranslate2

            count = ctranslate2.get_cuda_device_count()
        except Exception:
            count = 0
        if count and count > 0:
            return "cuda"
        log("stt: no CUDA device available, falling back to cpu")
        return "cpu"
    return device


def decode_wav_file(path):
    """Decode a WAV file with the stdlib and return (samples, rate).

    Returns None when the file is not a readable WAV.
    """
    try:
        with wave.open(path, "rb") as handle:
            channels = handle.getnchannels()
            width = handle.getsampwidth()
            rate = handle.getframerate()
            frames = handle.readframes(handle.getnframes())
    except (OSError, wave.Error):
        return None

    if width == 2:
        data = array.array("h")
        data.frombytes(frames[: len(frames) - (len(frames) % 2)])
        if sys.byteorder == "big":
            data.byteswap()
        samples = [value / 32768.0 for value in data]
    elif width == 1:
        samples = [(byte - 128) / 128.0 for byte in frames]
    elif width == 4:
        data = array.array("i")
        data.frombytes(frames[: len(frames) - (len(frames) % 4)])
        if sys.byteorder == "big":
            data.byteswap()
        samples = [value / 2147483648.0 for value in data]
    else:
        return None

    if channels > 1:
        samples = [
            sum(samples[index : index + channels]) / float(channels)
            for index in range(0, len(samples) - channels + 1, channels)
        ]

    return samples, rate


def resample(samples, source_rate, target_rate):
    """Resample mono float samples to the target rate (linear interpolation)."""
    if source_rate == target_rate or not samples:
        return samples
    if source_rate <= 0:
        return samples
    target_length = max(1, int(round(len(samples) * float(target_rate) / source_rate)))
    step = (len(samples) - 1) / float(target_length - 1) if target_length > 1 else 0.0
    result = []
    for index in range(target_length):
        position = index * step
        lower = int(position)
        upper = min(lower + 1, len(samples) - 1)
        weight = position - lower
        result.append(samples[lower] * (1.0 - weight) + samples[upper] * weight)
    return result


def decode_with_ffmpeg(path):
    """Decode any audio file to 16 kHz mono via ffmpeg. Returns samples or None."""
    command = [
        "ffmpeg",
        "-nostdin",
        "-v",
        "quiet",
        "-i",
        path,
        "-f",
        "s16le",
        "-ac",
        "1",
        "-ar",
        str(SAMPLE_RATE),
        "-",
    ]
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
    except (OSError, ValueError):
        return None
    if result.returncode != 0 or not result.stdout:
        return None
    data = array.array("h")
    data.frombytes(result.stdout[: len(result.stdout) - (len(result.stdout) % 2)])
    if sys.byteorder == "big":
        data.byteswap()
    return [value / 32768.0 for value in data]


def load_audio(path):
    """Load an audio file as a float32 numpy array of mono samples at 16 kHz.

    Tries the stdlib WAV reader first, then ffmpeg, then faster-whisper's own
    decoder (which depends on PyAV and breaks on some version combinations).
    """
    decoded = decode_wav_file(path)
    if decoded is not None:
        samples, rate = decoded
        return to_numpy(resample(samples, rate, SAMPLE_RATE))

    samples = decode_with_ffmpeg(path)
    if samples is not None:
        return to_numpy(samples)

    try:
        from faster_whisper.audio import decode_audio

        return decode_audio(path, sampling_rate=SAMPLE_RATE)
    except Exception as exc:
        log("stt: could not decode '%s': %s" % (path, exc))

    return None


def to_numpy(samples):
    """Convert a list of float samples into the float32 array whisper expects."""
    import numpy as np

    return np.asarray(samples, dtype=np.float32)


def load_model(WhisperModel, model_id, device, compute_type):
    """Load the whisper model, degrading the device/compute type when needed.

    Returns (model, device, compute_type).
    """
    attempts = [(device, compute_type)]
    if device != "cpu":
        attempts.append(("cpu", "int8" if compute_type != "int8" else compute_type))
    elif compute_type in ("float16", "int8_float16"):
        attempts.append(("cpu", "int8"))

    last_error = None
    for attempt_device, attempt_type in attempts:
        try:
            model = WhisperModel(
                model_id, device=attempt_device, compute_type=attempt_type
            )
            if attempt_device != device or attempt_type != compute_type:
                log(
                    "stt: using device=%s compute_type=%s instead of %s/%s"
                    % (attempt_device, attempt_type, device, compute_type)
                )
            return model, attempt_device, attempt_type
        except Exception as exc:
            last_error = exc

    emit_error("could not load whisper model '%s': %s" % (model_id, last_error))


def transcribe_audio(path, model_id, language, device, compute_type):
    """Transcribe an audio file and return the result payload."""
    WhisperModel = import_faster_whisper()

    device = resolve_device(device)

    samples = load_audio(path)
    if samples is None:
        emit_error("could not decode audio file '%s'" % path)
    if len(samples) == 0:
        emit_error("audio file '%s' contains no samples" % path)

    started = time.monotonic()
    model, device, compute_type = load_model(
        WhisperModel, model_id, device, compute_type
    )

    whisper_language = None if (language is None or language == "auto") else language

    def run():
        segments, info = model.transcribe(
            samples, language=whisper_language, vad_filter=True
        )
        texts = []
        detected_language = whisper_language or ""
        duration = 0.0
        for segment in segments:
            text = getattr(segment, "text", "")
            if text:
                texts.append(text.strip())
            info_language = getattr(info, "language", None)
            if info_language:
                detected_language = info_language
            info_duration = getattr(info, "duration", None)
            if isinstance(info_duration, (int, float)) and info_duration > 0:
                duration = float(info_duration)
        return texts, detected_language, duration

    try:
        texts, detected_language, duration = run()
    except Exception as exc:
        if device != "cpu":
            log("stt: transcription on %s failed (%s), retrying on cpu" % (device, exc))
            model, device, compute_type = load_model(
                WhisperModel, model_id, "cpu", "int8"
            )
            try:
                texts, detected_language, duration = run()
            except Exception as cpu_exc:
                emit_error("transcription failed: %s" % cpu_exc)
        else:
            emit_error("transcription failed: %s" % exc)

    elapsed = time.monotonic() - started
    if duration <= 0:
        duration = round(elapsed, 3)

    return {
        "text": " ".join(part for part in texts if part).strip(),
        "language": detected_language or (whisper_language or ""),
        "duration": round(float(duration), 3),
        "device": device,
    }


def wav_duration(path):
    """Duration of a WAV file in seconds, 0.0 when it cannot be read."""
    try:
        with wave.open(path, "rb") as handle:
            frames = handle.getnframes()
            rate = handle.getframerate() or SAMPLE_RATE
            return frames / float(rate)
    except (OSError, wave.Error):
        return 0.0


def stop_requested(stop_file):
    """True once the stop file exists."""
    return bool(stop_file) and os.path.exists(stop_file)


def capture_audio(out_path, stop_file, max_seconds, source_target):
    """Record the microphone into out_path as a 16 kHz mono s16 WAV."""
    command = [
        "pw-record",
        "--rate",
        str(SAMPLE_RATE),
        "--channels",
        str(CHANNELS),
        "--format",
        "s16",
    ]
    if source_target:
        command += ["--target", source_target]
    # "-" makes pw-record stream the raw frames to stdout, they are written
    # into the WAV file by this script.
    command += ["-"]

    # pw-record's stderr goes to a temp file so it can never fill a pipe
    # buffer and block the recorder.
    stderr_file = tempfile.TemporaryFile()
    try:
        proc = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=stderr_file,
            bufsize=0,
        )
    except FileNotFoundError:
        stderr_file.close()
        emit_error("pw-record was not found - install pipewire-audio")
    except OSError as exc:
        stderr_file.close()
        emit_error("could not start pw-record: %s" % exc)

    writer = None
    try:
        writer = wave.open(out_path, "wb")
        writer.setnchannels(CHANNELS)
        writer.setsampwidth(SAMPLE_WIDTH)
        writer.setframerate(SAMPLE_RATE)
    except (OSError, wave.Error) as exc:
        if proc.poll() is None:
            proc.terminate()
        emit_error("could not open output file '%s': %s" % (out_path, exc))

    write_error = []

    def reader():
        """Pump raw s16 frames from pw-record into the WAV writer.

        The wave module repatches the RIFF header after every write, so the
        file stays valid even when the process is killed mid-capture.
        """
        try:
            while True:
                chunk = proc.stdout.read(4096)
                if not chunk:
                    break
                writer.writeframes(chunk)
        except Exception as exc:  # broken pipe, closed stream, ...
            write_error.append(exc)

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()

    started = time.monotonic()
    deadline = started + max_seconds if max_seconds and max_seconds > 0 else None
    reason = "max-seconds"

    while True:
        if proc.poll() is not None:
            reason = "recorder-exited"
            break
        if stop_requested(stop_file):
            reason = "stop-file"
            break
        if deadline is not None and time.monotonic() >= deadline:
            reason = "max-seconds"
            break
        time.sleep(0.1)

    # Stop the recorder: SIGINT first so pw-record finalizes its own output,
    # SIGKILL after a short grace period.
    if proc.poll() is None:
        try:
            proc.send_signal(signal.SIGINT)
        except OSError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                proc.kill()
            except OSError:
                pass
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass

    thread.join(timeout=2)

    try:
        writer.close()
    except (OSError, wave.Error) as exc:
        write_error.append(exc)

    try:
        if proc.stdout is not None:
            proc.stdout.close()
    except OSError:
        pass

    if write_error:
        log("stt: capture finished with warnings: %s" % write_error[0])

    recorder_stderr = ""
    try:
        stderr_file.seek(0)
        recorder_stderr = stderr_file.read().decode("utf-8", "replace").strip()
    except (OSError, ValueError):
        recorder_stderr = ""
    try:
        stderr_file.close()
    except OSError:
        pass

    if proc.returncode not in (0, None, -signal.SIGINT) and recorder_stderr:
        log("stt: pw-record exited with %s: %s" % (proc.returncode, recorder_stderr))

    return reason, recorder_stderr


def build_parser():
    parser = argparse.ArgumentParser(
        prog="stt.py",
        description="Whisper speech-to-text backend for the end4-pC shell.",
    )
    subparsers = parser.add_subparsers(dest="command")

    record = subparsers.add_parser(
        "record",
        help="record the microphone and transcribe the recording",
    )
    record.add_argument("--out", required=True, help="path of the WAV file to write")
    record.add_argument(
        "--stop-file",
        default="",
        help="path whose appearance stops the capture (polled every 100 ms)",
    )
    record.add_argument(
        "--max-seconds",
        type=float,
        default=300.0,
        help="maximum capture duration in seconds (default: 300)",
    )
    record.add_argument(
        "--source-target",
        default="auto",
        help="pw-record source target name (default: auto)",
    )
    record.add_argument(
        "--model",
        default="base",
        choices=list(MODEL_IDS),
        help="whisper model id (default: base)",
    )
    record.add_argument(
        "--language",
        default="auto",
        help="spoken language code, or 'auto' to let whisper detect it (default: auto)",
    )
    record.add_argument(
        "--device",
        default="cpu",
        choices=list(DEVICE_IDS),
        help="inference device: cpu, cuda or auto (default: cpu)",
    )
    record.add_argument(
        "--compute-type",
        default="int8",
        choices=list(COMPUTE_TYPES),
        help="quantization/compute type (default: int8)",
    )
    record.add_argument(
        "--result-file",
        default="",
        help="write the resulting JSON to this file as well",
    )

    transcribe = subparsers.add_parser(
        "transcribe",
        help="transcribe an existing audio file",
    )
    transcribe.add_argument("--audio", required=True, help="path of the audio file to transcribe")
    transcribe.add_argument(
        "--model",
        default="base",
        choices=list(MODEL_IDS),
        help="whisper model id (default: base)",
    )
    transcribe.add_argument(
        "--language",
        default="auto",
        help="spoken language code, or 'auto' to let whisper detect it (default: auto)",
    )
    transcribe.add_argument(
        "--device",
        default="cpu",
        choices=list(DEVICE_IDS),
        help="inference device: cpu, cuda or auto (default: cpu)",
    )
    transcribe.add_argument(
        "--compute-type",
        default="int8",
        choices=list(COMPUTE_TYPES),
        help="quantization/compute type (default: int8)",
    )
    transcribe.add_argument(
        "--result-file",
        default="",
        help="write the resulting JSON to this file as well",
    )

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)

    if not args.command:
        parser.print_help(file=sys.stderr)
        emit_error("no command given (expected 'record' or 'transcribe')", 2)

    if args.command == "record":
        out_path = os.path.abspath(os.path.expanduser(args.out))
        out_dir = os.path.dirname(out_path)
        if out_dir:
            try:
                os.makedirs(out_dir, exist_ok=True)
            except OSError as exc:
                emit_error("could not create output directory '%s': %s" % (out_dir, exc))

        reason, recorder_stderr = capture_audio(
            out_path,
            os.path.expanduser(args.stop_file) if args.stop_file else "",
            args.max_seconds,
            args.source_target,
        )
        log("stt: capture stopped (%s)" % reason)

        if not os.path.exists(out_path):
            emit_error("recording produced no audio file")
        if wav_duration(out_path) <= 0:
            message = "no audio was captured"
            detail = ""
            for line in recorder_stderr.splitlines():
                if line.strip():
                    detail = line.strip()
                    break
            if detail:
                message += ": %s" % detail
            emit_error(message)

        payload = transcribe_audio(
            out_path,
            args.model,
            args.language,
            args.device,
            args.compute_type,
        )
    else:
        audio_path = os.path.abspath(os.path.expanduser(args.audio))
        if not os.path.exists(audio_path):
            emit_error("audio file '%s' does not exist" % audio_path)
        payload = transcribe_audio(
            audio_path,
            args.model,
            args.language,
            args.device,
            args.compute_type,
        )

    write_json_result(payload, os.path.expanduser(args.result_file) if args.result_file else "")
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except KeyboardInterrupt:
        emit_error("interrupted", 130)
    except BrokenPipeError:
        sys.exit(0)
    except Exception as exc:  # never leak a traceback into the JSON contract
        emit_error("%s: %s" % (type(exc).__name__, exc))

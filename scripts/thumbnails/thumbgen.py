#!/usr/bin/env python3

"""Freedesktop.org thumbnail cache generator for end4-pC.

The thumbnails are rendered with ImageMagick (still images) and ffmpeg
(videos) instead of GnomeDesktop.DesktopThumbnailFactory. The factory
spawns gdk-pixbuf-thumbnailer as a helper process, which fails on systems
without the gdk-pixbuf loaders installed
("g-spawn-exit-error-quark: Child process exited with code 1") and it cannot
render videos at all without ffmpegthumbnailer.

The cache layout follows the freedesktop.org thumbnail specification:
    ~/.cache/thumbnails/<size>/<md5 of the file uri>.png
The md5 is taken over "file://" + the absolute path with every path segment
percent-encoded the way JavaScript's encodeURIComponent() does, so the
hashes match the ones computed by the QML ThumbnailImage component.
"""

import hashlib
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import List

import click

try:
    from loguru import logger
except ImportError:  # loguru is optional, fall back to the stdlib logger
    import logging

    logger = logging.getLogger("thumbgen")
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

# Freedesktop.org thumbnail sizes.
THUMBNAIL_SIZES = {
    "normal": 128,
    "large": 256,
    "x-large": 512,
    "xx-large": 1024,
}

IMAGE_SUFFIXES = {
    ".jpg", ".jpeg", ".png", ".webp", ".avif", ".bmp", ".tif", ".tiff", ".svg",
    ".gif",
}

VIDEO_SUFFIXES = {
    ".mp4", ".webm", ".mkv", ".avi", ".mov", ".m4v", ".wmv", ".flv", ".ogv",
    ".3gp", ".qt",
}

# Characters JavaScript's encodeURIComponent() leaves untouched.
_JS_UNRESERVED = set(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
)


def js_encode_uri_component(text: str) -> str:
    """Percent-encode a string exactly like JavaScript's encodeURIComponent()."""
    encoded = []
    for byte in text.encode("utf-8"):
        char = chr(byte)
        if char in _JS_UNRESERVED:
            encoded.append(char)
        else:
            encoded.append("%%%02X" % byte)
    return "".join(encoded)


def thumbnail_uri(path: Path) -> str:
    """Build the file:// uri of an absolute path, encoded like the QML does."""
    absolute = str(path.resolve())
    return "file://" + "/".join(
        js_encode_uri_component(part) for part in absolute.split("/")
    )


def thumbnail_hash(path: Path) -> str:
    return hashlib.md5(thumbnail_uri(path).encode("utf-8")).hexdigest()


def cache_dir(size_key: str) -> Path:
    base = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
    return Path(base) / "thumbnails" / size_key


def _run(command: List[str], timeout: int = 60) -> bool:
    try:
        subprocess.run(
            command, check=True, capture_output=True, timeout=timeout
        )
        return True
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired,
            FileNotFoundError, OSError) as error:
        logger.debug("ERROR {}: {}".format(command[0], error))
        return False


def render_image(source: Path, target: Path, pixels: int) -> bool:
    """Render a still image into a thumbnail, preserving the aspect ratio."""
    return _run([
        "magick", str(source),
        "-auto-orient",
        # Keep the memory usage of huge images bounded, the pixel cache is
        # spilled to disk instead of eating all of the ram.
        "-limit", "memory", "256MiB",
        "-limit", "map", "512MiB",
        "-resize", "{}x{}".format(pixels, pixels),
        "-strip",
        str(target),
    ])


def render_video(source: Path, target: Path, pixels: int) -> bool:
    """Render a poster frame of a video into a thumbnail.

    The first frame of a clip is usually black (fade in) and would look like a
    broken preview, so a frame a few seconds in is preferred.
    """
    if shutil.which("ffmpegthumbnailer"):
        return _run([
            "ffmpegthumbnailer", "-s", str(pixels),
            "-i", str(source), "-o", str(target),
        ])
    for seek in ("00:00:03", "00:00:01", "00:00:00"):
        if _run([
            "ffmpeg", "-y", "-ss", seek, "-i", str(source),
            "-frames:v", "1",
            "-vf", "scale={0}:{0}:force_original_aspect_ratio=decrease".format(pixels),
            "-f", "image2", str(target),
        ], timeout=120):
            return True
    return False


def make_thumbnail(path: Path, size_key: str) -> bool:
    """Create the thumbnail of a single file if it is missing or outdated."""
    suffix = path.suffix.lower()
    if suffix in VIDEO_SUFFIXES:
        renderer = render_video
    elif suffix in IMAGE_SUFFIXES:
        renderer = render_image
    else:
        return False

    pixels = THUMBNAIL_SIZES[size_key]
    target_dir = cache_dir(size_key)
    target = target_dir / "{}.png".format(thumbnail_hash(path))

    try:
        mtime = path.stat().st_mtime
    except OSError:
        return False

    if target.exists():
        try:
            if target.stat().st_mtime >= mtime:
                logger.debug("FRESH     {}".format(path))
                return False
        except OSError:
            pass

    target_dir.mkdir(parents=True, exist_ok=True)
    # The temporary file has to keep a .png suffix, ImageMagick and ffmpeg
    # pick the output format from it.
    temporary = target.with_name(target.name + ".tmp.png")
    if temporary.exists():
        temporary.unlink()

    if not renderer(path, temporary, pixels):
        if temporary.exists():
            temporary.unlink()
        return False

    # ImageMagick and ffmpeg pick the format from the file extension, so the
    # temporary file needs a .png suffix to be written as a png.
    if not temporary.exists():
        return False

    os.replace(temporary, target)
    try:
        os.utime(target, (mtime, mtime))
    except OSError:
        pass
    logger.debug("OK        {}".format(path))
    return True


def collect_files(directory: Path, recursive: bool) -> List[Path]:
    if not (directory.exists() and directory.is_dir()):
        raise ValueError("{} doesn't exist or isn't a valid directory!".format(directory.resolve()))
    entries = directory.rglob("*") if recursive else directory.glob("*")
    return [entry for entry in entries if entry.is_file()]


@click.command()
@click.option(
    "-d", "--img_dirs", required=True,
    help='directories to generate thumbnails seperated by space, eg: "dir1/dir2 dir3"'
)
@click.option(
    "-s", "--size", default="normal",
    type=click.Choice(list(THUMBNAIL_SIZES)),
    help="Thumbnail size: normal, large, x-large, xx-large"
)
@click.option("-w", "--workers", default=4, help="no of cpus to use for processing")
@click.option(
    "-i", "--only_images", is_flag=True, default=False,
    help="Whether to only look for images to be thumbnailed"
)
@click.option(
    "-r", "--recursive", is_flag=True, default=False,
    help="Whether to recursively look for files"
)
@click.option(
    "--machine_progress", is_flag=True, default=False,
    help="Print machine-readable progress lines instead of a progress bar"
)
def main(img_dirs: str, size: str, workers: str, only_images: bool,
         recursive: bool, machine_progress: bool) -> None:
    directories = [Path(directory) for directory in img_dirs.split()]
    for directory in directories:
        files = collect_files(directory, recursive)
        if only_images:
            files = [f for f in files if f.suffix.lower() in IMAGE_SUFFIXES]
        files = [str(file) for file in files]
        print("Found {} files in the directory: {}".format(
            len(files), directory.resolve()))

        completed = 0
        total = len(files)
        # The rendering itself happens in subprocesses, so threads are enough
        # to use several cores.
        with ThreadPoolExecutor(max_workers=max(1, int(workers))) as executor:
            futures = {
                executor.submit(make_thumbnail, Path(file_path), size): file_path
                for file_path in files
            }
            for future in as_completed(futures):
                file_path = futures[future]
                try:
                    future.result()
                except Exception as error:  # keep going on broken files
                    logger.debug("ERROR {}: {}".format(file_path, error))
                completed += 1
                if machine_progress:
                    print("PROGRESS {}/{} FILE {}".format(completed, total, file_path))
                    sys.stdout.flush()

    print("Thumbnail Generation Completed!")


if __name__ == "__main__":
    main()

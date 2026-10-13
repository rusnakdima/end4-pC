#!/usr/bin/env python3

# From https://github.com/difference-engine/thumbnail-generator-ubuntu (MIT License)
# Since the script is small and the maintainers seem inactive to accept my PR (#11) I decided to just copy it over.
# When it gets merged and the python package gets updated we can just use it

import os
import sys
from multiprocessing import Pool
from pathlib import Path
from typing import List, Union

import click
import gi
from loguru import logger
from tqdm import tqdm

gi.require_version("GnomeDesktop", "4.0")
from gi.repository import Gio, GnomeDesktop  # isort:skip

thumbnail_size_map = {
    "normal": GnomeDesktop.DesktopThumbnailSize.NORMAL,
    "large": GnomeDesktop.DesktopThumbnailSize.LARGE,
    "x-large": GnomeDesktop.DesktopThumbnailSize.XLARGE,
    "xx-large": GnomeDesktop.DesktopThumbnailSize.XXLARGE,
}

ffmpegthumbnailer_size_map = {
    "normal": 256,
    "large": 512,
    "x-large": 1024,
    "xx-large": 2048,
}

video_suffixes = {".mp4", ".webm", ".mkv", ".avi", ".mov", ".m4v", ".wmv", ".flv", ".ogv", ".3gp", ".qt"}

factory = None
thumb_size = "normal"
logger.remove()
logger.add(sys.stdout, level="INFO")
log_dir = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
logger.add(f"{log_dir}/thumbgen.log", level="DEBUG", rotation="100 MB")

def _generate_video_thumbnail(uri: str, mtime: float) -> bool:
    """Generate video thumbnail using ffmpegthumbnailer directly, save to freedesktop cache."""
    import hashlib
    import subprocess
    import urllib.parse

    # Compute freedesktop.org thumbnail cache path
    # Must match QtQuick's encodeURIComponent(path) per-segment, then md5
    raw_path = uri.replace("file://", "")
    encoded_path = "/".join(urllib.parse.quote(part, safe="") for part in raw_path.split("/"))
    h = hashlib.md5(("file://" + encoded_path).encode()).hexdigest()
    size_key = {"normal": "normal", "large": "large", "x-large": "x-large", "xx-large": "xx-large"}[thumb_size]
    cache_dir = Path.home() / ".cache" / "thumbnails" / size_key
    cache_dir.mkdir(parents=True, exist_ok=True)
    out_path = cache_dir / f"{h}.png"

    if out_path.exists() and os.path.getmtime(str(out_path)) >= mtime:
        logger.debug("FRESH       {}".format(uri))
        return False

    try:
        subprocess.run(
            ["ffmpegthumbnailer", "-s", str(ffmpegthumbnailer_size_map[thumb_size]),
             "-i", uri.replace("file://", ""), "-o", str(out_path)],
            check=True, capture_output=True, timeout=30
        )
        # Update mtime to match source
        os.utime(out_path, (mtime, mtime))
        logger.debug("OK          {}".format(uri))
        return True
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError) as e:
        logger.debug("ERROR       {}: {}".format(uri, e))
        return False

def make_thumbnail(fpath: str) -> bool:
    mtime = os.path.getmtime(fpath)
    # Use Gio to determine the URI and mime type
    f = Gio.file_new_for_path(str(fpath))
    uri = f.get_uri()
    info = f.query_info("standard::content-type", Gio.FileQueryInfoFlags.NONE, None)
    mime_type = info.get_content_type()

    # Handle video files with ffmpegthumbnailer directly
    if Path(fpath).suffix.lower() in video_suffixes or mime_type.startswith("video/"):
        return _generate_video_thumbnail(uri, mtime)

    if factory.lookup(uri, mtime) is not None:
        logger.debug("FRESH       {}".format(uri))
        return False

    if not factory.can_thumbnail(uri, mime_type, mtime):
        logger.debug("UNSUPPORTED {}".format(uri))
        return False

    thumbnail = factory.generate_thumbnail(uri, mime_type)
    if thumbnail is None:
        logger.debug("ERROR       {}".format(uri))
        return False

    logger.debug("OK          {}".format(uri))
    factory.save_thumbnail(thumbnail, uri, mtime)
    return True

def _pool_init(ts):
    global thumb_size
    thumb_size = ts

@logger.catch()
def thumbnail_folder(*, dir_path: Path, workers: int, only_images: bool, recursive: bool, machine_progress: bool = False) -> None:
    all_files = get_all_files(dir_path=dir_path, recursive=recursive)
    if only_images:
        all_files = get_all_images(all_files=all_files)
    all_files = [str(fpath) for fpath in all_files]
    if machine_progress:
        completed = 0
        total = len(all_files)
        with Pool(processes=workers, initializer=_pool_init, initargs=(thumb_size,)) as p:
            for result in p.imap(make_thumbnail, all_files):
                completed += 1
                print(f"PROGRESS {completed}/{total} FILE {all_files[completed-1]}")
                sys.stdout.flush()
    else:
        with Pool(processes=workers, initializer=_pool_init, initargs=(thumb_size,)) as p:
            list(tqdm(p.imap(make_thumbnail, all_files), total=len(all_files)))


def get_all_images(*, all_files: List[Path]) -> List[Path]:
    img_suffixes = [".jpg", ".jpeg", ".png", ".gif", ".mp4", ".webm", ".mkv", ".avi", ".mov", ".m4v", ".wmv", ".flv", ".ogv", ".3gp", ".qt"]
    all_images = [fpath for fpath in all_files if fpath.suffix in img_suffixes]
    print("Found {} images".format(len(all_images)))
    return all_images


def get_all_files(*, dir_path: Path, recursive: bool) -> List[Path]:
    if not (dir_path.exists() and dir_path.is_dir()):
        raise ValueError("{} doesn't exist or isn't a valid directory!".format(dir_path.resolve()))
    if recursive:
        all_files = dir_path.rglob("*")
    else:
        all_files = dir_path.glob("*")
    all_files = [fpath for fpath in all_files if fpath.is_file()]
    print("Found {} files in the directory: {}".format(len(all_files), dir_path.resolve()))
    return all_files

@click.command()
@click.option(
    "-d", "--img_dirs", required=True, help='directories to generate thumbnails seperated by space, eg: "dir1/dir2 dir3"'
)
@click.option(
    "-s", "--size", default="normal", type=click.Choice(["normal", "large", "x-large", "xx-large"]), help="Thumbnail size: normal, large, x-large, xx-large"
)
@click.option("-w", "--workers", default=1, help="no of cpus to use for processing")
@click.option(
    "-i", "--only_images", is_flag=True, default=False, help="Whether to only look for images to be thumbnailed"
)
@click.option("-r", "--recursive", is_flag=True, default=False, help="Whether to recursively look for files")
@click.option("--machine_progress", is_flag=True, default=False, help="Print machine-readable progress lines instead of a progress bar")
def main(img_dirs: str, size: str, workers: str, only_images: bool, recursive: bool, machine_progress: bool) -> None:
    img_dirs = [Path(img_dir) for img_dir in img_dirs.split()]
    global factory, thumb_size
    thumb_size = size
    factory = GnomeDesktop.DesktopThumbnailFactory.new(thumbnail_size_map[size])
    for img_dir in img_dirs:
        thumbnail_folder(dir_path=img_dir, workers=workers, only_images=only_images, recursive=recursive, machine_progress=machine_progress)
    print("Thumbnail Generation Completed!")


if __name__ == "__main__":
    main()

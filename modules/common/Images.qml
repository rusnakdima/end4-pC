pragma Singleton

import Quickshell

Singleton {
    // Formats
    readonly property list<string> validImageTypes: ["jpeg", "png", "webp", "tiff", "svg"]
    readonly property list<string> validImageExtensions: ["jpg", "jpeg", "png", "webp", "avif", "bmp", "tif", "tiff", "svg",
        "mp4", "webm", "mkv", "avi", "mov", "gif", "m4v", "wmv", "flv", "ogv", "3gp", "qt"]

    function isValidImageByName(name: string): bool {
        const lower = (name || "").toLowerCase();
        return validImageExtensions.some(t => lower.endsWith(`.${t}`));
    }

    // Video files are valid wallpaper sources, but a plain Image element cannot
    // decode them. Surfaces that render a wallpaper as an image resolve the
    // path to a thumbnail first, so those surfaces never try to decode a clip.
    readonly property var videoExtensions: ["mp4", "webm", "mkv", "avi", "mov", "gif", "m4v", "wmv", "flv", "ogv", "3gp", "qt"]
    function isVideoPath(path: string): bool {
        const lower = (path || "").toLowerCase();
        return videoExtensions.some(t => lower.endsWith(`.${t}`));
    }

    // Thumbnails
    // https://specifications.freedesktop.org/thumbnail-spec/latest/directory.html
    readonly property var thumbnailSizes: ({
        "normal": 128,
        "large": 256,
        "x-large": 512,
        "xx-large": 1024
    })
    function thumbnailSizeNameForDimensions(width: int, height: int): string {
        const sizeNames = Object.keys(thumbnailSizes);
        for(let i = 0; i < sizeNames.length; i++) {
            const sizeName = sizeNames[i];
            const maxSize = thumbnailSizes[sizeName];
            if (width <= maxSize && height <= maxSize) return sizeName;
        }
        return "xx-large";
    }
}

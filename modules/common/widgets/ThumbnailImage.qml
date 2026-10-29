import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Thumbnail image. It currently generates to the right place at the right size, but does not handle metadata/maintenance on modification.
 * See Freedesktop's spec: https://specifications.freedesktop.org/thumbnail-spec/thumbnail-spec-latest.html
 *
 * The thumbnail is looked up in the freedesktop cache. When the requested size
 * is not cached yet, the bigger cache buckets are used first (they stay sharp
 * when scaled down) and the smaller ones afterwards, so a cell never ends up
 * empty just because one cache size is missing. As a last resort the thumbnail
 * is rendered on demand: images with ImageMagick, videos with ffmpeg.
 */
StyledImage {
    id: root

    property bool generateThumbnail: true
    required property string sourcePath

    readonly property bool isVideoSource: Images.isVideoPath(sourcePath)

    // The cache bucket the thumbnail should be in. It is writable so that
    // users can request a specific size instead of the computed one.
    property string thumbnailSizeName: Images.thumbnailSizeNameForDimensions(sourceSize.width, sourceSize.height)
    readonly property string effectiveSizeName: root.isVideoSource ? "large" : root.thumbnailSizeName
    // Every cache bucket, the requested one first, then the bigger ones and
    // finally the smaller ones.
    readonly property var sizeCandidates: root.isVideoSource
        ? ["large"]
        : (function() {
            const order = ["normal", "large", "x-large", "xx-large"];
            const index = order.indexOf(root.thumbnailSizeName);
            if (index < 0) return [root.thumbnailSizeName];
            return order.slice(index).concat(order.slice(0, index).reverse());
        })()
    property int candidateIndex: 0
    readonly property string candidateSizeName: sizeCandidates[candidateIndex] || root.effectiveSizeName

    // Generation is retried a couple of times, but never endlessly: a file
    // that cannot be rendered would otherwise make the process restart in a
    // loop and burn the CPU.
    property int generationAttempts: 0
    readonly property int maxGenerationAttempts: 4

    // The path of the thumbnail that is currently displayed. It is set
    // explicitly instead of being bound so that the image can be reloaded
    // after a thumbnail has been generated.
    property string activePath: ""

    function thumbnailPathFor(sizeName) {
        if (sourcePath.length === 0) return "";
        const resolvedUrlWithoutFileProtocol = FileUtils.trimFileProtocol(`${Qt.resolvedUrl(sourcePath)}`);
        const encodedUrlWithoutFileProtocol = resolvedUrlWithoutFileProtocol.split("/").map(part => encodeURIComponent(part)).join("/");
        const md5Hash = Qt.md5(`file://${encodedUrlWithoutFileProtocol}`);
        return `${Directories.genericCache}/thumbnails/${sizeName}/${md5Hash}.png`;
    }

    // The path of the thumbnail in the requested cache size.
    readonly property string thumbnailPath: thumbnailPathFor(root.effectiveSizeName)

    function loadCandidate(index) {
        candidateIndex = Math.max(0, Math.min(index, sizeCandidates.length - 1));
        activePath = "";
        activePath = thumbnailPathFor(candidateSizeName);
    }

    // Reloads the thumbnail, used when it was generated elsewhere.
    function reload() {
        loadCandidate(0);
    }

    source: activePath

    asynchronous: true
    smooth: true
    mipmap: false

    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Component.onCompleted: {
        loadCandidate(0);
    }

    // Renders the thumbnail on demand. The number of attempts is bounded,
    // so a file that cannot be rendered never makes the process restart in
    // an endless loop.
    function startGeneration() {
        if (!root.generateThumbnail) return;
        if (root.generationAttempts >= root.maxGenerationAttempts) return;
        root.generationAttempts++;
        thumbnailGeneration.running = false;
        thumbnailGeneration.running = true;
    }

    onSourceSizeChanged: {
        // A new size selects another cache bucket, so the thumbnail has to
        // be rendered for it. The attempts of the previous size are over.
        root.generationAttempts = 0;
        startGeneration();
    }

    onStatusChanged: {
        if (status === Image.Ready) {
            // The thumbnail is there, further attempts are allowed again.
            root.generationAttempts = 0;
            return;
        }
        if (status !== Image.Error) return;
        // The current cache bucket has no thumbnail, try the next one.
        if (candidateIndex < sizeCandidates.length - 1) {
            loadCandidate(candidateIndex + 1);
            return;
        }
        // No cached thumbnail at all, render one.
        startGeneration();
    }

    Process {
        id: thumbnailGeneration
        command: {
            const maxSize = Images.thumbnailSizes[root.effectiveSizeName];
            const thumbPath = FileUtils.trimFileProtocol(root.thumbnailPathFor(root.effectiveSizeName));
            const source = FileUtils.trimFileProtocol(root.sourcePath);
            const isVideo = Images.isVideoPath(source);
            // Paths are passed as positional args ($1..$3), never interpolated into the
            // script, so quotes in file names can neither break nor inject into it.
            // Exit codes: 0 = already cached, 1 = generated, 2 = failed.
            if (isVideo) {
                // The first frame of a clip is usually black (fade in) and would
                // look like a broken preview, so a frame a few seconds in is
                // used. When no frame can be rendered at all, a flat
                // placeholder is written: the cell is never blank.
                return ["bash", "-c", `
                    thumb="$1"; src="$2"; max="$3"
                    [ -f "$thumb" ] && exit 0
                    mkdir -p "$(dirname "$thumb")" || exit 2
                    tmp="$thumb.$$.tmp.png"
                    trap 'rm -f "$tmp"' EXIT
                    for seek in 00:00:03 00:00:01 00:00:00; do
                        ffmpeg -y -ss "$seek" -i "$src" -frames:v 1 -vf "scale=$max:$max:force_original_aspect_ratio=decrease" "$tmp" >/dev/null 2>&1 && mv "$tmp" "$thumb" && exit 1
                    done
                    magick -size "$max"x"$max" xc:'#202020' "$thumb" >/dev/null 2>&1 && exit 1
                    exit 2
                `, "_", thumbPath, source, `${maxSize}`];
            }
            return ["bash", "-c", `
                thumb="$1"; src="$2"; max="$3"
                [ -f "$thumb" ] && exit 0
                mkdir -p "$(dirname "$thumb")" || exit 2
                tmp="$thumb.$$.tmp.png"
                trap 'kill "$pid" 2>/dev/null; rm -f "$tmp"' EXIT
                magick "$src" -auto-orient -resize "$max"x"$max" "$tmp" & pid=$!
                wait "$pid" && mv "$tmp" "$thumb" && exit 1
                exit 2
            `, "_", thumbPath, source, `${maxSize}`];
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 1) {
                root.loadCandidate(0);
                return;
            }
            if (exitCode !== 2) return;
            // Nothing could be rendered: show the file itself, so a still
            // image is never reduced to an empty cell.
            const source = FileUtils.trimFileProtocol(root.sourcePath);
            const isVideo = Images.isVideoPath(source);
            if (isVideo) return;
            root.activePath = Qt.resolvedUrl(root.sourcePath);
        }
    }
}

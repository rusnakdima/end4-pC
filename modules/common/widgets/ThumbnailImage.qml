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

    onSourceSizeChanged: {
        if (!root.generateThumbnail) return;
        thumbnailGeneration.running = false;
        thumbnailGeneration.running = true;
    }

    onStatusChanged: {
        if (status !== Image.Error) return;
        // The current cache bucket has no thumbnail, try the next one.
        if (candidateIndex < sizeCandidates.length - 1) {
            loadCandidate(candidateIndex + 1);
            return;
        }
        // No cached thumbnail at all, render one.
        if (root.generateThumbnail) {
            thumbnailGeneration.running = false;
            thumbnailGeneration.running = true;
        }
    }

    Process {
        id: thumbnailGeneration
        command: {
            const maxSize = Images.thumbnailSizes[root.effectiveSizeName];
            const thumbPath = FileUtils.trimFileProtocol(root.thumbnailPathFor(root.effectiveSizeName));
            const source = FileUtils.trimFileProtocol(root.sourcePath);
            const tmp = `${thumbPath}.$$.tmp.png`;
            const isVideo = Images.isVideoPath(source);
            if (isVideo) {
                // The first frame of a clip is usually black (fade in) and would
                // look like a broken preview, so a frame a few seconds in is
                // used. When no frame can be rendered at all, a flat
                // placeholder is written: the cell is never blank.
                return ["bash", "-c",
                    `if [ -f '${thumbPath}' ]; then exit 0; fi; ` +
                    `for seek in 00:00:03 00:00:01 00:00:00; do ` +
                    `ffmpeg -y -ss "$seek" -i '${source}' -frames:v 1 -vf 'scale=${maxSize}:${maxSize}:force_original_aspect_ratio=decrease' '${tmp}' >/dev/null 2>&1 && mv '${tmp}' '${thumbPath}' && exit 1; ` +
                    `done; ` +
                    `magick -size ${maxSize}x${maxSize} xc:'#202020' '${thumbPath}' >/dev/null 2>&1 && exit 1; exit 2;`
                ];
            }
            return ["bash", "-c",
                `if [ -f '${thumbPath}' ]; then exit 0; fi; ` +
                `magick '${source}' -auto-orient -resize ${maxSize}x${maxSize} '${tmp}' >/dev/null 2>&1 && mv '${tmp}' '${thumbPath}' && exit 1; exit 2;`
            ];
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

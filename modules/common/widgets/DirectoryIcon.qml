import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3

Image {
    id: root
    required property var fileModelData
    asynchronous: true
    fillMode: Image.PreserveAspectFit

    readonly property bool isDirectory: fileModelData ? Boolean(fileModelData.fileIsDir) : false

    // Candidate icon names in preference order. The first one the configured
    // theme can resolve wins. Every lookup goes through iconPath(..., true),
    // which returns an empty string for a missing icon instead of the
    // missing-texture placeholder, so a theme gap can never render as a
    // magenta checkerboard in the cell.
    readonly property var candidates: {
        if (!fileModelData) return [];
        if (!root.isDirectory) return ["application-x-zerosize"];
        const name = `${fileModelData.fileName}`.toLowerCase();
        const isStandardDir = [Directories.documents, Directories.downloads, Directories.music,
            Directories.pictures, Directories.videos]
            .some(dir => FileUtils.trimFileProtocol(dir) === fileModelData.filePath);
        return (isStandardDir ? [`folder-${name}`] : []).concat(["folder", "inode-directory"]);
    }

    // Raised when a resolved path still fails to decode, so the next
    // candidate is tried instead of showing a broken image.
    property int candidateIndex: 0

    // Set by the mime probe below for regular files; keeps the source a
    // binding instead of being overwritten imperatively.
    property string mimeSource: ""

    // The bundled glyph: always present, shown only when the theme has
    // nothing to offer. Regular files get no fallback rather than a wrong one.
    readonly property url bundledFallback: root.isDirectory
        ? Qt.resolvedUrl(`${Directories.assetsPath}/icons/folder.svg`)
        : ""

    readonly property string resolvedSource: {
        // SystemAppearance.iconPath reads iconRevision, so this binding
        // re-resolves once the resolver has answered for the theme.
        for (let i = root.candidateIndex; i < root.candidates.length; i++) {
            const path = SystemAppearance.iconPath(root.candidates[i], true);
            if (path && path.length > 0) return path;
        }
        return "";
    }

    source: {
        if (root.mimeSource.length > 0) return root.mimeSource;
        const resolved = root.resolvedSource;
        if (resolved.length > 0) return resolved;
        return root.bundledFallback;
    }

    onStatusChanged: {
        if (status !== Image.Error) return;
        if (root.candidateIndex < root.candidates.length - 1) {
            root.candidateIndex++;
            return;
        }
        // Every candidate failed to decode: fall back to the bundled glyph.
        if (root.bundledFallback.toString().length > 0 && source !== root.bundledFallback)
            source = root.bundledFallback;
    }

    Process {
        running: root.fileModelData && !root.fileModelData.fileIsDir
        command: ["file", "--mime", "-b", root.fileModelData ? root.fileModelData.filePath : ""]
        stdout: StdioCollector {
            onStreamFinished: {
                const mime = text.split(";")[0].replace("/", "-");
                root.mimeSource = Images.validImageTypes.some(t => mime === `image-${t}`)
                    ? root.fileModelData.fileUrl
                    : SystemAppearance.iconPath(mime, "image-missing");
            }
        }
    }
}

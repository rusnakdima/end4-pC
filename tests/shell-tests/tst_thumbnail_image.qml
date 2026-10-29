import QtQuick
import QtTest
import qs.modules.common
import qs.modules.common.widgets

/**
 * Tests for the thumbnail widget.
 *
 * The widget looks the thumbnail of a file up in the freedesktop cache: the
 * name of the cache file is the md5 of the encoded file url of the source,
 * and the cache buckets are tried from the requested one over the bigger
 * ones to the smaller ones, so a cell never stays empty just because one
 * bucket of the cache is missing.
 *
 * The widget never renders a thumbnail here: that would spawn magick or
 * ffmpeg on the machine of the user.
 */
TestCase {
    id: testCase
    name: "ThumbnailImage"
    when: true

    Component {
        id: thumbnailFactory
        ThumbnailImage {}
    }

    function makeThumbnail(sourcePath) {
        return thumbnailFactory.createObject(null, {
            "sourcePath": sourcePath,
            "generateThumbnail": false
        });
    }

    function test_the_cache_file_is_named_after_the_md5_of_the_file_url() {
        const thumbnail = makeThumbnail("/tmp/end4pc-thumbnail-source.png");
        verify(thumbnail !== null);

        // The freedesktop thumbnail spec names the cache file after the md5
        // of the url of the source, encoded path segment by path segment.
        compare(
            thumbnail.thumbnailPathFor("normal"),
            Directories.genericCache + "/thumbnails/normal/5560ab54c205dd9a123cab350da49ed6.png");
    }

    function test_every_cache_bucket_holds_the_same_hash() {
        const thumbnail = makeThumbnail("/tmp/end4pc-thumbnail-source.png");

        const normal = thumbnail.thumbnailPathFor("normal");
        const large = thumbnail.thumbnailPathFor("large");

        verify(normal !== large);
        verify(normal.includes("/thumbnails/normal/"));
        verify(large.includes("/thumbnails/large/"));
        compare(normal.split("/").pop(), large.split("/").pop());
    }

    function test_a_source_without_a_path_has_no_thumbnail() {
        const thumbnail = makeThumbnail("");

        compare(thumbnail.thumbnailPathFor("normal"), "");
        compare(thumbnail.thumbnailPath, "");
    }

    function test_a_video_is_thumbnailed_in_the_large_bucket() {
        const thumbnail = makeThumbnail("/tmp/end4pc-missing-clip.mp4");

        verify(thumbnail.isVideoSource);
        compare(thumbnail.effectiveSizeName, "large");
        compare(thumbnail.sizeCandidates.length, 1);
        compare(thumbnail.sizeCandidates[0], "large");
        compare(thumbnail.thumbnailPath, thumbnail.thumbnailPathFor("large"));
    }

    function test_an_image_is_not_a_video() {
        // The source does not exist, so the widget knows no size yet and
        // falls back to the smallest cache bucket.
        const thumbnail = makeThumbnail("/tmp/end4pc-missing-photo.png");

        verify(!thumbnail.isVideoSource);
        compare(thumbnail.thumbnailSizeName, "normal");
        compare(thumbnail.effectiveSizeName, "normal");
    }

    function test_the_bigger_buckets_are_tried_before_the_smaller_ones() {
        const thumbnail = makeThumbnail("/tmp/end4pc-missing-photo.png");

        thumbnail.thumbnailSizeName = "normal";
        compare(thumbnail.sizeCandidates.join(","), "normal,large,x-large,xx-large");

        thumbnail.thumbnailSizeName = "large";
        compare(thumbnail.sizeCandidates.join(","), "large,x-large,xx-large,normal");

        thumbnail.thumbnailSizeName = "x-large";
        compare(thumbnail.sizeCandidates.join(","), "x-large,xx-large,large,normal");

        thumbnail.thumbnailSizeName = "xx-large";
        compare(thumbnail.sizeCandidates.join(","), "xx-large,x-large,large,normal");
    }

    function test_an_unknown_bucket_name_is_used_as_it_is() {
        const thumbnail = makeThumbnail("/tmp/end4pc-missing-photo.png");

        thumbnail.thumbnailSizeName = "huge";

        compare(thumbnail.sizeCandidates.length, 1);
        compare(thumbnail.sizeCandidates[0], "huge");
    }

    function test_loading_a_candidate_shows_the_thumbnail_of_that_bucket() {
        const thumbnail = makeThumbnail("/tmp/end4pc-missing-photo.png");
        thumbnail.thumbnailSizeName = "large";

        thumbnail.loadCandidate(0);
        compare(thumbnail.candidateIndex, 0);
        compare(thumbnail.candidateSizeName, "large");
        compare(thumbnail.activePath, thumbnail.thumbnailPathFor("large"));

        thumbnail.loadCandidate(2);
        compare(thumbnail.candidateIndex, 2);
        compare(thumbnail.candidateSizeName, "x-large");
        compare(thumbnail.activePath, thumbnail.thumbnailPathFor("x-large"));
    }

    function test_the_candidate_index_stays_inside_the_buckets() {
        const thumbnail = makeThumbnail("/tmp/end4pc-missing-photo.png");
        thumbnail.thumbnailSizeName = "large";

        thumbnail.loadCandidate(99);
        compare(thumbnail.candidateIndex, 3);
        compare(thumbnail.candidateSizeName, "normal");

        thumbnail.loadCandidate(-5);
        compare(thumbnail.candidateIndex, 0);
        compare(thumbnail.candidateSizeName, "large");
    }

    function test_a_reload_starts_over_at_the_requested_bucket() {
        const thumbnail = makeThumbnail("/tmp/end4pc-missing-photo.png");
        thumbnail.thumbnailSizeName = "large";

        thumbnail.loadCandidate(2);
        compare(thumbnail.candidateIndex, 2);

        thumbnail.reload();
        compare(thumbnail.candidateIndex, 0);
        compare(thumbnail.activePath, thumbnail.thumbnailPathFor("large"));
    }
}

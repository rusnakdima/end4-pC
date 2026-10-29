import QtQuick
import QtTest
import qs.modules.common

/**
 * The images module answers whether a file can be used as a wallpaper and
 * which thumbnail bucket a wallpaper of a given size belongs to.
 */
TestCase {
    id: testCase
    name: "Images"
    when: true

    function test_a_known_image_extension_is_valid() {
        verify(Images.isValidImageByName("wallpaper.png"));
        verify(Images.isValidImageByName("wallpaper.JPEG"));
        verify(Images.isValidImageByName("wallpaper.webp"));
    }

    function test_a_video_extension_is_valid_as_a_wallpaper_source() {
        // The wallpaper picker offers videos too, so a video name has to be
        // accepted here even though an Image element cannot decode it.
        verify(Images.isValidImageByName("clip.mp4"));
        verify(Images.isValidImageByName("clip.WEBM"));
    }

    function test_an_unknown_extension_is_not_valid() {
        verify(!Images.isValidImageByName("notes.txt"));
        verify(!Images.isValidImageByName("archive.tar.gz"));
        verify(!Images.isValidImageByName(""));
    }

    function test_a_video_path_is_recognised() {
        verify(Images.isVideoPath("clip.mp4"));
        verify(Images.isVideoPath("clip.mkv"));
        verify(!Images.isVideoPath("wallpaper.png"));
    }

    function test_the_thumbnail_buckets_start_at_their_lower_bound() {
        compare(Images.thumbnailSizeNameForDimensions(128, 128), "normal");
        compare(Images.thumbnailSizeNameForDimensions(256, 256), "large");
        compare(Images.thumbnailSizeNameForDimensions(512, 512), "x-large");
        compare(Images.thumbnailSizeNameForDimensions(1024, 1024), "xx-large");
    }

    function test_a_size_above_a_bucket_belongs_to_the_next_one() {
        compare(Images.thumbnailSizeNameForDimensions(129, 129), "large");
        compare(Images.thumbnailSizeNameForDimensions(257, 257), "x-large");
        compare(Images.thumbnailSizeNameForDimensions(513, 513), "xx-large");
    }

    function test_a_size_above_every_bucket_stays_in_the_largest_one() {
        compare(Images.thumbnailSizeNameForDimensions(1025, 1025), "xx-large");
        compare(Images.thumbnailSizeNameForDimensions(4096, 4096), "xx-large");
    }
}

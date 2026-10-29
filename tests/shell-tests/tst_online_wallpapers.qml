import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common

/**
 * Tests for the online wallpaper service.
 *
 * The service offers two kinds of providers: the API providers (wallhaven,
 * unsplash, pexels), which are listed in the resolution map, and the local
 * stream providers (naive, blapples), which read a json index from a fixed
 * GitHub raw URL. The mapping functions that turn a raw record into a
 * result are pure, so the URLs the service builds - including the encoding
 * of the file names - can be asserted here.
 */
TestCase {
    id: testCase
    name: "OnlineWallpapers"
    when: true

    function test_the_defaults_of_the_service() {
        compare(OnlineWallpapers.provider, "wallhaven");
        compare(OnlineWallpapers.resolution, "1080p");
        compare(OnlineWallpapers.query, "");
        compare(OnlineWallpapers.purity, "sfw");
        compare(OnlineWallpapers.category, "general");
        compare(OnlineWallpapers.page, 1);
        compare(OnlineWallpapers.localPageSize, 24);
        compare(OnlineWallpapers.results.length, 0);
    }

    function test_the_api_providers_are_the_ones_with_a_resolution_map() {
        const providers = Object.keys(OnlineWallpapers.resolutionMap).sort();
        compare(providers.join(","), "pexels,unsplash,wallhaven");
    }

    function test_the_resolution_map_of_the_wallhaven_provider() {
        const map = OnlineWallpapers.resolutionMap["wallhaven"];
        compare(map["1080p"], "1920x1080");
        compare(map["2K"], "2560x1440");
        compare(map["4K"], "3840x2160");
    }

    function test_the_resolution_map_of_the_unsplash_and_pexels_providers() {
        for (const provider of ["unsplash", "pexels"]) {
            const map = OnlineWallpapers.resolutionMap[provider];
            compare(map["1080p"], "&w=1920&h=1080&fit=crop");
            compare(map["2K"], "&w=2560&h=1440&fit=crop");
            compare(map["4K"], "&w=3840&h=2160&fit=crop");
        }
    }

    function test_the_purity_map_of_the_wallhaven_provider() {
        const map = OnlineWallpapers.purityMap;
        compare(map["sfw"], "100");
        compare(map["sketchy"], "110");
        compare(map["nsfw"], "111");
    }

    function test_the_urls_of_the_local_stream_providers() {
        compare(OnlineWallpapers.naiveJsonUrl, "https://raw.githubusercontent.com/na-ive/wallpapers/gh-pages/wallpapers.json");
        compare(OnlineWallpapers.naivePagesBase, "https://raw.githubusercontent.com/na-ive/wallpapers/gh-pages/");
        compare(OnlineWallpapers.naiveFullBase, "https://raw.githubusercontent.com/na-ive/wallpapers/main/");
        compare(OnlineWallpapers.blapplesJsonUrl, "https://raw.githubusercontent.com/Blapples/wallpapers/main/wallpapers.json");
        compare(OnlineWallpapers.blapplesPagesBase, "https://raw.githubusercontent.com/Blapples/wallpapers/main/");
        compare(OnlineWallpapers.blapplesFullBase, "https://raw.githubusercontent.com/Blapples/wallpapers/main/");
    }

    function test_the_naive_provider_maps_a_record_to_its_urls() {
        const item = OnlineWallpapers._mapNaive({
            filename: "my wall.png",
            resolution: "1920x1080",
            thumbnail: "thumbs/my wall.png"
        });

        compare(item.provider, "naive");
        compare(item.id, "my wall");
        compare(item.full, "https://raw.githubusercontent.com/na-ive/wallpapers/main/my%20wall.png");
        compare(item.thumb, "https://raw.githubusercontent.com/na-ive/wallpapers/gh-pages/thumbs/my wall.png");
        compare(item.width, 1920);
        compare(item.height, 1080);
        compare(item.title, "My Wall");
    }

    function test_the_blapples_provider_encodes_every_path_segment() {
        const item = OnlineWallpapers._mapBlapples({
            filename: "wall paper.png",
            resolution: "2560x1440",
            thumbnail: "previews/wall paper.png"
        });

        compare(item.provider, "blapples");
        compare(item.id, "wall paper");
        compare(item.full, "https://raw.githubusercontent.com/Blapples/wallpapers/main/wall%20paper.png");
        compare(item.thumb, "https://raw.githubusercontent.com/Blapples/wallpapers/main/previews/wall%20paper.png");
        compare(item.width, 2560);
        compare(item.height, 1440);
    }

    function test_a_record_without_a_resolution_has_no_dimensions() {
        const item = OnlineWallpapers._mapNaive({ filename: "a.png" });
        compare(item.width, 0);
        compare(item.height, 0);
    }

    function test_the_local_filter_matches_the_file_name() {
        OnlineWallpapers.query = "sunset";
        verify(OnlineWallpapers._matchesLocalFilters({ filename: "Sunset Beach.jpg" }));
        verify(!OnlineWallpapers._matchesLocalFilters({ filename: "mountain.jpg" }));
        OnlineWallpapers.query = "";
    }

    function test_the_local_filter_matches_the_color_group() {
        OnlineWallpapers.colorGroup = "orange";
        verify(OnlineWallpapers._matchesLocalFilters({ filename: "a.png", color_groups: ["orange", "red"] }));
        verify(!OnlineWallpapers._matchesLocalFilters({ filename: "a.png", color_groups: ["blue"] }));
        OnlineWallpapers.colorGroup = "";
    }

    function test_the_local_filter_rejects_a_record_without_a_file_name() {
        verify(!OnlineWallpapers._matchesLocalFilters({}));
        verify(!OnlineWallpapers._matchesLocalFilters(null));
    }
}

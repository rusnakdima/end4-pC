import QtQuick
import QtTest
import qs.modules.common.functions

/**
 * Tests for the notification helpers.
 *
 * The helpers turn a raw notification into the icon, the relative time and
 * the body the notification popup shows, so the empty input and the bodies
 * of the browser notifications matter as much as the ordinary ones.
 */
TestCase {
    id: testCase
    name: "Notifications"
    when: true

    function test_empty_summary_gets_the_default_symbol() {
        compare(NotificationUtils.findSuitableMaterialSymbol(""), "chat");
        compare(NotificationUtils.findSuitableMaterialSymbol(), "chat");
    }

    function test_summary_without_a_keyword_gets_the_default_symbol() {
        compare(NotificationUtils.findSuitableMaterialSymbol("Hello there"), "chat");
        compare(NotificationUtils.findSuitableMaterialSymbol("Something happened"), "chat");
    }

    function test_a_keyword_in_the_summary_picks_its_symbol() {
        compare(NotificationUtils.findSuitableMaterialSymbol("Reboot required"), "restart_alt");
        compare(NotificationUtils.findSuitableMaterialSymbol("Battery low"), "power");
        compare(NotificationUtils.findSuitableMaterialSymbol("Update available"), "update");
        compare(NotificationUtils.findSuitableMaterialSymbol("Music playing"), "queue_music");
        compare(NotificationUtils.findSuitableMaterialSymbol("Screenshot taken"), "screenshot_monitor");
    }

    function test_the_keyword_is_matched_case_insensitively() {
        compare(NotificationUtils.findSuitableMaterialSymbol("REBOOT"), "restart_alt");
        compare(NotificationUtils.findSuitableMaterialSymbol("bAtTeRy"), "power");
    }

    function test_the_file_rule_matches_the_start_of_the_summary() {
        // The "startswith:file" rule is a declarative prefix check.
        compare(NotificationUtils.findSuitableMaterialSymbol("file.txt opened"), "folder_copy");
        compare(NotificationUtils.findSuitableMaterialSymbol("File Manager"), "folder_copy");
    }

    function test_the_first_matching_keyword_wins() {
        // The keywords are checked in the order of the table, so a summary
        // that contains an earlier keyword gets that keyword's symbol even
        // when it starts with "file".
        compare(NotificationUtils.findSuitableMaterialSymbol("file updated"), "update");
        compare(NotificationUtils.findSuitableMaterialSymbol("file music"), "queue_music");
        // "installed" is before "install" in the table.
        compare(NotificationUtils.findSuitableMaterialSymbol("installed"), "download");
        compare(NotificationUtils.findSuitableMaterialSymbol("install"), "deployed_code_update");
        compare(NotificationUtils.findSuitableMaterialSymbol("meeting time"), "schedule");
    }

    function test_a_fresh_notification_says_now() {
        compare(NotificationUtils.getFriendlyNotifTimeString(Date.now() - 30000), "Now");
        compare(NotificationUtils.getFriendlyNotifTimeString(Date.now() - 59000), "Now");
    }

    function test_a_notification_of_the_same_day_is_shown_in_minutes_or_hours() {
        const now = Date.now();
        const fiveMinutes = now - 5 * 60000;
        const threeHours = now - 3 * 3600000;

        // The helper buckets by the calendar day of the timestamp, so a
        // timestamp that reaches back over midnight is a "Yesterday" one
        // instead of a relative one. That only happens in the first minutes
        // (resp. hours) after midnight.
        const sameDay = new Date(fiveMinutes).toDateString() === new Date(now).toDateString();
        compare(
            NotificationUtils.getFriendlyNotifTimeString(fiveMinutes),
            sameDay ? "5m" : "Yesterday");

        const sameDayHours = new Date(threeHours).toDateString() === new Date(now).toDateString();
        compare(
            NotificationUtils.getFriendlyNotifTimeString(threeHours),
            sameDayHours ? "3h" : "Yesterday");
    }

    function test_a_notification_of_yesterday_says_yesterday() {
        compare(NotificationUtils.getFriendlyNotifTimeString(Date.now() - 24 * 3600000), "Yesterday");
    }

    function test_an_older_notification_gets_the_date() {
        const old = Date.now() - 3 * 24 * 3600000;
        compare(
            NotificationUtils.getFriendlyNotifTimeString(old),
            Qt.formatDateTime(new Date(old), "MMMM dd"));
    }

    function test_a_notification_without_a_timestamp_has_no_time() {
        compare(NotificationUtils.getFriendlyNotifTimeString(""), "");
        compare(NotificationUtils.getFriendlyNotifTimeString(0), "");
        compare(NotificationUtils.getFriendlyNotifTimeString(null), "");
    }

    function test_an_invalid_timestamp_has_no_time() {
        // A date that cannot be parsed formats into the empty string.
        compare(NotificationUtils.getFriendlyNotifTimeString("not a date"), "");
    }

    function test_a_body_is_required() {
        // DEFECT: the helper dereferences the body without a guard, so a
        // notification without a body throws a TypeError instead of
        // returning an empty body.
        let thrown = false;
        try {
            NotificationUtils.processNotificationBody(undefined, "Terminal");
        } catch (error) {
            thrown = true;
        }
        verify(thrown);
    }

    function test_the_browser_notification_loses_its_first_line() {
        // Chromium based browsers put the origin of the notification into
        // the first paragraph, which the popup does not show.
        compare(
            NotificationUtils.processNotificationBody("<a href='x'>link</a>\n\nReal body", "Chromium"),
            "Real body");
        compare(
            NotificationUtils.processNotificationBody("<a href='x'>link</a>\n\nReal body", "brave"),
            "Real body");
        compare(
            NotificationUtils.processNotificationBody("<a href='x'>link</a>\n\nReal body", "Microsoft Edge"),
            "Real body");
    }

    function test_only_the_first_paragraph_of_a_browser_notification_is_dropped() {
        compare(
            NotificationUtils.processNotificationBody("<a href='x'>link</a>\n\nFirst\n\nSecond", "Vivaldi"),
            "First\n\nSecond");
    }

    function test_a_browser_notification_without_a_blank_line_keeps_its_body() {
        compare(
            NotificationUtils.processNotificationBody("<a>x</a>", "Chromium"),
            "<a>x</a>");
        compare(
            NotificationUtils.processNotificationBody("<b>x</b>\n\nbody", "Chromium"),
            "<b>x</b>\n\nbody");
    }

    function test_a_notification_of_another_app_keeps_its_body() {
        compare(
            NotificationUtils.processNotificationBody("<a href='x'>link</a>\n\nReal body", "Terminal"),
            "<a href='x'>link</a>\n\nReal body");
        compare(
            NotificationUtils.processNotificationBody("<a href='x'>link</a>\n\nReal body", "Firefox"),
            "<a href='x'>link</a>\n\nReal body");
    }

    function test_an_image_gets_a_blank_line_before_it() {
        compare(
            NotificationUtils.processNotificationBody("text<img src='y'>", "Slack"),
            "text\n\n<img src='y'>");
        compare(
            NotificationUtils.processNotificationBody("<img src='y'>", "Slack"),
            "\n\n<img src='y'>");
    }
}

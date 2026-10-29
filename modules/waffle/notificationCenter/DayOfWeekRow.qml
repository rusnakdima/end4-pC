import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common.functions

// Weekday header of the waffle notification centre's calendar.
// The end4-pC "WeekRow" widget does not expose a short weekday name, which the
// waffle calendar needs, so this widget is the waffle-specific variant.
RowLayout {
    id: root

    required property var locale
    property date date: new Date()

    property list<var> model: {
        // QLocale.firstDayOfWeek uses the Qt enum (Mon = 1 ... Sun = 7), while
        // DateUtils.getFirstDayOfWeek expects the JS convention (Sun = 0 ... Sat = 6).
        const jsFirstDay = root.locale.firstDayOfWeek % 7;
        const firstDayOfWeek = DateUtils.getFirstDayOfWeek(root.date, jsFirstDay);
        const days = [];
        for (let i = 0; i < 7; i++) {
            const dayDate = new Date(firstDayOfWeek);
            dayDate.setDate(firstDayOfWeek.getDate() + i);
            days.push({
                date: dayDate,
                day: dayDate.getDate(),
                month: dayDate.getMonth() + 1,
                year: dayDate.getFullYear(),
                today: DateUtils.sameDate(dayDate, DateTime.clock.date),
                shortName: root.locale.toString(dayDate, "ddd")
            });
        }
        return days;
    }

    property Component delegate: Text {
        required property var model
        text: model.shortName
    }

    Repeater {
        model: root.model
        delegate: root.delegate
    }
}

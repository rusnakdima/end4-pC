pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.ii.sidebarRight.calendar
import qs.modules.ii.sidebarRight.todo
import qs.modules.ii.sidebarRight.pomodoro
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    WindowGlass {
        anchors.fill: parent
        glassEnabled: (parent?.color.a ?? 0) > 0
        cardRadius: parent?.radius ?? 0
        tint: parent?.color ?? 'transparent'
    }
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    // The collapsible cards all wear the same hairline.
    border.width: 1
    border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.55)
    clip: true

    // Same spoiler card as the toggles, sliders and notifications sections:
    // a CollapsibleSectionHeader carries the collapse state, and the card
    // reports a real height in both states instead of the tab row drawing
    // its own arrow. Expanded keeps the old content height (the calendar
    // grid needs its six week rows) plus the header and its margins.
    readonly property bool collapsed: Persistent.states.sidebar.bottomGroup.collapsed
    readonly property int expandedHeight: 400
    implicitHeight: collapsed ? header.implicitHeight + 10 : expandedHeight
    property int selectedTab: Persistent.states.sidebar.bottomGroup.tab
    property int previousIndex: -1
    readonly property var currentTabData: root.tabs[root.selectedTab] ?? root.tabs[0]
    readonly property int remainingTasks: Todo.list.filter(task => !task.done).length
    property var tabs: [
        {
            "type": "calendar",
            "name": Translation.tr("Calendar"),
            "icon": "calendar_month",
            "widget": "calendar/CalendarWidget.qml"
        },
        {
            "type": "todo",
            "name": Translation.tr("To Do"),
            "icon": "done_outline",
            "widget": "todo/TodoWidget.qml"
        },
        {
            "type": "timer",
            "name": Translation.tr("Timer"),
            "icon": "schedule",
            "widget": "pomodoro/PomodoroWidget.qml"
        },
    ]

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }

    Keys.onPressed: event => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                root.selectedTab = Math.min(root.selectedTab + 1, root.tabs.length - 1);
            } else {
                root.selectedTab = Math.max(root.selectedTab - 1, 0);
            }
            event.accepted = true;
        }
    }

    CollapsibleSectionHeader {
        id: header
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 5
        }
        // The card hosts three tabs, so the header names the one on screen;
        // the readout keeps the date and the open task count the old
        // collapsed row used to show, in both states.
        headerIcon: root.currentTabData.icon
        title: root.currentTabData.name
        trailingText: Translation.tr("%1   •   %2 tasks").arg(DateTime.collapsedCalendarFormat).arg(root.remainingTasks)
        collapsed: root.collapsed
        onCollapseToggled: Persistent.states.sidebar.bottomGroup.collapsed = !Persistent.states.sidebar.bottomGroup.collapsed
    }

    RowLayout {
        id: bottomWidgetGroupRow

        visible: !root.collapsed
        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            topMargin: 5
            leftMargin: 5
            rightMargin: 5
            bottomMargin: 5
        }
        spacing: 20

        // Navigation rail
        Item {
            Layout.fillHeight: true
            Layout.fillWidth: false
            Layout.leftMargin: 5
            Layout.topMargin: 5
            implicitWidth: tabBar.implicitWidth
            // Navigation rail buttons
            NavigationRailTabArray {
                id: tabBar
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 5
                currentIndex: root.selectedTab
                expanded: false
                Repeater {
                    model: root.tabs
                    NavigationRailButton {
                        required property int index
                        required property var modelData
                        showToggledHighlight: false
                        toggled: root.selectedTab == index
                        buttonText: modelData.name
                        buttonIcon: modelData.icon
                        onPressed: {
                            root.selectedTab = index;
                            Persistent.states.sidebar.bottomGroup.tab = index;
                        }
                    }
                }
            }
        }

        // Content area
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Loader {
                id: tabStack
                anchors.fill: parent
                anchors.bottomMargin: -anchors.topMargin

                Component.onCompleted: {
                    tabStack.source = root.currentTabData.widget;
                }

                Connections {
                    target: root
                    function onSelectedTabChanged() {
                        // previousIndex is updated when the switch animation
                        // finishes, so it still holds the tab left behind.
                        if (root.selectedTab > root.previousIndex)
                            tabSwitchBehavior.animation.down = true;
                        else if (root.selectedTab < root.previousIndex)
                            tabSwitchBehavior.animation.down = false;
                        tabStack.source = root.currentTabData.widget;
                    }
                }

                Behavior on source {
                    id: tabSwitchBehavior
                    animation: TabSwitchAnim {
                        id: upAnim
                        down: true
                    }
                }
            }
        }
    }

    component TabSwitchAnim: SequentialAnimation {
        id: switchAnim
        property bool down: false
        ParallelAnimation {
            PropertyAnimation {
                target: tabStack
                properties: "opacity"
                to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
            PropertyAnimation {
                target: tabStack.anchors
                properties: "topMargin"
                to: 10 * (switchAnim.down ? -1 : 1)
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        PropertyAction {
            target: tabStack
            property: "source"
            value: root.tabs[root.selectedTab].widget
        } // The source change happens here
        ParallelAnimation {
            PropertyAnimation {
                target: tabStack.anchors
                properties: "topMargin"
                from: 10 * -(switchAnim.down ? -1 : 1)
                to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
            PropertyAnimation {
                target: tabStack
                properties: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
        }
        ScriptAction {
            script: {
                root.previousIndex = root.selectedTab;
            }
        }
    }
}

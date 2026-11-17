import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    property var order: []
    property bool editMode: false
    property real itemSpacing: 10
    property color accentColor: Appearance.colors.colPrimary
    property real cornerRadius: Appearance.rounding.normal

    property string fillKey: ""
    property real fillMinHeight: 60

    // Height of the sections as their delegates measured them, in slot
    // order. A scroll container binds contentHeight to this and gives the
    // column the same height, so the sections keep their own sizes and the
    // column overflows (and scrolls) instead of being squeezed or clipped.
    // It is computed from naturalHeight, never from effectiveHeight, so
    // binding the column's height to it cannot feed back into a fill slot.
    readonly property real contentHeight: {
        const keys = root.shownKeys()
        let total = Math.max(0, keys.length - 1) * root.itemSpacing
        for (let i = 0; i < keys.length; i++)
            total += root.naturalHeight(keys[i])
        return total
    }
    implicitHeight: contentHeight

    // Slot heights are live bindings on each section's reported
    // implicitHeight, so they change in one frame whenever a section
    // collapses, a section appears, or the fill section's share of the
    // leftover space shifts. Animating those steps keeps the column from
    // snapping. Armed a moment after construction instead of from the
    // start, so opening the sidebar still shows the sections at full size
    // rather than watching them grow in from zero.
    property bool animateSlotHeights: false

    signal reordered(var newOrder)
    property var componentForKey: function(key) { return null }
    property var isKeyActive: function(key) { return true }

    property var workingOrder: order.slice()
    property var stableKeys: []
    property string keySignature: ""
    property var heightMap: ({})
    property string draggingKey: ""
    readonly property bool animateMoves: root.draggingKey !== "" || settleTimer.running

    Timer {
        id: settleTimer
        interval: 320
    }

    Timer {
        id: slotAnimationArmTimer
        interval: 300
        onTriggered: root.animateSlotHeights = true
    }

    onOrderChanged: {
        if (root.draggingKey === "") root.workingOrder = root.order.slice()
        root.syncKeys()
    }
    Component.onCompleted: {
        root.syncKeys()
        slotAnimationArmTimer.start()
    }

    function syncKeys() {
        const signature = root.order.slice().sort().join("|")
        if (signature === root.keySignature) return
        root.keySignature = signature
        root.stableKeys = root.order.slice()
    }

    function naturalHeight(key) {
        return root.heightMap[key] ?? 0
    }

    function isShown(key) {
        if (!root.isKeyActive(key)) return false
        return key === root.fillKey || root.naturalHeight(key) > 0.5
    }

    function shownKeys() {
        return root.workingOrder.filter(key => root.isShown(key))
    }

    function effectiveHeight(key) {
        if (!root.isShown(key)) return 0
        if (key !== root.fillKey) return root.naturalHeight(key)
        const keys = root.shownKeys()
        let others = 0
        for (let i = 0; i < keys.length; i++) {
            if (keys[i] !== root.fillKey) others += root.naturalHeight(keys[i])
        }
        const remaining = root.height - others - Math.max(0, keys.length - 1) * root.itemSpacing
        return Math.max(root.fillMinHeight, remaining)
    }

    function yForKey(key) {
        let y = 0
        for (let i = 0; i < root.workingOrder.length; i++) {
            const k = root.workingOrder[i]
            if (k === key) break
            if (!root.isShown(k)) continue
            y += root.effectiveHeight(k) + root.itemSpacing
        }
        return y
    }

    function indexAtCenter(centerY) {
        const keys = root.shownKeys()
        let accY = 0
        for (let i = 0; i < keys.length; i++) {
            const h = root.effectiveHeight(keys[i])
            if (centerY <= accY + h / 2) return i
            accY += h + root.itemSpacing
        }
        return keys.length - 1
    }

    function moveKey(key, shownIndex) {
        const keys = root.shownKeys()
        const target = keys[shownIndex]
        if (target === undefined || target === key) return
        const next = root.workingOrder.slice()
        next.splice(next.indexOf(key), 1)
        next.splice(next.indexOf(target) + (shownIndex > keys.indexOf(key) ? 1 : 0), 0, key)
        root.workingOrder = next
    }

    Repeater {
        id: repeater
        model: root.stableKeys

        delegate: Item {
            id: slot
            required property string modelData

            readonly property bool dragging: root.draggingKey === slot.modelData
            property real dragY: 0
            readonly property real baseY: root.yForKey(slot.modelData)

            width: root.width
            height: root.effectiveHeight(slot.modelData)
            visible: height > 0
            y: slot.dragging ? slot.dragY : slot.baseY
            z: slot.dragging ? 100 : 0

            // One motion source for the whole column: a section's height
            // step (a spoiler collapsing, the media card appearing, the
            // fill section's share shifting) animates here, and because y
            // is recomputed from these heights every frame the sections
            // below slide with it instead of jumping.
            Behavior on height {
                enabled: root.animateSlotHeights && !slot.dragging
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            Behavior on y {
                enabled: root.animateMoves && !slot.dragging
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }

            function reportHeight() {
                const hm = Object.assign({}, root.heightMap)
                hm[slot.modelData] = loader.implicitHeight
                root.heightMap = hm
            }

            StyledRectangularShadow {
                visible: slot.dragging
                target: frame
            }

            Loader {
                id: loader
                anchors.fill: parent
                sourceComponent: root.componentForKey(slot.modelData)
                opacity: root.editMode && !slot.dragging ? 0.7 : 1

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                onImplicitHeightChanged: slot.reportHeight()
                Component.onCompleted: slot.reportHeight()
            }

            Rectangle {
                id: frame
                anchors.fill: parent
                radius: root.cornerRadius
                visible: root.editMode
                color: slot.dragging ? ColorUtils.transparentize(root.accentColor, 0.8) : "transparent"
                border.width: 2
                border.color: slot.dragging ? root.accentColor : ColorUtils.transparentize(root.accentColor, 0.55)

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                Rectangle {
                    anchors {
                        top: parent.top
                        right: parent.right
                        margins: 6
                    }
                    width: 30
                    height: 30
                    radius: height / 2
                    color: root.accentColor

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "drag_indicator"
                        iconSize: 20
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }

            MouseArea {
                id: dragArea
                anchors.fill: parent
                enabled: root.editMode
                visible: root.editMode
                cursorShape: slot.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real grabOffset: 0

                onPressed: mouse => {
                    dragArea.grabOffset = dragArea.mapToItem(root, mouse.x, mouse.y).y - slot.y
                    slot.dragY = slot.y
                    root.draggingKey = slot.modelData
                }

                onPositionChanged: mouse => {
                    if (!slot.dragging) return
                    const pointerY = dragArea.mapToItem(root, mouse.x, mouse.y).y
                    slot.dragY = Math.max(0, Math.min(root.height - slot.height, pointerY - dragArea.grabOffset))
                    root.moveKey(slot.modelData, root.indexAtCenter(slot.dragY + slot.height / 2))
                }

                onReleased: finish()
                onCanceled: finish()

                function finish() {
                    if (!slot.dragging) return
                    settleTimer.restart()
                    root.draggingKey = ""
                    root.reordered(root.workingOrder.slice())
                }
            }
        }
    }
}

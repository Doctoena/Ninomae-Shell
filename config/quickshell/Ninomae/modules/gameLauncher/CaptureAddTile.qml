import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

/**
 * The last tile of a Captures grid: a dashed outline the size of a capture, saying how to add one (the
 * screenshot key, the clip key). Not clickable: it only explains.
 */
Item {
    id: root
    property string icon
    property string text
    property string hint

    Canvas { // The dashed outline (QML's borders are solid)
        id: outline
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        readonly property color stroke: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.8)
        onStrokeChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d"), r = Appearance.rounding.normal, w = width - 1, h = height - 1;
            ctx.reset();
            ctx.setLineDash([6, 5]);
            ctx.lineWidth = 1.5;
            ctx.strokeStyle = stroke;
            ctx.beginPath();
            ctx.moveTo(r + 0.5, 0.5);
            ctx.arcTo(w, 0.5, w, h, r);
            ctx.arcTo(w, h, 0.5, h, r);
            ctx.arcTo(0.5, h, 0.5, 0.5, r);
            ctx.arcTo(0.5, 0.5, w, 0.5, r);
            ctx.closePath();
            ctx.stroke();
        }
    }
    Column {
        anchors.centerIn: parent
        width: parent.width - 24
        spacing: 6
        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.icon
            iconSize: 26
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.5)
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.text
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Medium
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.3)
        }
        StyledText {
            width: parent.width
            visible: root.hint !== ""
            horizontalAlignment: Text.AlignHCenter
            text: root.hint
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }
}

import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// A volume slider in the in-game overlay's Sound: the shell's slider at its thinnest, with a short handle, so a
// row stays as slim as Performance's
StyledSlider {
    Layout.fillWidth: true
    configuration: StyledSlider.Configuration.XS
    handleHeight: 18
    stopIndicatorValues: []
}

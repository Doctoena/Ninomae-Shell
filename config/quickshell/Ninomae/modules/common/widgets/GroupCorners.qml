import QtQuick
import qs.modules.common

/**
 * Where a settings row sits among the rows next to it, for its corners: rows one after another make a group,
 * rounded at its top and bottom and only slightly between (the first row's top, the last row's bottom).
 * A row is anything with `settingsRow: true` (the Config* rows, SettingRow, SettingsCard). Hidden items and
 * Repeaters don't count, so a group stays rounded when an option hides the rows under it.
 *   GroupCorners { id: corners; item: root }  … topLeftRadius: corners.top
 */
QtObject {
    id: root
    required property Item item
    property real outer: Appearance.rounding.normal
    property real inner: 5
    // Not by size: the layout sets sizes, and reading them here loops. A Repeater is an invisible helper
    function counts(x) { return x.visible && !String(x).startsWith("QQuickRepeater"); }
    // The visible neighbour before / after, or none: is it a row?
    function rowBeside(step) {
        const p = root.item?.parent;
        if (!p) return false;
        const siblings = p.children;
        let i = -1;
        for (let k = 0; k < siblings.length; k++) if (siblings[k] === root.item) { i = k; break; }
        for (let k = i + step; k >= 0 && k < siblings.length; k += step) {
            const x = siblings[k];
            if (!root.counts(x)) continue;
            return x.settingsRow === true;
        }
        return false;
    }
    readonly property real top: rowBeside(-1) ? inner : outer
    readonly property real bottom: rowBeside(1) ? inner : outer
}

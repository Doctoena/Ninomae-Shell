import qs.modules.common.widgets
import qs.services
import Quickshell.Services.UPower
QuickToggleButton {
    id: root
    toggled: PowerProfiles.profile !== PowerProfile.Balanced
    buttonIcon: switch(PowerProfiles.profile) {
        case PowerProfile.PowerSaver: return "energy_savings_leaf"
        case PowerProfile.Balanced: return "settings_slow_motion"
        case PowerProfile.Performance: return "local_fire_department"
    }
    onClicked: {
        if (PowerProfiles.hasPerformanceProfile) {
            switch(PowerProfiles.profile) {
                case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced
                break;
                case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance
                break;
                case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver
                break;
            }
        } else {
            PowerProfiles.profile = PowerProfiles.profile == PowerProfile.Balanced ? PowerProfile.PowerSaver : PowerProfile.Balanced
        }
    }
    StyledToolTip {
        text: Translation.tr("Click to cycle through power profiles")
    }
}

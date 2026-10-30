pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root
    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00 // People keep joking about setting volume to 5172% so...
    property string audioTheme: Config.options.sounds.theme
    signal sinkProtectionTriggered(string reason);
    PwObjectTracker {
        objects: [sink, source]
    }
    Connections { // Protection against sudden volume changes
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (!Config.options.audio.protection.enable) return;
            const newVolume = sink.audio.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100;
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;
            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered(Translation.tr("Illegal increment"));
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("Exceeded max allowed"));
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
    }
    // One scroll notch on a volume area: finer steps under 10%. Does nothing while there's
    // no output (e.g. Bluetooth earbuds switching to headset mode for a call)
    function stepVolume(up) {
        const a = root.sink?.audio;
        if (!a) return;
        const step = a.volume < 0.1 ? 0.01 : 0.02;
        a.volume = up ? Math.min(1, a.volume + step) : Math.max(0, a.volume - step);
    }
    // Plays /usr/share/sounds/<theme>/stereo/<name>.oga (or .ogg) with the lightest player installed:
    // pw-play or canberra-gtk-play, ffplay (all of FFmpeg) only as a last resort. The path is an argument
    function playSystemSound(soundName) {
        Quickshell.execDetached(["sh", "-c", `
            for f in "$1.oga" "$1.ogg"; do
                [ -f "$f" ] || continue
                if command -v pw-play >/dev/null; then exec pw-play "$f"
                elif command -v canberra-gtk-play >/dev/null; then exec canberra-gtk-play -f "$f"
                else exec ffplay -nodisp -autoexit -loglevel quiet "$f"; fi
            done`, "play-sound", `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}`]);
    }
}

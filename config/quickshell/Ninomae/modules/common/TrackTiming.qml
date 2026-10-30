import QtQuick
import Quickshell.Services.Mpris
import "trackTimingCache.js" as Cache

/**
 * A player's length and position, kept through the gaps where a browser stops sending them.
 * Zen/Firefox sends the real length and position on play, pause and seek, but whenever the page
 * updates its media info (YouTube does this when the window loses focus) it sends the metadata
 * again without the length and resets the position to 0, until the next play/pause/seek. Through
 * such a gap this keeps the last real length for the same track and counts the position on from
 * the last real one. Players that always send both just pass through. The memory is shared
 * (trackTimingCache.js), so a widget made later (the media drawer, rebuilt per opening) knows it too.
 */
Item {
    id: root
    visible: false
    property MprisPlayer player: null

    readonly property bool hasLength: length > 0
    property real length: 0
    property real position: 0

    // positionEvent: called for the player's own position report (a seek, or a real update), not a tick
    function update(positionEvent) {
        const p = root.player;
        if (!p) {
            root.length = 0;
            root.position = 0;
            return;
        }
        // The track, by URL where there is one: a browser's title flickers ("… - YouTube", "") meanwhile
        const key = `${p.dbusName}|${p.metadata["xesam:url"] || p.trackTitle || ""}`;
        const now = Date.now();
        let t = Cache.tracks[key];
        if (!t) {
            // Forget all but the most recent tracks, so it doesn't grow with every video watched
            const keys = Object.keys(Cache.tracks).sort((a, b) => Cache.tracks[b].anchorTime - Cache.tracks[a].anchorTime);
            for (const old of keys.slice(19)) delete Cache.tracks[old];
            t = Cache.tracks[key] = { length: 0, anchorPos: 0, anchorTime: now, playing: false };
        }
        if (p.lengthSupported && p.length > 0) {
            t.length = p.length;
            t.anchorPos = p.position;
        } else if (positionEvent && p.position > 1) {
            // A real position without the length: take it, so stalls (buffering, ads) don't leave the
            // count running ahead. A gap's reset to 0 is not one
            t.anchorPos = p.position;
        } else if (t.playing) {
            t.anchorPos += (now - t.anchorTime) / 1000;
        }
        t.anchorTime = now;
        t.playing = p.isPlaying;
        root.length = t.length;
        root.position = t.length > 0 ? Math.min(t.anchorPos, t.length) : 0;
    }

    onPlayerChanged: update()
    Component.onCompleted: { update(); if (!hasLength) recheck.start(); }
    // Just after a shell start the saved memory (MprisController) may not be read yet: look again once
    Timer { id: recheck; interval: 1500; onTriggered: root.update() }
    Connections {
        target: root.player
        function onPositionChanged() { root.update(true); }
        function onLengthChanged() { root.update(); }
        function onMetadataChanged() { root.update(); }
        function onIsPlayingChanged() { root.update(); }
    }
    Timer { // Keeps the position moving while playing (Quickshell works it out fresh on each read)
        running: root.player?.isPlaying ?? false
        interval: 1000
        repeat: true
        onTriggered: root.update()
    }
}

pragma Singleton
pragma ComponentBehavior: Bound
// From https://git.outfoxxed.me/outfoxxed/nixnew
// It does not have a license, but the author is okay with redistribution.
import qs.modules.common
import qs.modules.common.functions
import QtQml.Models
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../modules/common/trackTimingCache.js" as TimingCache
/**
 * A service that provides easy access to the active Mpris player.
 */
Singleton {
	id: root;
	property MprisPlayer trackedPlayer: null;
	property MprisPlayer activePlayer: trackedPlayer ?? Mpris.players.values[0] ?? null;
	Instantiator {
		model: Mpris.players;
		Connections {
			required property MprisPlayer modelData;
			target: modelData;
			Component.onCompleted: {
				if (root.trackedPlayer == null || modelData.isPlaying) {
					root.trackedPlayer = modelData;
				}
			}
			// A player closing: unless another one is tracked and playing, move to one that's playing,
			// else any that's left (never the one closing)
			Component.onDestruction: {
				const tracked = root.trackedPlayer;
				if (tracked && tracked !== modelData && tracked.isPlaying) return;
				const others = Mpris.players.values.filter(p => p !== modelData);
				root.trackedPlayer = others.find(p => p.isPlaying) ?? others[0] ?? null;
			}
			function onPlaybackStateChanged() {
				if (root.trackedPlayer !== modelData) root.trackedPlayer = modelData;
			}
			// Real timing from the player (play, pause, seek, a new track): worth keeping over a restart
			function onIsPlayingChanged() { timingSave.start(); }
			function onPositionChanged() { timingSave.start(); }
			function onLengthChanged() { timingSave.start(); }
		}
	}
	// TrackTiming's memory of each track's length and position (browsers drop them between play/pause/seek
	// events) is saved here, so after a shell restart the progress bars carry on instead of staying empty
	// until the next play/pause/seek
	JsonStore {
		id: timingStore
		filePath: `${FileUtils.trimFileProtocol(Directories.cache)}/media/track_timing.json`
		onLoaded: {
			for (const [key, saved] of Object.entries(value ?? {})) {
				const t = TimingCache.tracks[key];
				if (!t || !(t.length > 0)) TimingCache.tracks[key] = saved; // Only fills what this run doesn't know yet
			}
		}
	}
	Timer { // Saves a moment after the first event (start() doesn't push a running timer back), once every
		// TrackTiming has taken it in
		id: timingSave
		interval: 2000
		onTriggered: {
			const text = JSON.stringify(TimingCache.tracks);
			if (text !== JSON.stringify(timingStore.value)) timingStore.commit(JSON.parse(text));
		}
	}
	IpcHandler {
		target: "mpris"
		function pauseAll(): void {
			for (const player of Mpris.players.values) {
				if (player.canPause) player.pause();
			}
		}
		function playPause(): void { if (root.activePlayer?.canTogglePlaying) root.activePlayer.togglePlaying(); }
		function previous(): void { if (root.activePlayer?.canGoPrevious) root.activePlayer.previous(); }
		function next(): void { if (root.activePlayer?.canGoNext) root.activePlayer.next(); }
	}
}

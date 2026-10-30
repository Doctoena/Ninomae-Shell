#!/usr/bin/env bash
# Generate a YouTube Music (th-ch/youtube-music) CSS theme from the
# Material You colors already produced by generate_colors_material.py.
# Called by applycolor.sh after colors are generated.

XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$XDG_STATE_HOME/quickshell"
COLORS_JSON="$STATE_DIR/user/generated/colors.json"
OUTPUT_CSS="$STATE_DIR/user/generated/youtube-music-theme.css"

if [ ! -f "$COLORS_JSON" ]; then
  echo "[youtube-music-theme] colors.json not found, skipping."
  exit 0
fi

# Extract only the colors we need in a single jq invocation
eval "$(jq -r '{
  BG: .background,
  SURFACE: .surface,
  SURFACE_CONTAINER: .surface_container,
  SURFACE_CONTAINER_LOW: .surface_container_low,
  SURFACE_CONTAINER_HIGH: .surface_container_high,
  SURFACE_CONTAINER_HIGHEST: .surface_container_highest,
  ON_SURFACE: .on_surface,
  ON_SURFACE_VARIANT: .on_surface_variant,
  SURFACE_VARIANT: .surface_variant,
  OUTLINE: .outline,
  OUTLINE_VARIANT: .outline_variant,
  PRIMARY: .primary,
  PRIMARY_CONTAINER: .primary_container,
  ON_PRIMARY: .on_primary,
  ON_PRIMARY_CONTAINER: .on_primary_container,
  INVERSE_PRIMARY: .inverse_primary,
  INVERSE_SURFACE: .inverse_surface,
  INVERSE_ON_SURFACE: .inverse_on_surface,
  TERTIARY: .tertiary,
  SCRIM: .scrim
} | to_entries[] | "\(.key)=\u0027\(.value)\u0027"' "$COLORS_JSON")"

cat > "$OUTPUT_CSS" << CSSEOF
/* YouTube Music — Material You Theme
 * Generated: $(date -Iseconds)
 */

/* ── Smooth theme injection transition ─────────────────── */
html {
  transition: background-color 0.35s ease !important;
}
ytmusic-app,
ytmusic-app-layout,
ytmusic-player-bar,
#player-bar-background,
#nav-bar-background {
  transition: background-color 0.35s ease, color 0.25s ease !important;
}

/* ── CSS variable overrides ────────────────────────────── */
html,
ytmusic-app {
  /* Backgrounds */
  --yt-spec-base-background:            ${BG} !important;
  --yt-spec-general-background-a:       ${BG} !important;
  --yt-spec-general-background-b:       ${SURFACE_CONTAINER_LOW} !important;
  --yt-spec-general-background-c:       ${SURFACE_CONTAINER} !important;
  --yt-spec-menu-background:            ${SURFACE_CONTAINER_HIGH} !important;
  --yt-spec-raised-background:          ${SURFACE_CONTAINER_HIGH} !important;
  --yt-spec-snackbar-background:        ${INVERSE_SURFACE} !important;

  /* Text */
  --yt-spec-text-primary:               ${ON_SURFACE} !important;
  --yt-spec-text-secondary:             ${ON_SURFACE_VARIANT} !important;
  --yt-spec-text-disabled:              ${OUTLINE} !important;
  --yt-spec-text-primary-inverse:       ${SURFACE} !important;
  --yt-spec-black-1:                    ${ON_SURFACE} !important;
  --yt-spec-black-2:                    ${ON_SURFACE_VARIANT} !important;
  --yt-spec-black-3:                    ${OUTLINE} !important;
  --yt-spec-black-4:                    ${OUTLINE_VARIANT} !important;
  --yt-spec-black-pure:                 ${ON_SURFACE} !important;
  --yt-spec-black-1-alpha-16:           ${ON_SURFACE}29 !important;
  --yt-spec-black-1-alpha-30:           ${ON_SURFACE}4d !important;
  --yt-spec-black-pure-alpha-16:        ${ON_SURFACE}29 !important;
  --yt-spec-black-pure-alpha-30:        ${ON_SURFACE}4d !important;

  /* Buttons & links */
  --yt-spec-filled-button-text:         ${ON_PRIMARY} !important;
  --yt-spec-call-to-action:             ${PRIMARY} !important;
  --yt-spec-call-to-action-inverse:     ${INVERSE_PRIMARY} !important;
  --yt-endpoint-color:                  ${PRIMARY} !important;
  --yt-endpoint-visited-color:          ${PRIMARY} !important;
  --yt-endpoint-hover-color:            ${TERTIARY} !important;

  /* Overlays */
  --yt-spec-overlay-background-heavy:   ${SCRIM}cc !important;
  --yt-spec-overlay-background-medium:  ${SCRIM}99 !important;
  --yt-spec-overlay-background-secondary: ${SCRIM}66 !important;

  /* YouTube Music specific */
  --ytmusic-background:                 ${BG} !important;
  --ytmusic-color-black1:               ${ON_SURFACE} !important;
  --ytmusic-color-black2:               ${ON_SURFACE_VARIANT} !important;
  --ytmusic-color-black3:               ${OUTLINE} !important;
  --ytmusic-color-black4:               ${OUTLINE_VARIANT} !important;
  --ytmusic-color-blackpure:            ${ON_SURFACE} !important;
  --ytmusic-color-grey5:                ${SURFACE_VARIANT} !important;
  --ytmusic-text-secondary:             ${ON_SURFACE_VARIANT} !important;
  --ytmusic-general-background-a:       ${BG} !important;
  --ytmusic-general-background-b:       ${SURFACE_CONTAINER_LOW} !important;
  --ytmusic-general-background-c:       ${SURFACE_CONTAINER} !important;
  --ytmusic-menu-item-hover-background-color: ${SURFACE_CONTAINER_HIGHEST} !important;
  --ytmusic-setting-item-toggle-active: ${PRIMARY} !important;

  /* Controls */
  --iron-icon-fill-color:               ${ON_SURFACE_VARIANT} !important;
  --paper-slider-active-color:          ${PRIMARY} !important;
  --paper-slider-knob-color:            ${PRIMARY} !important;
  --paper-slider-container-color:       ${SURFACE_VARIANT} !important;
  --paper-toggle-button-checked-bar-color:    ${PRIMARY_CONTAINER} !important;
  --paper-toggle-button-checked-button-color: ${PRIMARY} !important;
  --ytmd-transparent-player-transparency-color: ${BG} !important;
}

/* ── Element overrides ─────────────────────────────────── */

/* Smooth hover transitions */
ytmusic-two-row-item-renderer,
ytmusic-responsive-list-item-renderer,
ytmusic-guide-entry-renderer,
ytmusic-chip-cloud-chip-renderer,
tp-yt-paper-button,
tp-yt-paper-icon-button,
tp-yt-paper-item,
ytmusic-menu-service-item-renderer {
  transition: background-color 0.2s ease, color 0.15s ease,
              transform 0.15s ease, box-shadow 0.2s ease !important;
}

/* Borderless elevation */
ytmusic-player-bar,
#player-bar-background,
#nav-bar-background,
#nav-bar-divider,
ytmusic-guide-renderer,
tp-yt-app-drawer,
ytmusic-player-queue-header {
  border: none !important;
}

/* Main content area */
body,
ytmusic-app-layout,
#layout,
#content.ytmusic-app {
  background: ${BG} !important;
}

/* Home page background overrides */
#background.immersive-background.ytmusic-browse-response {
  background: ${BG} !important;
  opacity: 1 !important;
}
ytmusic-browse-response .background-gradient {
  background: ${BG} !important;
}

/* Player bar */
ytmusic-player-bar,
#player-bar-background.ytmusic-app-layout {
  background: ${SURFACE_CONTAINER} !important;
}
ytmusic-player-bar .content-info-wrapper {
  position: static !important;
  transform: none !important;
  justify-content: flex-start !important;
}
ytmusic-player-bar .thumbnail-image-wrapper img {
  border-radius: 4px !important;
}
ytmusic-player-bar .time-info {
  color: ${ON_SURFACE_VARIANT} !important;
}
ytmusic-player-bar .menu {
  --iron-icon-fill-color: ${ON_SURFACE_VARIANT} !important;
}

/* Nav bar */
#nav-bar-background.ytmusic-app-layout {
  background: ${BG} !important;
}

/* Sidebar */
ytmusic-guide-renderer,
#guide-content,
tp-yt-app-drawer,
#guide-wrapper,
#mini-guide-background.ytmusic-app-layout {
  background-color: ${BG} !important;
  border: none !important;
}
ytmusic-guide-entry-renderer:hover {
  background-color: ${SURFACE_CONTAINER} !important;
}
ytmusic-guide-entry-renderer[active] {
  background-color: ${SURFACE_CONTAINER_HIGH} !important;
}

/* Cards & tiles */
ytmusic-two-row-item-renderer {
  border-radius: 8px !important;
  overflow: hidden !important;
  padding: 8px !important;
}
ytmusic-two-row-item-renderer:hover {
  background-color: ${SURFACE_CONTAINER} !important;
}

/* Rounded thumbnails */
ytmusic-two-row-item-renderer ytmusic-thumbnail-renderer,
ytmusic-two-row-item-renderer img,
ytmusic-responsive-list-item-renderer ytmusic-thumbnail-renderer,
ytmusic-responsive-list-item-renderer img {
  border-radius: 6px !important;
}

/* Song list rows */
ytmusic-responsive-list-item-renderer {
  border-radius: 6px !important;
}
ytmusic-responsive-list-item-renderer:hover {
  background-color: ${SURFACE_CONTAINER} !important;
}

/* Play button */
tp-yt-paper-button.ytmusic-play-button-renderer {
  background-color: ${PRIMARY} !important;
  color: ${ON_PRIMARY} !important;
}

/* Selected chips */
ytmusic-chip-cloud-chip-renderer[chip-style="STYLE_PRIMARY"],
ytmusic-chip-cloud-chip-renderer[selected] {
  background-color: ${ON_SURFACE} !important;
  color: ${BG} !important;
}

/* Search box */
ytmusic-search-box {
  border-radius: 24px !important;
  background-color: ${SURFACE_CONTAINER_HIGH} !important;
  border: none !important;
  overflow: hidden !important;
}
ytmusic-search-box:focus-within {
  background-color: ${SURFACE_CONTAINER_HIGHEST} !important;
  box-shadow: 0 0 0 2px ${PRIMARY} !important;
}

/* Menus & dropdowns */
tp-yt-paper-listbox,
ytmusic-menu-popup-renderer,
ytmusic-menu-renderer {
  border-radius: 8px !important;
  border: none !important;
  background-color: ${SURFACE_CONTAINER_HIGH} !important;
  box-shadow: 0 8px 24px ${SCRIM}66 !important;
  overflow: hidden !important;
}
tp-yt-paper-item:hover,
ytmusic-menu-service-item-renderer:hover {
  background-color: ${SURFACE_CONTAINER_HIGHEST} !important;
}

/* Queue & side panel */
ytmusic-player-queue-header,
ytmusic-player-queue,
#side-panel {
  background-color: ${SURFACE_CONTAINER_LOW} !important;
}
ytmusic-player-queue-item {
  border-radius: 6px !important;
  transition: background-color 0.2s ease !important;
}
ytmusic-player-queue-item:hover {
  background-color: ${SURFACE_CONTAINER} !important;
}
ytmusic-player-queue-item[selected] {
  background-color: ${SURFACE_CONTAINER_HIGH} !important;
}

/* Immersive headers */
ytmusic-immersive-header-renderer {
  background: linear-gradient(180deg, ${PRIMARY_CONTAINER}44 0%, transparent 100%) !important;
}
ytmusic-detail-header-renderer {
  background-color: transparent !important;
}

/* Dialogs */
ytmusic-dialog,
tp-yt-paper-dialog {
  border-radius: 12px !important;
  border: none !important;
  background-color: ${SURFACE_CONTAINER_HIGH} !important;
  box-shadow: 0 16px 48px ${SCRIM}99 !important;
}

/* Snackbar / toast */
ytmusic-notification-action-renderer,
tp-yt-paper-toast {
  background-color: ${INVERSE_SURFACE} !important;
  color: ${INVERSE_ON_SURFACE} !important;
  border-radius: 8px !important;
  border: none !important;
}

/* Scrollbar */
::-webkit-scrollbar       { width: 6px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: ${SURFACE_VARIANT}80; border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: ${SURFACE_VARIANT}; }

/* Text selection */
::selection {
  background-color: ${PRIMARY_CONTAINER};
  color: ${ON_PRIMARY_CONTAINER};
}
CSSEOF

echo "[youtube-music-theme] Generated: $OUTPUT_CSS"

# Point YouTube Music at it (its own settings file, written with this machine's path; not part of the
# dotfiles). Only if YouTube Music has been set up, and only when the entry is missing
YTM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/YouTube Music/config.json"
if [[ -f "$YTM_CONFIG" ]] && command -v jq >/dev/null; then
    if ! jq -e --arg css "$OUTPUT_CSS" '(.options.themes // []) | index($css)' "$YTM_CONFIG" >/dev/null 2>&1; then
        jq --arg css "$OUTPUT_CSS" '.options.themes = ((.options.themes // []) | map(select(test("youtube-music-theme\\.css$") | not)) + [$css])' \
            "$YTM_CONFIG" > "$YTM_CONFIG.tmp" && mv "$YTM_CONFIG.tmp" "$YTM_CONFIG"
    fi
fi

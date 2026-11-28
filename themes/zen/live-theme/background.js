// Ninomae live theme: puts the shell's wallpaper colours on Zen as they change, without a restart.
// themes/zen/apply-theme.sh writes colors.json next to this file whenever matugen regenerates the
// colours (it runs from a folder Zen's sandbox can see, through a proxy file in the profile). This
// reads it once a second and, when it changed, sets it as the browser theme.
//
// A theme can only set Firefox's own colour slots, so userChrome.css reads the palette back out of
// them (its :root[lwtheme] block). Each palette colour has one slot to itself, picked among ones
// with a similar meaning so what Zen draws from them directly matches too, and that neither
// userChrome.css nor Zen sets with !important (that would loop, or win over the theme). Keep the
// two in step.

const COLORS_URL = browser.runtime.getURL("colors.json");
let last = "";

function themeFor(c) {
  const dark = luminance(c.bg) < 0.4;
  return {
    colors: {
      // Read back by userChrome.css, one palette colour each
      frame: c.bg,                                  // --nino-bg
      tab_background_separator: c.surface,          // --nino-surface
      popup: c["surface-2"],                        // --nino-surface-2
      popup_highlight: c["surface-3"],              // --nino-surface-3
      toolbar_bottom_separator: c["surface-4"],     // --nino-surface-4
      popup_text: c.text,                           // --nino-text
      sidebar_border: c.subtext,                    // --nino-subtext
      toolbar_vertical_separator: c.outline,        // --nino-outline
      tab_line: c.primary,                          // --nino-primary
      toolbar_field_highlight_text: c["on-primary"], // --nino-on-primary
      // The rest, for anything userChrome.css doesn't restyle
      frame_inactive: c.bg,
      tab_background_text: c.text,
      tab_selected: c["surface-3"],
      tab_text: c.text,
      tab_loading: c.primary,
      toolbar: c.bg,
      toolbar_text: c.text,
      toolbar_field: c["surface-2"],
      toolbar_field_text: c.text,
      toolbar_field_focus: c["surface-2"],
      toolbar_field_text_focus: c.text,
      toolbar_field_border: "transparent",
      toolbar_field_border_focus: c.primary,
      toolbar_field_highlight: c.primary,
      toolbar_top_separator: "transparent",
      icons: c.text,
      icons_attention: c.primary,
      button_background_hover: c["surface-3"],
      button_background_active: c["surface-4"],
      popup_border: c.outline,
      popup_highlight_text: c.text,
      sidebar: c.bg,
      sidebar_text: c.text,
      ntp_background: c.bg,
      ntp_card_background: c["surface-2"],
      ntp_text: c.text,
    },
    properties: {
      color_scheme: dark ? "dark" : "light",
      content_color_scheme: dark ? "dark" : "light",
    },
  };
}

// Relative luminance of a #rrggbb colour, 0–1
function luminance(hex) {
  const [r, g, b] = [1, 3, 5].map(i => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

async function check() {
  let text;
  try {
    text = await (await fetch(COLORS_URL, { cache: "no-store" })).text();
  } catch (e) {
    return; // Not written yet
  }
  if (text === last) return;
  let colors;
  try {
    colors = JSON.parse(text);
  } catch (e) {
    return; // Caught mid-write: next time
  }
  last = text;
  browser.theme.update(themeFor(colors));
}

check();
setInterval(check, 1000);

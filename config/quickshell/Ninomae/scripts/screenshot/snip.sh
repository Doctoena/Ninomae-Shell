#!/usr/bin/env bash
# Finishes a region-selector capture (modules/regionSelector, run detached): crops the frozen frame and
# does the picked action with it. Always removes the frame.
#   snip.sh copy|edit <frame.png> <WxH+X+Y> <folder to save in, or "" to only copy>
#   snip.sh search    <frame.png> <WxH+X+Y> <search engine URL the image URL is appended to>
#   snip.sh ocr       <frame.png> <WxH+X+Y>
# copy: saves and copies, then a notification with a preview and Open / Edit / Delete
# edit: the same, opened in swappy instead of notifying (released with the right button)
set -uo pipefail
mode=$1 frame=$2 geometry=$3 arg=${4:-}
app=(-a Screenshot)

fail() { notify-send "${app[@]}" -u critical -i dialog-error "$1" "$2"; rm -f "$frame"; exit 1; }
# +repage drops the crop offset, which PNG would otherwise keep (and some apps honour)
crop() { magick "$frame" -crop "$geometry" +repage "$1" || fail "Screenshot failed" "Couldn't crop the screenshot"; }

case $mode in
search)
    crop "$frame"
    # The search engine needs a public URL, so the crop goes to a file host first
    url="$(curl -sf --max-time 30 -F "files[]=@$frame" https://uguu.se/upload | jq -r '.files[0].url // empty')"
    rm -f "$frame"
    [[ -n $url ]] || fail "Image search failed" "Couldn't upload the image"
    exec xdg-open "$arg$url" ;;
ocr)
    crop "$frame"
    # Every installed language (osd is page layout, not a language)
    langs="$(tesseract --list-langs 2>/dev/null | tail -n +2 | grep -vx osd | paste -sd+)"
    text="$(tesseract "$frame" stdout ${langs:+-l "$langs"} 2>/dev/null)"
    rm -f "$frame"
    if [[ -z ${text//[[:space:]]/} ]]; then
        notify-send "${app[@]}" -i document-scanner "No text found" "Nothing readable in that region"
    else
        printf '%s' "$text" | wl-copy
        notify-send "${app[@]}" -i document-scanner "Text copied" "${text:0:200}"
    fi
    exit ;;
copy|edit) ;;
*) fail "Screenshot failed" "Unknown action: $mode" ;;
esac

dir=$arg
if [[ -n $dir ]]; then
    dir="${dir/#\~/$HOME}"
    mkdir -p "$dir" || fail "Screenshot failed" "Couldn't create $dir"
    base="$dir/Screenshot_$(date +%Y-%m-%d_%H-%M-%S)"
    file="$base.png" n=1
    while [[ -e $file ]]; do file="${base}_$((n++)).png"; done # Two in the same second
else
    # Not keeping screenshots: the last one stays next to the frame so the preview and Edit still work
    file="$(dirname -- "$frame")/last-screenshot.png"
fi
crop "$file"
rm -f "$frame"
wl-copy --type image/png <"$file"

[[ $mode == edit ]] && exec swappy -f "$file" -o "$file"

args=("${app[@]}" -i applications-graphics -h "string:image-path:$file" --action=open=Open --action=edit=Edit)
if [[ -n $dir ]]; then
    body="Copied, and saved to ${dir/#$HOME/\~}"
    args+=(--action=delete=Delete
           # Keeps "Open" working after this script is gone (shell restart, timeout below)
           -h "string:omarchy-exec-argv:$(jq -cn --arg f "$file" '["xdg-open", $f]')")
else
    body="Copied to the clipboard"
fi
# Waits for a button; gives up after a while so unanswered notifications don't pile up processes
case "$(timeout 30m notify-send "${args[@]}" --wait "Screenshot taken" "$body")" in
    open) xdg-open "$file" ;;
    edit) swappy -f "$file" -o "$file" ;;
    delete) rm -f "$file" ;;
esac

#!/usr/bin/env bash
# Installs the "Ninomae" VS Code colour theme (generated from the wallpaper by matugen, see
# matugen/templates/vscode). Packages ninomae-theme/ as a VSIX so VS Code registers it, then
# points the installed copy at this folder so wallpaper changes update the theme in place.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
src="$here/ninomae-theme"
code_bin="$(command -v code || command -v codium || true)"
[[ -n "$code_bin" ]] || { echo "VS Code not installed; skipped"; exit 0; }
ext_dir="$HOME/.vscode/extensions"
[[ "$(basename "$code_bin")" == codium ]] && ext_dir="$HOME/.vscode-oss/extensions"
target="$ext_dir/ninomae.ninomae-theme-1.0.0"

if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$src")" ]]; then
    echo "Ninomae theme already installed"
else
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/pkg/extension"
    cp -a "$src/." "$tmp/pkg/extension/"
    printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>' \
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension=".json" ContentType="application/json"/><Default Extension=".vsixmanifest" ContentType="text/xml"/></Types>' \
        > "$tmp/pkg/[Content_Types].xml"
    cat > "$tmp/pkg/extension.vsixmanifest" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="ninomae-theme" Version="1.0.0" Publisher="ninomae"/>
    <DisplayName>Ninomae</DisplayName>
    <Description xml:space="preserve">Colour theme generated from the current wallpaper by matugen</Description>
    <Categories>Themes</Categories>
    <Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.70.0"/></Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
</PackageManifest>
XML
    (cd "$tmp/pkg" && python3 -c "
import zipfile, os
with zipfile.ZipFile('../ninomae-theme.vsix', 'w', zipfile.ZIP_DEFLATED) as z:
    for r, _, files in os.walk('.'):
        for f in files: z.write(os.path.join(r, f), os.path.relpath(os.path.join(r, f), '.'))")
    "$code_bin" --install-extension "$tmp/ninomae-theme.vsix" --force >/dev/null 2>&1
    rm -rf "$target" && ln -s "$src" "$target"
    echo "Installed Ninomae VS Code theme"
fi

# Select it (creates the settings file if VS Code has never been opened)
settings="$HOME/.config/Code/User/settings.json"
[[ "$(basename "$code_bin")" == codium ]] && settings="$HOME/.config/VSCodium/User/settings.json"
mkdir -p "$(dirname "$settings")"
if [[ ! -s "$settings" ]]; then
    printf '{\n  "workbench.colorTheme": "Ninomae"\n}\n' > "$settings"
elif grep -q '"workbench.colorTheme"' "$settings"; then
    sed -i -E 's/("workbench.colorTheme"\s*:\s*")[^"]*(")/\1Ninomae\2/' "$settings"
else
    sed -i '0,/{/s//{\n  "workbench.colorTheme": "Ninomae",/' "$settings"
fi

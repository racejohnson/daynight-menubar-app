#!/usr/bin/env bash
# Builds AppResources/Assets.car and AppResources/AppIcon.icns from the two drawings in this folder.
#
#   AppIcon.svg        the 1024 master, used from 64 px up (its light leak only from 256 up)
#   AppIcon-small.svg  the flat pixel drawing on a 32 grid, used at 16 and 32
#
# Renders with Playwright's Chromium when it can find it (PLAYWRIGHT=/path/to/playwright/index.mjs),
# otherwise with rsvg-convert. Set RENDERER=rsvg to force rsvg. Set ICONSET_OUT=dir to keep the iconset.
#
# Assets.car holds the master as a full-bleed Icon Composer icon, compiled with actool. macOS 26+
# draws a bare .icns inside a grey container; Info.plist names CFBundleIconName = AppIcon so the
# system uses Assets.car and gets the real icon shape. AppIcon.icns (CFBundleIconFile) is the fallback.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
OUT="$ROOT/AppResources/AppIcon.icns"
PLAYWRIGHT="${PLAYWRIGHT:-$HOME/Codex/velora-design-system/node_modules/playwright/index.mjs}"
RENDERER="${RENDERER:-auto}"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/daynight-icon.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"

# Size variants of the drawings.
# bleed.svg: the master without its shadow or tile clip, framed on the tile (for Icon Composer).
sed -e '/transform="translate(0,12)"/d' -e 's|<g clip-path="url(#tile)">|<g>|' \
    -e 's|viewBox="0 0 1024 1024"|viewBox="100 100 824 824"|' "$HERE/AppIcon.svg" > "$TMP/bleed.svg"
cp "$HERE/AppIcon.svg" "$TMP/full.svg"
sed '/<!-- leak:begin/,/<!-- leak:end -->/d' "$HERE/AppIcon.svg" > "$TMP/lite.svg"
grep -v 'data-max="16"' "$HERE/AppIcon-small.svg" > "$TMP/small32.svg"
grep -v 'data-min="32"' "$HERE/AppIcon-small.svg" > "$TMP/small16.svg"

# name  source  pixels
JOBS=(
  "icon_16x16.png       small16 16"
  "icon_16x16@2x.png    small32 32"
  "icon_32x32.png       small32 32"
  "icon_32x32@2x.png    lite    64"
  "icon_128x128.png     lite    128"
  "icon_128x128@2x.png  full    256"
  "icon_256x256.png     full    256"
  "icon_256x256@2x.png  full    512"
  "icon_512x512.png     full    512"
  "icon_512x512@2x.png  full    1024"
)
JOBS+=("../AppIcon.icon/Assets/art.png bleed 1024")
mkdir -p "$TMP/AppIcon.icon/Assets"

if [[ "$RENDERER" == auto ]]; then
  if command -v node >/dev/null && [[ -f "$PLAYWRIGHT" ]]; then RENDERER=chromium; else RENDERER=rsvg; fi
fi

if [[ "$RENDERER" == chromium ]]; then
  cat > "$TMP/render.mjs" <<JS
import { chromium } from '$PLAYWRIGHT';
import fs from 'fs';
const [dir, ...jobs] = process.argv.slice(2);
const browser = await chromium.launch();
for (const job of jobs) {
  const [name, src, px] = job.split(':'); const size = +px;
  const svg = fs.readFileSync(dir + '/' + src + '.svg', 'utf8')
    .replace(/<svg ([^>]*?)width="\d+" height="\d+"/, '<svg \$1width="' + size + '" height="' + size + '"');
  const page = await browser.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: 1 });
  await page.setContent('<html><body style="margin:0;background:transparent">' + svg + '</body></html>');
  await page.screenshot({ path: dir + '/AppIcon.iconset/' + name, omitBackground: true, clip: { x: 0, y: 0, width: size, height: size } });
  await page.close();
}
await browser.close();
JS
  args=()
  for j in "${JOBS[@]}"; do read -r name src px <<<"$j"; args+=("$name:$src:$px"); done
  node "$TMP/render.mjs" "$TMP" "${args[@]}"
else
  for j in "${JOBS[@]}"; do
    read -r name src px <<<"$j"
    rsvg-convert -w "$px" -h "$px" "$TMP/$src.svg" -o "$SET/$name"
  done
fi

iconutil -c icns "$SET" -o "$OUT"
cat > "$TMP/AppIcon.icon/icon.json" <<'JSON'
{
  "fill" : "none",
  "groups" : [ {
    "name" : "Art",
    "layers" : [ { "name" : "Art", "image-name" : "art.png", "glass" : false } ],
    "lighting" : "individual",
    "shadow" : { "kind" : "none", "opacity" : 0 },
    "specular" : false,
    "translucency" : { "enabled" : false, "value" : 0 }
  } ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}
JSON
mkdir -p "$TMP/car"
xcrun actool "$TMP/AppIcon.icon" --compile "$TMP/car" --platform macosx --minimum-deployment-target 26.0 \
  --app-icon AppIcon --output-partial-info-plist "$TMP/car/partial.plist" >/dev/null
cp "$TMP/car/Assets.car" "$ROOT/AppResources/Assets.car"
echo "Wrote $ROOT/AppResources/Assets.car"
if [[ -n "${ICONSET_OUT:-}" ]]; then rm -rf "$ICONSET_OUT"; mkdir -p "$ICONSET_OUT"; cp "$SET"/*.png "$ICONSET_OUT"/; fi
echo "Wrote $OUT ($RENDERER)"

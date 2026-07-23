#!/bin/bash
# Renders the icon and packages it into the formats macOS consumes:
#   DitGiff.iconset/          the ten raw PNGs
#   DitGiff.icns              for a bundle built outside Xcode
#   AppIcon.appiconset/       drop straight into Assets.xcassets
#   icon.svg                  vector master for the site, README and Icon Composer
set -euo pipefail
cd "$(dirname "$0")"

swift render-icon.swift .

iconutil --convert icns DitGiff.iconset --output DitGiff.icns

rm -rf AppIcon.appiconset
mkdir -p AppIcon.appiconset
cp DitGiff.iconset/*.png AppIcon.appiconset/

cat > AppIcon.appiconset/Contents.json <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png",      "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",      "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",    "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",    "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",    "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "built:"
echo "  DitGiff.icns             $(du -h DitGiff.icns | cut -f1)"
echo "  AppIcon.appiconset/      $(ls AppIcon.appiconset/*.png | wc -l | tr -d ' ') pngs + Contents.json"
echo "  icon.svg                 vector master"

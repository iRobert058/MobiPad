#!/bin/sh
# Renders thumbnail.html with headless Chrome:
#   thumbnail-2560x1440.png  portfolio (2x)
#   thumbnail-1280x720.jpg   YouTube (under 2 MB)
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

"$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=1280,720 --virtual-time-budget=3000 \
  --allow-file-access-from-files \
  --screenshot="$PWD/thumbnail-2560x1440.png" "file://$PWD/thumbnail.html" 2>/dev/null

sips -s format jpeg -s formatOptions 92 -z 720 1280 \
  thumbnail-2560x1440.png --out thumbnail-1280x720.jpg >/dev/null

sips -g pixelWidth -g pixelHeight thumbnail-2560x1440.png thumbnail-1280x720.jpg
ls -lh thumbnail-2560x1440.png thumbnail-1280x720.jpg

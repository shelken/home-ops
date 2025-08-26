#!/bin/sh
APPLE_ID=$(cat /config/secret/APPLE_ID)

APPLE_ID=$(cat /config/secret/APPLE_ID)

# ref: https://icloud-photos-downloader.github.io/icloud_photos_downloader/reference.html
# ref: https://github.com/icloud-photos-downloader/icloud_photos_downloader/blob/master/src/icloudpd/base.py

/app/icloudpd_ex icloudpd \
  --log-level=debug \
  --directory=/data \
  --cookie-directory=/config \
  --username="$APPLE_ID" \
  --domain=cn \
  --auto-delete \
  --no-progress-bar \
  --size=original \
  --keep-unicode-in-filenames=true \
  --folder-structure="{:%Y/%m/%d}" \
  --watch-with-interval=21600 \
  --mfa-provider=webui \
  --password-provider=webui
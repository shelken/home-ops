#!/bin/sh
APPLE_ID=$(cat /config/secret/APPLE_ID)
SMTP_HOST=$(cat /config/secret/SMTP_HOST)
SMTP_PORT=$(cat /config/secret/SMTP_PORT)
SMTP_USERNAME=$(cat /config/secret/SMTP_USERNAME)
SMTP_PASSWORD=$(cat /config/secret/SMTP_PASSWORD)
NOTIFICATION_EMAIL=$(cat /config/secret/NOTIFICATION_EMAIL)
NOTIFICATION_EMAIL_FROM=$(cat /config/secret/NOTIFICATION_EMAIL_FROM)

# ref: https://icloud-photos-downloader.github.io/icloud_photos_downloader/reference.html
# ref: https://github.com/icloud-photos-downloader/icloud_photos_downloader/blob/master/src/icloudpd/base.py

/app/icloudpd_ex icloudpd \
    --log-level=debug \
    --no-progress-bar \
    --watch-with-interval=21600 \
    --mfa-provider=webui \
    --password-provider=webui \
    --domain=cn \
    --username="$APPLE_ID" \
    --directory=/data \
    --cookie-directory=/config \
    --auto-delete \
    --size=original \
    --keep-unicode-in-filenames=true \
    --folder-structure="{:%Y/%m/%d}" \
    --smtp-host="$SMTP_HOST" \
    --smtp-port="$SMTP_PORT" \
    --smtp-username="$SMTP_USERNAME" \
    --smtp-password="$SMTP_PASSWORD" \
    --notification-email="$NOTIFICATION_EMAIL" \
    --notification-email-from="$NOTIFICATION_EMAIL_FROM"

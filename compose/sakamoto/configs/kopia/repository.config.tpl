{
  "storage": {
    "type": "s3",
    "config": {
      "bucket": "kopia",
      "prefix": "main/",
      "endpoint": "drive-s3.int.{{azure://shelken-homelab/compose-sakamoto/MAIN_DOMAIN}}",
      "accessKeyID": "azure://shelken-homelab/compose-sakamoto/OPENLIST_S3_ACCESS_KEY_ID",
      "secretAccessKey": "azure://shelken-homelab/compose-sakamoto/OPENLIST_S3_SECRET_ACCESS_KEY"
    }
  },
  "caching": {
    "cacheDirectory": "/app/cache",
    "maxCacheSize": 5242880000,
    "maxMetadataCacheSize": 5242880000,
    "maxListCacheDuration": 30
  }
}

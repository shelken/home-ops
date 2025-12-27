{
  "storage": {
    "type": "s3",
    "config": {
      "bucket": "kopia",
      "prefix": "main/",
      "endpoint": "openlist:5246",
      "accessKeyID": "azure://shelken-homelab/compose-vps/OPENLIST_S3_ACCESS_KEY_ID",
      "secretAccessKey": "azure://shelken-homelab/compose-vps/OPENLIST_S3_SECRET_ACCESS_KEY",
      "doNotUseTLS": true
    }
  },
  "caching": {
    "cacheDirectory": "/app/cache",
    "maxCacheSize": 5242880000,
    "maxMetadataCacheSize": 5242880000,
    "maxListCacheDuration": 30
  }
}

## 无法正常连接smb并启动容器

```log
Error: failed to create subPath directory for volumeMount "backup-media" of container "app"
```

解决: sakamoto 上重启smbd `sudo launchctl stop com.apple.smbd && sudo launchctl start com.apple.smbd`

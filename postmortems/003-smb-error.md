## 无法正常连接smb并启动容器

```log
Error: failed to create subPath directory for volumeMount "backup-media" of container "app"
```

解决: 在 SMB 服务所在主机上重启 `smbd`：`sudo launchctl stop com.apple.smbd && sudo launchctl start com.apple.smbd`

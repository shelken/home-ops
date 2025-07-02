# README

volsync 将集群数据同步到内网部署的 minio

定时：每小时一次

## 使用

- flux模板替换功能（postBuild.substituteFrom），替换变量
- 在flux kustomization中引入
- longhorn 创建相关 storageclass [path](../../../infra/common/longhorn-system/longhorn/storageclass/snapshot.yaml)
- 该模板目前默认pvc为2GB可 `VOLSYNC_CAPACITY` 调整大小
- 为什么pvc中的VOLSYNC_STORAGECLASS是longhorn，source和dst中是longhorn-snapshot，因为需要自定义参数，例如减少副本为1

## 必须参数变量

- APP：对应的服务名

## 其他关键变量

- VOLSYNC_CAPACITY：PVC容量大小 默认 2
- VOLSYNC_PUID：默认1000
- VOLSYNC_PGID：默认1000
- 
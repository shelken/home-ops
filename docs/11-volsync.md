# volsync

依赖 snapshot-controller; 先安装；（创建`longhorn-snapclass`的卷快照类）
依赖 longhorn（服务数据存储）; 先安装

## 旧数据迁移

[文档](https://volsync.readthedocs.io)

```shell
source ~/.restic.env
export RESTIC_REPOSITORY=s3:minio.ooooo.space/k8s-restic/repos/[APP_NAME]
cd /data/docker/[APP_NAME]
restic init
restic backup .
```

## 添加新应用

在component引入volsync component,并补全postBuild所需变量

ks.yaml
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app memos
  namespace: &namespace staging
spec:
  components:
    - ../../../components/volsync
  postBuild:
    substitute:
      APP: *app
      VOLSYNC_CAPACITY: 2Gi
      # 如果values的配置用户和组不是1000,需要修改对应的用户
      # VOLSYNC_PUID: 1000
      # VOLSYNC_PGID: 1000
```

```yaml
spec:
  values:
    persistence:
      data:
        existingClaim: memos
        globalMounts:
          # 对应你的app挂载的路径，如果没有默认挂载在[当前项的名字]即`/data`
          - path: /var/opt/memos
            readOnly: false
```


## 查看数据

```yaml
 ---
 kind: Pod
 apiVersion: v1
 metadata:
   name: busybox
   namespace: staging
 spec:
   containers:
     - name: busybox
       image: busybox
       command: ["/bin/sh", "-c"]
       args: ["sleep 999999"]
       volumeMounts:
         - name: data
           mountPath: "/mnt"
   volumes:
     - name: data
       persistentVolumeClaim:
         claimName: [APP_NAME]
```

```shell
kubectl -n staging apply -f pod.yaml
kubectl -n staging exec -it pod/busybox -- ls -al /mnt

```
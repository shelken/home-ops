# volsync

依赖 snapshot-controller; 先安装
依赖 longhorn（服务数据存储）; 先安装

## 旧数据迁移

就是说我们要从docker服务的数据迁移到我们集群中，要用到这个工具cli

[cli 文档](https://volsync.readthedocs.io/en/stable/usage/cli/index.html)
[Migrating data into Kubernetes](https://volsync.readthedocs.io/en/stable/usage/cli/migration.html)

```shell
# mac无法安装，使用go安装
brew install krew
kubectl krew install volsync

#
go install github.com/backube/volsync/kubectl-volsync@main
kubectl-volsync -h

```
### 复制数据
首先要定义pvc，要持久化的数据应该要有定义相应的pvc，例如【uptime-kuma】，将应用名和pvc命名一致，在集群中应该先创建了

创建一个关联关系

```shell
kubectl-volsync migration create --pvcname staging/uptime-kuma -r uptime-kuma
kubectl-volsync migration rsync -r uptime-kuma --source /tmp/uptime-kuma-data/

```

### 查看数据

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
         claimName: uptime-kuma
```

```shell
kubectl -n staging apply -f pod.yaml
kubectl -n staging exec -it pod/busybox -- ls -al /mnt

```
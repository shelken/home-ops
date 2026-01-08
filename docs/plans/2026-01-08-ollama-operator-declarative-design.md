# Ollama Operator 声明式配置设计

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**目标：** 将手动 `ollama pull` 工作流替换为基于 `ollama-operator` 的声明式 GitOps 配置，使模型部署完全通过 Git 管控。

**背景：** vLLM 要求 GPU 计算能力 >= 7.0，但 homelab-1 的 GTX 1050 Ti 为 SM 6.1，不满足要求。因此继续使用 Ollama，但通过 operator 实现声明式管理。

---

## 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                      FluxCD GitOps                          │
├─────────────────────────────────────────────────────────────┤
│  k8s/apps/common/ollama/operator/   ← Operator 部署         │
│  k8s/apps/common/ollama/models/     ← Model CR 定义         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│         ollama-operator (namespace: ollama-operator-system) │
│  - 监听 Model CR                                            │
│  - 自动为每个 Model 创建 Deployment + Service + PVC          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Model CR: qwen3-4b (namespace: default)        │
│  - image: qwen3:4b                                          │
│  - runtimeClassName: nvidia                                 │
│  - storageClassName: openebs-hostpath                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 目录结构

```
k8s/apps/common/ollama/
├── ks.yaml                       ← 统一入口，管理所有子组件
│
├── app/                          ← 现有：原 Ollama 实例（暂时禁用）
│   ├── kustomization.yaml
│   ├── helmrelease.yaml
│   └── pvc.yaml
│
├── web/                          ← 现有：Open WebUI（暂时禁用）
│   ├── kustomization.yaml
│   ├── helmrelease.yaml
│   └── externalsecret.yaml
│
├── operator/                     ← 新增：ollama-operator
│   ├── kustomization.yaml
│   ├── gitrepository.yaml
│   └── ks-operator.yaml
│
└── models/                       ← 新增：Model CR 资源
    ├── kustomization.yaml
    └── qwen3-4b.yaml
```

---

## Task 1: 更新 OpenEBS 配置

**文件：**
- 修改：`k8s/infra/common/openebs-system/openebs/app/helmrelease.yaml`

**变更内容：**

```yaml
localpv-provisioner:
  localpv:
    basePath: &hostPath /var/mnt/local-hostpath   # 从 /mnt/data/openebs/local 改为此路径
  hostpathClass:
    enabled: true
    name: openebs-hostpath
    isDefaultClass: false
    basePath: *hostPath
    # 删除 nodeAffinityLabels - 不再限制到特定节点
```

**说明：** OpenEBS helper pod 会自动创建目录，无需手动 mkdir。

---

## Task 2: 创建 Operator 目录

**文件：**
- 创建：`k8s/apps/common/ollama/operator/kustomization.yaml`
- 创建：`k8s/apps/common/ollama/operator/gitrepository.yaml`
- 创建：`k8s/apps/common/ollama/operator/ks-operator.yaml`

### `kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - gitrepository.yaml
  - ks-operator.yaml
```

### `gitrepository.yaml`

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: ollama-operator
spec:
  interval: 1h
  url: https://github.com/nekomeowww/ollama-operator
  ref:
    tag: v0.10.1
```

### `ks-operator.yaml`

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ollama-operator-install
spec:
  interval: 1h
  sourceRef:
    kind: GitRepository
    name: ollama-operator
  path: ./dist
  prune: true
  wait: true
```

---

## Task 3: 创建 Models 目录

**文件：**
- 创建：`k8s/apps/common/ollama/models/kustomization.yaml`
- 创建：`k8s/apps/common/ollama/models/qwen3-4b.yaml`

### `kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - qwen3-4b.yaml
```

### `qwen3-4b.yaml`

```yaml
---
apiVersion: ollama.ayaka.io/v1
kind: Model
metadata:
  name: qwen3-4b
spec:
  # 模型镜像
  image: qwen3:4b

  # GPU 调度
  runtimeClassName: nvidia

  # 存储配置
  storageClassName: openebs-hostpath

  # 资源限制 - 严格控制，强制使用 GPU 显存
  resources:
    limits:
      nvidia.com/gpu: "1"
      memory: 2Gi
    requests:
      cpu: 100m
      memory: 512Mi

  # Ollama 运行时参数
  env:
    - name: OLLAMA_KEEP_ALIVE
      value: "24h"
    - name: OLLAMA_LOAD_TIMEOUT
      value: "600"
    - name: OLLAMA_NUM_CTX
      value: "4096"
    - name: OLLAMA_HOST
      value: "0.0.0.0"
    - name: OLLAMA_ORIGINS
      value: "*"
```

---

## Task 4: 更新 ks.yaml

**文件：**
- 修改：`k8s/apps/common/ollama/ks.yaml`

**变更内容：**
- 新增 `ollama-operator` Kustomization
- 新增 `ollama-models` Kustomization（依赖 operator）
- 注释掉现有的 `ollama` 和 `ollama-web` Kustomizations

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app ollama-operator
  namespace: &namespace default
spec:
  targetNamespace: *namespace
  dependsOn:
    - name: openebs
      namespace: openebs-system
  path: ./k8s/apps/common/ollama/operator
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
  interval: 1h
  retryInterval: 2m
  timeout: 5m
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app ollama-models
  namespace: &namespace default
spec:
  targetNamespace: *namespace
  dependsOn:
    - name: ollama-operator
  path: ./k8s/apps/common/ollama/models
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
  interval: 1h
  retryInterval: 2m
  timeout: 10m
# --- 以下暂时禁用 ---
# ---
# apiVersion: kustomize.toolkit.fluxcd.io/v1
# kind: Kustomization
# metadata:
#   name: &app ollama
#   ... (原有 app 配置)
# ---
# apiVersion: kustomize.toolkit.fluxcd.io/v1
# kind: Kustomization
# metadata:
#   name: &app ollama-web
#   ... (原有 web 配置)
```

---

## Task 5: 推送模型文件

**重要：** 此任务需要特别注意目录路径问题。

**工具：** 使用 `ollama-plus`，位于 `/Users/shelken/code/MyRepo/ai/ollama-export/ollama-plus.go`

**当前限制：**
- `ollama-plus` 对 Linux 主机预设远程路径为 `/data/ai/ollama/models`
- ollama-operator 创建 PVC 并在 pod 内挂载到 `/root/.ollama`
- 可能需要增强 `ollama-plus` 以支持自定义远程路径，或者直接推送到节点上的 PVC 挂载路径

**实施方案：**
1. 先部署 operator 和 Model CR（让它创建 PVC）
2. 确认 homelab-1 上的实际模型存储路径：
   - OpenEBS 会创建：`/var/mnt/local-hostpath/<pvc-id>/`
   - Pod 内部：挂载为 `/root/.ollama`
3. 增强 `ollama-plus` 或手动 rsync 模型文件到正确路径
4. 重启 Model pod 以加载预置的模型文件

**命令模板（路径确认后）：**
```bash
# 方案 A：增强后的 ollama-plus
go run /Users/shelken/code/MyRepo/ai/ollama-export/ollama-plus.go push qwen3:4b --host homelab-1 --remote-path <实际路径>

# 方案 B：直接 rsync 到 PVC 路径
rsync -avz ~/.ollama/models/ homelab-1:/var/mnt/local-hostpath/<pvc-id>/
```

---

## Task 6: 提交并验证

**验证命令：**

```bash
# 检查 operator pods
KUBECONFIG=./kubeconfig kubectl get pods -n ollama-operator-system

# 检查 Model CR 状态
KUBECONFIG=./kubeconfig kubectl get models

# 检查 Model Pod
KUBECONFIG=./kubeconfig kubectl get pods -l ollama.ayaka.io/model=qwen3-4b

# 检查 GPU 使用情况
ssh 192.168.6.110 "nvidia-smi"

# 测试 API
KUBECONFIG=./kubeconfig kubectl port-forward svc/ollama-model-qwen3-4b 11434:11434
curl http://localhost:11434/api/generate -d '{"model":"qwen3:4b","prompt":"你好"}'
```

---

## 回滚方案

如遇问题：
1. 在 ks.yaml 中取消注释原有的 `ollama` 和 `ollama-web`
2. 注释掉 `ollama-operator` 和 `ollama-models`
3. 如需要，恢复 OpenEBS 的 nodeAffinityLabels
4. 提交并让 Flux 恢复原状态

---

## 参考资料

- [ollama-operator GitHub](https://github.com/nekomeowww/ollama-operator)
- [OpenEBS Dynamic LocalPV Provisioner](https://github.com/openebs/dynamic-localpv-provisioner)
- [Qwen3 Models](https://github.com/QwenLM/Qwen3)

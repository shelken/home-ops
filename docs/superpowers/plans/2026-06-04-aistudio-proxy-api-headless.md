# AIstudioProxyAPI Headless Image and Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a headless AIstudioProxyAPI image from the upstream release, then add a ClusterIP-only GitOps service that reads auth state from a PVC.

**Architecture:** The image is built in the containers repo from `CJackHwang/AIstudioProxyAPI` tag `v4.1.2_py`. The home-ops repo deploys one app-template HelmRelease with a Volsync-backed PVC mounted at `/app/auth_profiles`. No Route, Ingress, LoadBalancer, login container, or CPA config is part of this plan.

**Tech Stack:** Docker Buildx Bake, Python slim, Poetry in builder stage, Camoufox, Playwright, Flux Kustomization, bjw-s app-template, Volsync.

---

## File Map

Containers repo:

- Create: `apps/aistudio-proxy-api/Dockerfile` — builds the runtime image from upstream tag `v4.1.2_py`.
- Create: `apps/aistudio-proxy-api/docker-bake.hcl` — exposes the app name, source repo, upstream version, and multi-arch targets to the shared CI.

home-ops repo:

- Create: `k8s/apps/common/aistudio-proxy-api/ks.yaml` — Flux Kustomization with Volsync PVC settings.
- Create: `k8s/apps/common/aistudio-proxy-api/app/kustomization.yaml` — app folder kustomize entry.
- Create: `k8s/apps/common/aistudio-proxy-api/app/helmrelease.yaml` — ClusterIP-only AIstudioProxyAPI workload.
- Modify: `k8s/apps/common/kustomization.yaml` — add `aistudio-proxy-api/ks.yaml` to the common app list.
- Modify: `.renovate/packageRules.json5` — add source URL metadata for the custom image.

Privacy note for public files: use the real GHCR owner in committed Kubernetes YAML only if that owner is already public project metadata. Do not write local machine paths, private hostnames, node names, IPs, or personal filesystem paths.

---

### Task 1: Add the containers image definition

**Files:**
- Create: `apps/aistudio-proxy-api/Dockerfile`
- Create: `apps/aistudio-proxy-api/docker-bake.hcl`

- [ ] **Step 1: Create the app folder**

Run in the containers repo:

```bash
mkdir -p apps/aistudio-proxy-api
```

Expected: directory exists.

- [ ] **Step 2: Write `docker-bake.hcl`**

Create `apps/aistudio-proxy-api/docker-bake.hcl`:

```hcl
target "docker-metadata-action" {}

variable "APP" {
  default = "aistudio-proxy-api"
}

variable "VERSION" {
  // renovate: datasource=github-releases depName=CJackHwang/AIstudioProxyAPI
  default = "v4.1.2_py"
}

variable "SOURCE" {
  default = "https://github.com/CJackHwang/AIstudioProxyAPI"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION     = "${VERSION}"
    SOURCE_REPO = "${SOURCE}.git"
  }
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output = ["type=docker"]
  tags = ["${APP}:${VERSION}"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64",
    "linux/arm64"
  ]
}
```

- [ ] **Step 3: Write `Dockerfile`**

Create `apps/aistudio-proxy-api/Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1.7
FROM python:3.10-slim-bookworm AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG VERSION=v4.1.2_py
ARG SOURCE_REPO=https://github.com/CJackHwang/AIstudioProxyAPI.git
ARG POETRY_VERSION=1.8.3

ENV POETRY_HOME=/opt/poetry \
    POETRY_NO_INTERACTION=1 \
    POETRY_VIRTUALENVS_CREATE=false \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/poetry/bin:/opt/venv/bin:$PATH

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/*

RUN python -m venv "$VIRTUAL_ENV" \
    && curl -sSL https://install.python-poetry.org | python3 - --version "$POETRY_VERSION"

WORKDIR /src
RUN git clone --depth=1 --branch "$VERSION" "$SOURCE_REPO" .

RUN poetry install --only main --no-root --no-ansi

FROM python:3.10-slim-bookworm

ARG DEBIAN_FRONTEND=noninteractive

ENV VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HOME=/home/app \
    PLAYWRIGHT_BROWSERS_PATH=/home/app/.cache/ms-playwright \
    SERVER_PORT=2048 \
    DEFAULT_FASTAPI_PORT=2048 \
    DEFAULT_CAMOUFOX_PORT=9222 \
    STREAM_PORT=3120 \
    SERVER_LOG_LEVEL=INFO \
    DEBUG_LOGS_ENABLED=false \
    TRACE_LOGS_ENABLED=false \
    AUTO_SAVE_AUTH=false \
    AUTO_AUTH_ROTATION_ON_STARTUP=false \
    COOKIE_REFRESH_ENABLED=true \
    COOKIE_REFRESH_ON_REQUEST_ENABLED=true \
    COOKIE_REFRESH_ON_SHUTDOWN=true \
    INTERNAL_CAMOUFOX_PROXY="" \
    GUI_DEFAULT_HELPER_ENDPOINT=""

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      fonts-liberation \
      libasound2 \
      libatk-bridge2.0-0 \
      libatk1.0-0 \
      libcups2 \
      libdbus-1-3 \
      libdrm2 \
      libgbm1 \
      libgtk-3-0 \
      libnspr4 \
      libnss3 \
      libpango-1.0-0 \
      libpangocairo-1.0-0 \
      libu2f-udev \
      libx11-6 \
      libx11-xcb1 \
      libxcb1 \
      libxcomposite1 \
      libxdamage1 \
      libxext6 \
      libxfixes3 \
      libxrandr2 \
      libxrender1 \
      libxtst6 \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1000 app \
    && useradd --uid 1000 --gid app --home-dir /home/app --create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /src /app

RUN mkdir -p \
      /app/auth_profiles/active \
      /app/auth_profiles/saved \
      /app/auth_profiles/emergency \
      /app/logs \
      /app/.cache \
      /home/app/.cache/ms-playwright \
      /home/app/.mozilla \
    && camoufox fetch \
    && python -m playwright install firefox \
    && python scripts/update_browserforge_data.py \
    && chown -R app:app /app /home/app /opt/venv

USER 1000:1000

EXPOSE 2048 3120

CMD ["python", "launch_camoufox.py", "--headless", "--server-port", "2048", "--stream-port", "3120", "--helper", ""]
```

- [ ] **Step 4: Print bake config**

Run in the containers repo:

```bash
cd apps/aistudio-proxy-api
docker buildx bake image-all --print
```

Expected: JSON includes `linux/amd64`, `linux/arm64`, `VERSION=v4.1.2_py`, and source `CJackHwang/AIstudioProxyAPI.git`.

- [ ] **Step 5: Commit containers image files**

Run in the containers repo:

```bash
git add apps/aistudio-proxy-api/Dockerfile apps/aistudio-proxy-api/docker-bake.hcl
git commit -F - <<'EOF'
feat: add aistudio proxy image

- 新增 AIstudioProxyAPI headless 镜像构建配置
- 使用 upstream v4.1.2_py 与 Poetry lock 安装依赖
- 保持 runtime 不包含 Poetry 与登录 UI 组件
EOF
```

Expected: commit succeeds.

---

### Task 2: Validate the image locally

**Files:**
- No file changes expected.

- [ ] **Step 1: Build the local image**

Run in the containers repo:

```bash
cd apps/aistudio-proxy-api
docker buildx bake image-local
```

Expected: image `aistudio-proxy-api:v4.1.2_py` exists locally.

- [ ] **Step 2: Verify Python imports**

Run:

```bash
docker run --rm --entrypoint python aistudio-proxy-api:v4.1.2_py - <<'PY'
import camoufox
import fastapi
import playwright
import uvicorn
print("imports ok")
PY
```

Expected output contains:

```text
imports ok
```

- [ ] **Step 3: Verify runtime user**

Run:

```bash
docker run --rm --entrypoint sh aistudio-proxy-api:v4.1.2_py -c 'id -u && id -g'
```

Expected output:

```text
1000
1000
```

- [ ] **Step 4: Verify auth directories**

Run:

```bash
docker run --rm --entrypoint sh aistudio-proxy-api:v4.1.2_py -c 'test -d /app/auth_profiles/active && test -d /app/auth_profiles/saved && test -d /app/auth_profiles/emergency && echo auth dirs ok'
```

Expected output:

```text
auth dirs ok
```

- [ ] **Step 5: Run with local auth if available**

Use a local directory that contains `auth_profiles/active/*.json`. Keep private paths out of any commit message or public doc.

```bash
docker run --rm \
  -p 2048:2048 \
  -p 3120:3120 \
  -v "<LOCAL_AUTH_PROFILES_DIR>:/app/auth_profiles" \
  aistudio-proxy-api:v4.1.2_py
```

Expected after startup:

```bash
curl -fsS http://127.0.0.1:2048/health
curl -fsS http://127.0.0.1:2048/v1/models
```

The first command returns health JSON. The second command returns a models response or an auth-related error that clearly points to the profile state.

---

### Task 3: Add home-ops Kubernetes manifests

**Files:**
- Create: `k8s/apps/common/aistudio-proxy-api/ks.yaml`
- Create: `k8s/apps/common/aistudio-proxy-api/app/kustomization.yaml`
- Create: `k8s/apps/common/aistudio-proxy-api/app/helmrelease.yaml`

- [ ] **Step 1: Create folders**

Run in home-ops:

```bash
mkdir -p k8s/apps/common/aistudio-proxy-api/app
```

Expected: directory exists.

- [ ] **Step 2: Write `ks.yaml`**

Create `k8s/apps/common/aistudio-proxy-api/ks.yaml`:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app aistudio-proxy-api
  namespace: &namespace default
spec:
  targetNamespace: *namespace
  components:
    - ../../../../components/volsync
  dependsOn:
    - name: cilium
      namespace: kube-system
    - name: volsync
      namespace: volsync-system
  postBuild:
    substitute:
      APP: *app
      VOLSYNC_CAPACITY: 1Gi
      VOLSYNC_CACHE_CAPACITY: 1Gi
  interval: 1h
  path: ./k8s/apps/common/aistudio-proxy-api/app
  prune: true
  retryInterval: 2m
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  timeout: 5m
  wait: false
```

- [ ] **Step 3: Write app kustomization**

Create `k8s/apps/common/aistudio-proxy-api/app/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
```

- [ ] **Step 4: Write HelmRelease**

Create `k8s/apps/common/aistudio-proxy-api/app/helmrelease.yaml`.

Before commit, replace `<GHCR_OWNER>` with the image owner that publishes the containers repo image, and replace `<IMAGE_DIGEST>` with the digest from GHCR.

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app aistudio-proxy-api
spec:
  interval: 1h
  chartRef:
    kind: OCIRepository
    name: app-template
    namespace: flux-system
  install:
    remediation:
      retries: -1
  upgrade:
    cleanupOnFail: true
    remediation:
      retries: 3
  values:
    controllers:
      aistudio-proxy-api:
        annotations:
          reloader.stakater.com/auto: "true"
        containers:
          app:
            image:
              repository: ghcr.io/<GHCR_OWNER>/aistudio-proxy-api
              tag: v4.1.2_py@sha256:<IMAGE_DIGEST>
            command: ["python"]
            args:
              - launch_camoufox.py
              - --headless
              - --server-port
              - "2048"
              - --stream-port
              - "3120"
              - --helper
              - ""
            env:
              TZ: ${TIMEZONE}
              SERVER_PORT: &port 2048
              DEFAULT_FASTAPI_PORT: 2048
              DEFAULT_CAMOUFOX_PORT: 9222
              STREAM_PORT: &stream-port 3120
              SERVER_LOG_LEVEL: INFO
              DEBUG_LOGS_ENABLED: "false"
              TRACE_LOGS_ENABLED: "false"
              AUTO_SAVE_AUTH: "false"
              AUTO_AUTH_ROTATION_ON_STARTUP: "false"
              COOKIE_REFRESH_ENABLED: "true"
              COOKIE_REFRESH_ON_REQUEST_ENABLED: "true"
              COOKIE_REFRESH_ON_SHUTDOWN: "true"
              INTERNAL_CAMOUFOX_PROXY: ""
              GUI_DEFAULT_HELPER_ENDPOINT: ""
            probes:
              readiness:
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /health
                    port: *port
                  initialDelaySeconds: 30
                  periodSeconds: 10
                  timeoutSeconds: 3
                  failureThreshold: 12
              liveness:
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /health
                    port: *port
                  initialDelaySeconds: 120
                  periodSeconds: 30
                  timeoutSeconds: 5
                  failureThreshold: 6
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: false
              capabilities:
                drop:
                  - ALL
            resources:
              requests:
                cpu: 100m
                memory: 512Mi
              limits:
                memory: 2Gi
    defaultPodOptions:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
    service:
      app:
        controller: *app
        type: ClusterIP
        ports:
          http:
            port: *port
          stream:
            port: *stream-port
    persistence:
      auth-profiles:
        existingClaim: *app
        globalMounts:
          - path: /app/auth_profiles
      logs:
        type: emptyDir
        globalMounts:
          - path: /app/logs
      app-cache:
        type: emptyDir
        globalMounts:
          - path: /app/.cache
      home-cache:
        type: emptyDir
        globalMounts:
          - path: /home/app/.cache
      tmp:
        type: emptyDir
        globalMounts:
          - path: /tmp
      shm:
        type: emptyDir
        medium: Memory
        sizeLimit: 512Mi
        globalMounts:
          - path: /dev/shm
```

- [ ] **Step 5: Confirm no route block exists**

Run:

```bash
rg -n "route:|Ingress|LoadBalancer|HTTPRoute" k8s/apps/common/aistudio-proxy-api
```

Expected output is empty, except the command exits with code 1 because no match was found.

---

### Task 4: Enable the app in common kustomization and Renovate metadata

**Files:**
- Modify: `k8s/apps/common/kustomization.yaml`
- Modify: `.renovate/packageRules.json5`

- [ ] **Step 1: Add the app to `k8s/apps/common/kustomization.yaml`**

Add this line near `cli-proxy-api/ks.yaml`:

```yaml
  - aistudio-proxy-api/ks.yaml
```

The top of the resources list should become:

```yaml
resources:
  # - affine/ks.yaml
  - aistudio-proxy-api/ks.yaml
  - caches/ks.yaml
  - cli-proxy-api/ks.yaml
```

- [ ] **Step 2: Add Renovate source metadata**

In `.renovate/packageRules.json5`, add this rule after the CLIProxyAPI source rule:

```json5
    {
      description: "AIstudioProxyAPI sourceUrl 补充",
      matchPackageNames: ["/aistudio-proxy-api/"],
      sourceUrl: "https://github.com/CJackHwang/AIstudioProxyAPI"
    },
```

- [ ] **Step 3: Validate common kustomization**

Run in home-ops:

```bash
kustomize build k8s/apps/common/aistudio-proxy-api/app >/tmp/aistudio-proxy-api-app.yaml
kustomize build k8s/apps/common >/tmp/home-ops-common.yaml
```

Expected: both commands exit with code 0.

- [ ] **Step 4: Confirm service exposure**

Run:

```bash
rg -n "LoadBalancer|HTTPRoute|hostnames:|parentRefs:|envoy-" /tmp/aistudio-proxy-api-app.yaml /tmp/home-ops-common.yaml
```

Expected: no lines for `aistudio-proxy-api`.

---

### Task 5: Publish image and pin digest in home-ops

**Files:**
- Modify: `k8s/apps/common/aistudio-proxy-api/app/helmrelease.yaml`

- [ ] **Step 1: Push containers commit and start the release workflow**

Run in the containers repo:

```bash
git status --short
git push
```

Expected: working tree clean before push, then GitHub Actions starts for `apps/aistudio-proxy-api`.

If manual workflow dispatch is preferred:

```bash
gh workflow run Release --field app=aistudio-proxy-api --field release=true
```

Expected: workflow starts.

- [ ] **Step 2: Watch the workflow**

Run in the containers repo:

```bash
gh run list --workflow Release --limit 5
gh run watch <RUN_ID>
```

Expected: build matrix for `linux/amd64` and `linux/arm64` passes, then manifest and attestation steps pass.

- [ ] **Step 3: Get image digest**

Run after GHCR has the image:

```bash
docker buildx imagetools inspect ghcr.io/<GHCR_OWNER>/aistudio-proxy-api:v4.1.2_py
```

Expected: output includes a top-level digest like:

```text
Digest: sha256:<MANIFEST_DIGEST>
```

- [ ] **Step 4: Pin the digest**

Edit `k8s/apps/common/aistudio-proxy-api/app/helmrelease.yaml` so the tag is fully pinned:

```yaml
              tag: v4.1.2_py@sha256:<MANIFEST_DIGEST>
```

The committed file must not contain `<MANIFEST_DIGEST>`.

- [ ] **Step 5: Validate the pinned manifest**

Run:

```bash
rg -n "<GHCR_OWNER>|<IMAGE_DIGEST>|<MANIFEST_DIGEST>" k8s/apps/common/aistudio-proxy-api .renovate/packageRules.json5
kustomize build k8s/apps/common/aistudio-proxy-api/app >/tmp/aistudio-proxy-api-app.yaml
```

Expected: `rg` finds no matches, and kustomize exits with code 0.

---

### Task 6: Commit home-ops manifests

**Files:**
- All home-ops files from Tasks 3-5.

- [ ] **Step 1: Review diff**

Run in home-ops:

```bash
git diff -- k8s/apps/common/aistudio-proxy-api k8s/apps/common/kustomization.yaml .renovate/packageRules.json5
```

Expected diff:

- Adds one app folder.
- Adds one ClusterIP service.
- Adds one Volsync-backed PVC usage.
- Adds one common kustomization entry.
- Adds one Renovate source metadata rule.
- Does not add Route, Ingress, or LoadBalancer.

- [ ] **Step 2: Run privacy and leak scans**

Run:

```bash
python3 - <<'PY'
import re
from pathlib import Path
paths = [
    Path("k8s/apps/common/aistudio-proxy-api"),
    Path("docs/superpowers/plans/2026-06-04-aistudio-proxy-api-headless.md"),
]
patterns = [
    re.compile("/" + "Users"),
    re.compile("192" + r"\.168\."),
    re.compile(r"10\."),
    re.compile(r"172\.(1[6-9]|2[0-9]|3[0-1])\."),
    re.compile(r"\." + "lan"),
    re.compile("MAIN" + "_DOMAIN"),
    re.compile("PRIVATE|TOKEN|COOKIE"),
    re.compile(r"auth_profiles/.+\.json"),
]
findings = []
for root in paths:
    files = root.rglob("*") if root.is_dir() else [root]
    for file in files:
        if not file.is_file():
            continue
        text = file.read_text(errors="ignore")
        for pattern in patterns:
            if pattern.search(text):
                findings.append(str(file))
                break
if findings:
    raise SystemExit("private data candidates: " + ", ".join(sorted(set(findings))))
print("privacy scan ok")
PY
```

Expected output:

```text
privacy scan ok
```

- [ ] **Step 3: Run pre-commit checks**

Run:

```bash
pre-commit run --files \
  k8s/apps/common/aistudio-proxy-api/ks.yaml \
  k8s/apps/common/aistudio-proxy-api/app/kustomization.yaml \
  k8s/apps/common/aistudio-proxy-api/app/helmrelease.yaml \
  k8s/apps/common/kustomization.yaml \
  .renovate/packageRules.json5
```

Expected: all checks pass.

- [ ] **Step 4: Commit home-ops files**

Run:

```bash
git add \
  k8s/apps/common/aistudio-proxy-api \
  k8s/apps/common/kustomization.yaml \
  .renovate/packageRules.json5

git commit -F - <<'EOF'
feat: add aistudio proxy api service

- 新增 AIstudioProxyAPI headless 常驻服务
- 使用 ClusterIP 暴露主 API 与 stream proxy
- 使用 Volsync PVC 保存 auth_profiles
- 不创建 Route、Ingress、LoadBalancer 或 login 服务
EOF
```

Expected: commit succeeds.

---

### Task 7: Cluster verification after Flux sync

**Files:**
- No file changes expected.

- [ ] **Step 1: Push home-ops commit**

Run:

```bash
git status --short
git push
```

Expected: working tree clean before push.

- [ ] **Step 2: Let Flux reconcile from Git**

Do not use `kubectl apply`. If a Flux sync is needed, use the repo's existing Flux workflow or `flux reconcile ks` according to the project convention.

Example command:

```bash
flux reconcile ks apps-common --with-source
```

Expected: Flux reads Git state and applies the committed manifests.

- [ ] **Step 3: Check created resources**

Run:

```bash
kubectl -n default get kustomization aistudio-proxy-api
kubectl -n default get helmrelease aistudio-proxy-api
kubectl -n default get svc aistudio-proxy-api -o jsonpath='{.spec.type}{"\n"}'
```

Expected:

```text
ClusterIP
```

- [ ] **Step 4: Confirm no external exposure**

Run:

```bash
kubectl -n default get httproute,ingress,svc -o wide | rg "aistudio-proxy-api|LoadBalancer"
```

Expected: only the `aistudio-proxy-api` Service appears, and its type is `ClusterIP`.

- [ ] **Step 5: Verify health from inside the cluster**

Use an existing temporary test Pod pattern from the repo, or start an ephemeral curl Pod if that is acceptable for operational checks:

```bash
kubectl -n default run aistudio-proxy-api-smoke \
  --rm -i --restart=Never \
  --image=curlimages/curl:8.17.0 \
  --command -- sh -c 'curl -fsS http://aistudio-proxy-api:2048/health'
```

Expected: health response returns HTTP 2xx.

- [ ] **Step 6: Verify models endpoint**

Run:

```bash
kubectl -n default run aistudio-proxy-api-models \
  --rm -i --restart=Never \
  --image=curlimages/curl:8.17.0 \
  --command -- sh -c 'curl -fsS http://aistudio-proxy-api:2048/v1/models'
```

Expected: returns a models response if auth is valid. If auth is absent or expired, the response and Pod logs must clearly identify auth state as the issue.

---

## Self-Review

Spec coverage:

- Headless-only image: Task 1 and Task 2.
- Upstream release/tag source: Task 1 uses `v4.1.2_py` from `CJackHwang/AIstudioProxyAPI`.
- No login image or Web UI: Task 1 image excludes those components; Task 3 manifests do not create them.
- ClusterIP-only service: Task 3 and Task 4 validation.
- PVC auth state and Volsync: Task 3 `ks.yaml` and `persistence.auth-profiles`.
- No CPA config changes: file map contains no CPA files.
- Digest pinning: Task 5.
- Validation: Tasks 2, 4, 6, 7.

Text scan targets before commit:

```bash
python3 - <<'PY'
from pathlib import Path
text = Path("docs/superpowers/plans/2026-06-04-aistudio-proxy-api-headless.md").read_text()
needles = [
    "/" + "Users",
    "192" + ".168",
    "." + "lan",
    "implement " + "later",
    "similar " + "to",
]
found = [needle for needle in needles if needle in text]
if found:
    raise SystemExit(f"unexpected text: {found}")
print("plan text check ok")
PY
```

Expected output:

```text
plan text check ok
```

References:

- Kubernetes Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Docker multi-stage builds: https://docs.docker.com/get-started/docker-concepts/building-images/multi-stage-builds/
- Poetry docs: https://python-poetry.org/docs/
- uv Docker integration: https://docs.astral.sh/uv/guides/integration/docker/
- Camoufox upstream: https://github.com/daijro/camoufox
- AIstudioProxyAPI upstream release used here: https://github.com/CJackHwang/AIstudioProxyAPI/releases/tag/v4.1.2_py

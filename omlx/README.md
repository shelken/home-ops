# oMLX 外部 STT 服务 (stt-voice)

> 状态:方案定稿,未实施。集群实际状态以 Flux 为准,宿主实际状态以 nix-config 为准,本文是目标规格

## 目标

在 yuuko(M1 / 16GB / 永不睡眠)上以 oMLX 提供 Qwen3-ASR 推理,通过服务注册以 `stt-voice` Service 接入集群;支持 envoy-internal 域名访问与 task 快速启停

## 目标规格(未来 agent 以本节为准)

| 项 | 值 |
|---|---|
| Service | `stt-voice`,namespace `default`(仓库规范:普通应用一律 default),selector-less |
| EndpointSlice | `stt-voice`,addressType IPv4,地址 `${YUUKO_IP}`(cluster-settings 注入,跟随 ROUTER_IP 先例) |
| 端口 | 8900(Service 与 oMLX 监听一致,背景资料的 8000 作废) |
| 集群内地址 | `http://stt-voice.default.svc.cluster.local:8900`,同 ns 可写 `http://stt-voice:8900` |
| gateway | HTTPRoute `stt-voice.${MAIN_DOMAIN}` → envoy-internal(仅 LAN 解析,语音数据不出内网) |
| 探活 | gatus `tcp://yuuko.lan:8900`(resources/outside 新增,yuuko.lan 已在路由器注册) |
| API key | yuuko 侧首次手工写入 settings.json(步骤见下),集群侧不分发 |
| API | `POST /v1/audio/transcriptions`、`GET /v1/models`(OpenAI 兼容) |
| 机制依据 | docs/adr/0002(为何不用 ExternalName / FQDN endpoint / 直接 LAN 引用) |

oMLX 上游约束:非 loopback 绑定必须有 main API key,否则拒绝启动;keyless 需手改 settings.json 的 `auth.allow_unauthenticated_inference`,本方案不采用

## 计划文件树(未实施)

```
omlx/
└── README.md                    # 本文(宿主侧安装/配置归 nix-config,不落 home-ops)
.taskfile/omlx.yaml              # 仅启停与观察任务
k8s/apps/common/ai/stt-voice/
├── ks.yaml                      # targetNamespace: default
└── app/
    ├── kustomization.yaml
    ├── service.yaml             # selector-less
    ├── endpointslice.yaml       # 资源内不写 metadata.namespace(targetNamespace 注入)
    └── httproute.yaml           # parentRef envoy-internal/network
```

配套改动:`k8s/components/common/cluster-settings.yaml` 新增 `YUUKO_IP`;gatus `resources/outside/` 新增检查文件;`Taskfile.yaml` includes 追加 omlx

## task 规划(omlx:*)

- `start` / `stop`:`omlx start|stop`,即 brew services(launchd keep_alive,崩溃与开机自启)
- `status` / `logs` / `ps`:状态观察入口
- 不含安装/配置/升级:宿主侧归 nix-config(`shelken.homelab.omlx`),升级节奏由 nix 侧 pin 控制

## 宿主侧管理(nix-config)

home-ops 不负责 oMLX 的安装与配置;安装、pin、升级节奏由 nix-config 服务级 option 管理(设计定稿,未实施):

```nix
# modules/darwin/apps/homelab/omlx.nix(新建)
options.shelken.homelab.omlx.enable = mkBoolOpt false;
config = mkIf cfg.enable {
  homebrew.taps  = [ { name = "jundot/omlx"; trusted = true; } ];
  homebrew.brews = [ "jundot/omlx/omlx" ];
  # nix-darwin 无 pin 选项,activation 收尾补 pin,幂等且在 brew bundle 安装之后执行
  system.activationScripts.postUserActivation.text = ''
    [ -x /opt/homebrew/bin/brew ] && /opt/homebrew/bin/brew pin jundot/omlx/omlx || true
  '';
};
# hosts/yuuko/default.nix: shelken.homelab.omlx.enable = true;
```

与现有 nix-config 的交互事实:

- `homebrew.onActivation.cleanup = "uninstall"`:未进 Brewfile 的 formula 会在 switch 时被卸载,omlx 声明进 brews 后不受影响
- nix activation 默认不带 `--upgrade`,switch 不会升级已装 formula;pin 防的是手动 `brew upgrade` 类操作
- sakamoto 保持 `omlx.enable` 缺省 false,与 lms 互不抢统一内存

settings.json 手动一次性(yuuko):

```bash
# 1. 生成 key(仅 yuuko 本地使用)
openssl rand -hex 32
# 2. 写 ~/.omlx/settings.json: host 0.0.0.0 / port 8900 / api key,模型目录默认 ~/.omlx/models
# 3. 启动,此后 launchd 常驻
omlx start
```

## 宿主侧事实(2026-09-26 验证)

- brew formula 无 bottle,纯源码编译(依赖 rust 构建与多个 `--no-binary` 原生包),upgrade = 全量重新下载 + 重新编译
- 模型文件在 `~/.omlx/models`,与 brew 前缀无关,upgrade 不触碰、不重新下载
- 仓库无任何 brew 自动化(Renovate 不管理 omlx,taskfile 仅 lms 有 install-if-missing 的 cask),升级只发生在显式执行时
- yuuko 硬件:Mac mini M1 / 16GB / `pmset sleep 0`;oMLX 此前未安装(无 CLI、无 App、无 `~/.omlx`)

证据来源:上游 formula `Formula/omlx.rb`(github.com/jundot/omlx)、上游 README Install/CLI 章节;仓库验证命令 `grep -ri brew ansible scripts .taskfile .renovate lima`

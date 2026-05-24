# Gatus sidecar picks wrong endpoint from multi-match HTTPRoute

**日期**: 2026-05-24
**影响**: Gatus 误报 `openlist-app` 异常，服务本身实际正常。
**发现人**: 用户反馈 Gatus 访问 `openlist-app` 失败，但手工访问正常。

## 问题

`openlist-app` 的 `HTTPRoute` 有多个 `matches`。没有显式指定 endpoint 时，`gatus-sidecar` 自动选中了错误路径做健康检查。

Gatus 实际检查的是：

```text
https://<DRIVE_DOMAIN>/d/picbed
```

而稳定健康接口是：

```text
https://<DRIVE_DOMAIN>/api/public/settings
```

## 现象

sidecar 日志：

```text
time=<TIME> level=INFO msg="updated endpoint" resource=httproutes namespace=default name=openlist-app url=https://<DRIVE_DOMAIN>/d/picbed
```

最小复现：

```bash
curl -IL https://<DRIVE_DOMAIN>/api/public/settings
# HTTP/2 200

curl -IL https://<DRIVE_DOMAIN>/d/picbed
# HTTP/2 500
```

返回体：

```text
500 Internal Server Error
failed link: not a file
```

## 根因

1. 这个 `HTTPRoute` 的多个 `matches` 用途不同，不是每个路径都适合做健康检查。
2. 没有加 `gatus.home-operations.com/endpoint` 注释，导致 sidecar 自动发现取错了路径。
3. 排查时先看了 sidecar 的启动期 watch 错误，没有先确认 Gatus 实际探测的 URL。

## 修复

给这个 `HTTPRoute` 显式加 `gatus.home-operations.com/endpoint` 注释，固定健康检查地址：

```yaml
metadata:
  annotations:
    gatus.home-operations.com/endpoint: |
      url: https://<DRIVE_DOMAIN>/api/public/settings
      conditions:
        - "[STATUS] == 200"
```

## 预防

1. 只要 `HTTPRoute` 有多个 `matches`，默认显式写 `gatus.home-operations.com/endpoint`。
2. 遇到“手工访问正常，但 Gatus 失败”，先确认 Gatus 实际探测的 URL。
3. 健康检查优先用稳定接口，不要直接用文件路径或公开内容路径。

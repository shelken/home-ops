#!/usr/bin/env bash
# 用渲染产物自带的 CRD 判断：仓库与 chart 输出的资源是否还在使用已弃用或已停止提供的 API 版本。
# 依据的是即将部署的 chart 版本，不依赖集群连接。
# 覆盖范围：只含渲染产物里带 CRD 的 chart；Flux 自身与 Cilium 的 CRD 由其他途径安装，不在其中。
# 用法：check-deprecated-apis.sh <flate build 的输出文件，须包含 CRD>
# 已弃用：只报告；已停止提供（served: false）：报告并以非零退出。
# yq 与 jq 的表达式里的 $ 是它们自己的变量，不是 shell 变量
# shellcheck disable=SC2016
set -euo pipefail

rendered=${1:?用法: check-deprecated-apis.sh <rendered.yaml>}

# 只展开已弃用或停止提供的版本，键为 "group/version Kind"
states=$(yq -N -o=json '
  select(.kind == "CustomResourceDefinition")
  | .spec.group as $g | .spec.names.kind as $k
  | .spec.versions[]
  | select(.served == false or .deprecated == true)
  | {"id": ($g + "/" + .name + " " + $k), "served": .served}
' "$rendered" |
  jq -s 'map({(.id): (if .served then "已弃用" else "已停止提供" end)}) | add // {}')

findings=$(yq -N -o=json '
  select(.kind != "CustomResourceDefinition")
  | {"id": (.apiVersion + " " + .kind), "name": ((.metadata.namespace // "-") + "/" + .metadata.name)}
' "$rendered" |
  jq -rs --argjson states "$states" '
    map(select($states[.id] != null) | . + {state: $states[.id]})
    | group_by(.id)[]
    | "[\(.[0].state)] \(.[0].id)：\(map(.name) | sort | .[0:5] | join(", "))\(if length > 5 then " 等 \(length) 个" else "" end)"
  ')

[[ -z $findings ]] && exit 0
echo "$findings"
grep -q '^\[已停止提供\]' <<<"$findings" && exit 1
exit 0

#!/usr/bin/env bash
# 把 flate 渲染失败的 stderr 日志整理成 Markdown 摘要，写入 GitHub Actions 作业摘要。
# 按失败对象区分「依赖获取阻塞」与「配置渲染失败」，避免上游故障被误读成配置写错。
# 用法：summarize-flate-failures.sh <flate build 的 stderr 日志文件>
set -euo pipefail

log=${1:?用法: summarize-flate-failures.sh <flate.stderr.log>}

# 失败对象行是「✗ 后跟两个空格」；汇总行（✗ 后一个空格）与 blocks 行都不匹配
objects=$(grep -E '^[[:space:]]*✗  ' "$log" || true)

echo "## Flate 渲染未完成"
echo

if [[ -z $objects ]]; then
  echo "未识别到失败对象，见 Render manifests 步骤日志。"
  exit 0
fi

tagged=$(
  awk -F '  +' '
    function trunc(s) { return length(s) > 300 ? substr(s, 1, 300) "…" : s }
    {
      err = $5
      for (i = 6; i <= NF; i++) err = err "  " $i
      source = ($3 ~ /^(OCIRepository|GitRepository|HelmRepository|HelmChart|Bucket)$/)
      # flate 把网络类错误统一显示为固定文本，来源写错还是上游不可用只能看报错是不是对象缺失
      missing = source && (err ~ /not found/)
      dep = !missing && (source || (err ~ /https?:\/\//))
      printf "%s\t%s\t%s\t%s\n", (dep ? "dep" : "cfg"), $3, $4, trunc(err)
    }
  ' <<<"$objects"
)

read -r ndep ncfg < <(
  awk -F '\t' '{ n[$1]++ } END { printf "%d %d\n", n["dep"] + 0, n["cfg"] + 0 }' <<<"$tagged"
)

if ((ndep > 0)); then
  echo "### 依赖获取阻塞（$ndep）"
  echo
  echo "上游来源不可用或缓存缺失，与本次配置是否正确无关；上游恢复后重跑即可。若本次新增或修改了该来源，先核对 url、tag、digest。"
  echo
  awk -F '\t' '$1 == "dep" { printf "- `%s %s`：%s\n", $2, $3, $4 }' <<<"$tagged"
  echo
fi

if ((ncfg > 0)); then
  echo "### 配置渲染失败（$ncfg）"
  echo
  awk -F '\t' '$1 == "cfg" { printf "- `%s %s`：%s\n", $2, $3, $4 }' <<<"$tagged"
  echo
fi

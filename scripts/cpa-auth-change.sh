set -euo pipefail
NS=default
LABEL=app.kubernetes.io/name=cli-proxy-api
CONTAINER=app
REMOTE=/.cli-proxy-api
LOCAL=./tmp

rm -rf "$LOCAL"
mkdir -p "$LOCAL"
POD=$(kubectl get pod -l $LABEL -o jsonpath='{.items[0].metadata.name}' | head -1)
kubectl -n "$NS" cp "$POD:$REMOTE" "$LOCAL" -c "$CONTAINER"

find "$LOCAL" -type f -name 'codex-*.json' -print0 |
    while IFS= read -r -d '' f; do
        tmp="$(mktemp)"
        jq '.websockets = true' "$f" >"$tmp" && mv "$tmp" "$f"
        # jq '.websockets = false' "$f" >"$tmp" && mv "$tmp" "$f"
        # jq 'del(.websocket)' "$f" >"$tmp" && mv "$tmp" "$f"
    done

kubectl -n "$NS" cp "$LOCAL/." "$POD:$REMOTE" -c "$CONTAINER"
rm -rf "$LOCAL"

# Checkpoints

## 1. Containers image app scaffold
- [ ] Add `apps/cli-proxy-api/docker-bake.hcl`
- [ ] Add `apps/cli-proxy-api/Dockerfile`
- [ ] Verify local bake metadata resolves expected app/version/platforms

## 2. GHCR image publish
- [ ] Commit and push `containers` changes
- [ ] Trigger `Release` workflow for `cli-proxy-api` with `release=true`
- [ ] Record published tag and digest from GHCR

## 3. Home-ops image switch
- [ ] Update `k8s/apps/common/cli-proxy-api/app/helmrelease.yaml`
- [ ] Keep unrelated working tree changes untouched
- [ ] Validate final diff only changes image repository/tag

# Plan

1. In `/Users/shelken/Code/active/containers`, add a new `apps/cli-proxy-api` app that matches the existing app-builder convention. Use a bake file with app name `cli-proxy-api`, version `6.9.28-fillfirst.1`, source `https://github.com/shelken/CLIProxyAPI`, and amd64/arm64 targets.
2. Implement the image Dockerfile by reusing the upstream `CLIProxyAPI` build flow, but fetch source from `https://github.com/shelken/CLIProxyAPI.git` and check out branch `feat/fill-first-codex-warmup` during the builder stage. Preserve build args for `VERSION`, `COMMIT`, and `BUILD_DATE`.
3. Verify the new app matches the containers repo conventions by printing bake metadata locally before committing.
4. Commit the containers repo changes with conventional commit format, push to `main`, and trigger the existing `Release` workflow manually for app `cli-proxy-api` with `release=true` so GHCR publishes `ghcr.io/shelken/cli-proxy-api:6.9.28-fillfirst.1`.
5. Inspect the published image to capture the digest associated with tag `6.9.28-fillfirst.1`.
6. In `/Users/shelken/Code/MyRepo/home-ops`, update `k8s/apps/common/cli-proxy-api/app/helmrelease.yaml` so the app uses `ghcr.io/shelken/cli-proxy-api` and `6.9.28-fillfirst.1@sha256:<digest>`. Leave the unrelated local edits in `config.yaml` and `docs/context/` untouched.
7. Validate the home-ops diff is scoped to the image change only, then stop for your review before any GitOps reconcile step.

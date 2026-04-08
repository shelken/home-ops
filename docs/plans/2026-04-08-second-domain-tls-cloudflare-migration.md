# Second Domain TLS Cloudflare Migration Plan

> For agentic workers: execute this plan conservatively, keep the current effective behavior unchanged, and do not enable any new second-domain routes or DNS records while migrating.

**Goal:** Move `${SECOND_DOMAIN}` certificate management and external DNS ownership to Cloudflare while preserving the current effective runtime behavior and removing stale Aliyun-specific configuration.

**Scope Lock:** Migrate both certificate management and Cloudflare external-dns ownership for `${SECOND_DOMAIN}`. Do not enable any `${SECOND_DOMAIN}` business DNS records, HTTPRoutes, or other new entrypoints during this work.

**Current Confirmed State**

- `${SECOND_DOMAIN}` is now managed in Cloudflare.
- The Cloudflare API token in use can see the required zone.
- The migration target is both `second-domain-tls` management and Cloudflare external-dns ownership for `${SECOND_DOMAIN}`, not adding or enabling any `${SECOND_DOMAIN}` application exposure.
- `echo` is deployed, and its active external route currently comes from `k8s/apps/common/echo/app/helmrelease.yaml`.
- 合并到 `main` 后做 `${SECOND_DOMAIN}` 联通测试时，应临时调整 HelmRelease 内的 `route.app`，测试结束后再撤回，不使用独立的 `dnsendpoint.yaml` / `httproute.yaml` 文件。

**Files In Scope**

- Already migrated in this branch:
  - `k8s/infra/common/cert-manager/cert-manager/tls/clusterissuer.yaml`
  - `k8s/infra/common/cert-manager/cert-manager/tls/clusterissuer-staging.yaml`
  - `k8s/infra/common/cert-manager/cert-manager/ks.yaml`
  - `k8s/infra/common/cert-manager/cert-manager/alidns-webhook/*`
  - `k8s/infra/common/network/external/ali-dns/*`
- Modify in this follow-up:
  - `k8s/infra/common/network/external/cloudflare-dns/app/helmrelease.yaml`
- Keep unchanged:
  - `k8s/infra/common/network/certificates/export/certificate.yaml`
  - `k8s/infra/common/network/certificates/export/pushsecret.yaml`
  - `k8s/infra/common/network/certificates/import/externalsecret.yaml`
  - `k8s/infra/common/network/envoy-gateway/app/envoy.yaml`
  - `k8s/infra/common/network/internal/openwrt-dns/app/helmrelease.yaml`
  - `k8s/apps/common/echo/app/helmrelease.yaml`

**Why Cloudflare Is Sufficient**

- `cert-manager` supports `dns01.cloudflare.apiTokenSecretRef` and multiple solvers selected by `dnsZones`.
- The repository already uses Cloudflare for `${MAIN_DOMAIN}` with `cert-manager-secret`.
- The current Cloudflare token has already been confirmed to see the required zone.

References:

- cert-manager ACME DNS01 solvers: https://cert-manager.io/docs/configuration/acme/dns01/
- ExternalDNS Cloudflare provider auth: https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/cloudflare.md

**Implementation Steps**

### 1. Switch `${SECOND_DOMAIN}` ACME solving to Cloudflare

Update both issuer files so `${SECOND_DOMAIN}` no longer depends on the Aliyun webhook solver.

- In `k8s/infra/common/cert-manager/cert-manager/tls/clusterissuer.yaml`:
  - Remove the `${SECOND_DOMAIN}` solver block that uses:
    - `dns01.webhook`
    - `name: alidns-webhook-secret`
    - `groupName: acme.${MAIN_DOMAIN}`
    - `solverName: alidns-solver`
  - Replace it with a Cloudflare DNS01 solver using `cert-manager-secret` and `API_TOKEN`.
  - Keep selector scoping by `dnsZones: ["${SECOND_DOMAIN}"]`.

- In `k8s/infra/common/cert-manager/cert-manager/tls/clusterissuer-staging.yaml`:
  - Make the same change for staging.

Expected result:

- `second-domain-tls` continues to use `letsencrypt-production`.
- `letsencrypt-production` and `letsencrypt-staging` both solve `${SECOND_DOMAIN}` challenges through Cloudflare.

### 2. Remove cert-manager Aliyun webhook deployment

After `${SECOND_DOMAIN}` no longer references the webhook solver, remove the webhook deployment from Flux.

- In `k8s/infra/common/cert-manager/cert-manager/ks.yaml`:
  - Remove the `Kustomization` named `cert-manager-alidns-webhook`.

- Delete the entire webhook resource set:
  - `k8s/infra/common/cert-manager/cert-manager/alidns-webhook/kustomization.yaml`
  - `k8s/infra/common/cert-manager/cert-manager/alidns-webhook/helmrelease.yaml`
  - `k8s/infra/common/cert-manager/cert-manager/alidns-webhook/helmrepository.yaml`
  - `k8s/infra/common/cert-manager/cert-manager/alidns-webhook/externalsecret.yaml`

Expected result:

- Flux no longer deploys or depends on the Aliyun cert-manager webhook.
- The repository keeps only the Cloudflare-based ACME path.

### 3. Hand off `${SECOND_DOMAIN}` external DNS ownership to Cloudflare

This follow-up still does not require enabling `${SECOND_DOMAIN}` business DNS records in Cloudflare. The goal is to make Cloudflare own the domain so existing disabled resources can be enabled later without another provider migration.

- In `k8s/infra/common/network/external/cloudflare-dns/app/helmrelease.yaml`:
  - Add `${SECOND_DOMAIN}` to `domainFilters`.
  - Keep `sources`, `policy`, `txtOwnerId`, and `txtPrefix` unchanged.

Expected result:

- Cloudflare external-dns watches both `${MAIN_DOMAIN}` and `${SECOND_DOMAIN}`.
- No `${SECOND_DOMAIN}` routes or records become active because nothing new is enabled in `cloudflare-dns` or app kustomizations.

### 4. Keep runtime behavior unchanged

Do not modify the following behaviors:

- `second-domain-tls` secret naming and wildcard coverage stay unchanged.
- Secret export/import flow through Azure stays unchanged.
- Envoy Gateway continues to reference `second-domain-tls` exactly as before.
- `echo.${SECOND_DOMAIN}` remains inactive in normal state; the post-merge validation path is to add a temporary second-domain hostname to `k8s/apps/common/echo/app/helmrelease.yaml`, then remove it after testing.

**Verification Checklist**

Run these checks after editing:

1. Search for stale Aliyun references tied to `${SECOND_DOMAIN}`:

```bash
rg -n "alidns-webhook|alibaba|alibabacloud|secret_token|secret_key" k8s/infra/common/cert-manager k8s/infra/common/network/external
```

Expected:

- No remaining active `${SECOND_DOMAIN}` cert-manager Aliyun solver references.
- No remaining `network/external/ali-dns` resources.

2. Confirm Cloudflare external-dns now watches both `${MAIN_DOMAIN}` and `${SECOND_DOMAIN}` in `k8s/infra/common/network/external/cloudflare-dns/app/helmrelease.yaml`.

3. Confirm `${SECOND_DOMAIN}` issuer config still points to Cloudflare in both issuer files.

4. Confirm the default `echo` configuration still only exposes the main-domain route in `k8s/apps/common/echo/app/helmrelease.yaml`.

5. After this branch is merged to `main`, run a post-merge validation:
   - temporarily add `echo.${SECOND_DOMAIN}` to `route.app.hostnames` in `k8s/apps/common/echo/app/helmrelease.yaml`
   - reconcile `kustomization/echo`
   - verify `https://echo.${SECOND_DOMAIN}` is reachable
   - remove the temporary hostname and reconcile again

6. Confirm `second-domain-tls` references are unchanged where they should stay stable:

```bash
rg -n "second-domain-tls" k8s/infra/common/network
```

Expected:

- References remain in certificate export/import and Envoy Gateway consumption points.

**Non-Goals**

- Do not enable `${SECOND_DOMAIN}` business records beyond provider ownership.
- Do not enable second-domain exposure in the normal committed state.
- Do not add new `${SECOND_DOMAIN}` DNSEndpoint, HTTPRoute, or Ingress resources in this change; the test path is a temporary HelmRelease route change after merge.
- Do not rename `second-domain-tls` or alter wildcard coverage.
- Do not delete any resource outside the Aliyun-specific migration scope.

**Execution Note**

After implementation, verify manifests locally, then follow the repository GitOps rule for reconciliation when the user asks for deployment-related actions.

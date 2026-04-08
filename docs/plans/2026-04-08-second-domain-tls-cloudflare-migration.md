# Second Domain TLS Cloudflare Migration Plan

> For agentic workers: execute this plan conservatively, keep the current effective behavior unchanged, and do not enable any new second-domain routes or DNS records while migrating.

**Goal:** Move `second-domain-tls` management from Aliyun to Cloudflare while preserving the current effective runtime behavior and removing stale Aliyun-specific configuration.

**Scope Lock:** Only migrate certificate management and remove obsolete Aliyun resources. Do not enable any `${SECOND_DOMAIN}` business DNS records, HTTPRoutes, or other new entrypoints during this work.

**Current Confirmed State**

- `${SECOND_DOMAIN}` is now managed in Cloudflare.
- The Cloudflare API token in use can see the required zone.
- The migration target is `second-domain-tls` management, not adding or enabling any `${SECOND_DOMAIN}` application exposure.
- `echo` is deployed, but its `${SECOND_DOMAIN}` resources are not active because these files are commented out from `k8s/apps/common/echo/app/kustomization.yaml`:
  - `./dnsendpoint.yaml`
  - `./httproute.yaml`

**Files In Scope**

- Modify:
  - `k8s/infra/common/cert-manager/cert-manager/tls/clusterissuer.yaml`
  - `k8s/infra/common/cert-manager/cert-manager/tls/clusterissuer-staging.yaml`
  - `k8s/infra/common/cert-manager/cert-manager/ks.yaml`
- Delete:
  - `k8s/infra/common/cert-manager/cert-manager/alidns-webhook/kustomization.yaml`
  - `k8s/infra/common/cert-manager/cert-manager/alidns-webhook/helmrelease.yaml`
  - `k8s/infra/common/cert-manager/cert-manager/alidns-webhook/helmrepository.yaml`
  - `k8s/infra/common/cert-manager/cert-manager/alidns-webhook/externalsecret.yaml`
  - `k8s/infra/common/network/external/ali-dns/ks.yaml`
  - `k8s/infra/common/network/external/ali-dns/app/helmrelease.yaml`
  - `k8s/infra/common/network/external/ali-dns/app/externalsecret.yaml`
  - `k8s/infra/common/network/external/ali-dns/app/kustomization.yaml`
- Keep unchanged:
  - `k8s/infra/common/network/certificates/export/certificate.yaml`
  - `k8s/infra/common/network/certificates/export/pushsecret.yaml`
  - `k8s/infra/common/network/certificates/import/externalsecret.yaml`
  - `k8s/infra/common/network/envoy-gateway/app/envoy.yaml`
  - `k8s/infra/common/network/external/cloudflare-dns/app/helmrelease.yaml`
  - `k8s/apps/common/echo/app/kustomization.yaml`

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

### 3. Remove stale Aliyun external DNS resources

This migration does not require enabling `${SECOND_DOMAIN}` business DNS records in Cloudflare. The goal is cleanup only.

- Delete:
  - `k8s/infra/common/network/external/ali-dns/ks.yaml`
  - `k8s/infra/common/network/external/ali-dns/app/helmrelease.yaml`
  - `k8s/infra/common/network/external/ali-dns/app/externalsecret.yaml`
  - `k8s/infra/common/network/external/ali-dns/app/kustomization.yaml`

Expected result:

- The repository no longer carries stale Aliyun external-dns definitions.
- No `${SECOND_DOMAIN}` routes or records become active because nothing new is enabled in `cloudflare-dns` or app kustomizations.

### 4. Keep runtime behavior unchanged

Do not modify the following behaviors:

- `second-domain-tls` secret naming and wildcard coverage stay unchanged.
- Secret export/import flow through Azure stays unchanged.
- Envoy Gateway continues to reference `second-domain-tls` exactly as before.
- `echo.${SECOND_DOMAIN}` remains inactive because its `DNSEndpoint` and `HTTPRoute` stay commented out from the app kustomization.

**Verification Checklist**

Run these checks after editing:

1. Search for stale Aliyun references tied to `${SECOND_DOMAIN}`:

```bash
rg -n "alidns-webhook|alibaba|alibabacloud|secret_token|secret_key" k8s/infra/common/cert-manager k8s/infra/common/network/external
```

Expected:

- No remaining active `${SECOND_DOMAIN}` cert-manager Aliyun solver references.
- No remaining `network/external/ali-dns` resources.

2. Confirm `${SECOND_DOMAIN}` issuer config now points to Cloudflare in both issuer files.

3. Confirm no application exposure was enabled accidentally:

```bash
rg -n "dnsendpoint.yaml|httproute.yaml" k8s/apps/common/echo/app/kustomization.yaml
```

Expected:

- `./dnsendpoint.yaml` and `./httproute.yaml` remain commented out.

4. Confirm `second-domain-tls` references are unchanged where they should stay stable:

```bash
rg -n "second-domain-tls" k8s/infra/common/network
```

Expected:

- References remain in certificate export/import and Envoy Gateway consumption points.

**Non-Goals**

- Do not enable `${SECOND_DOMAIN}` records in `cloudflare-dns`.
- Do not add `${SECOND_DOMAIN}` to `domainFilters`.
- Do not uncomment `echo` second-domain DNS or route resources.
- Do not rename `second-domain-tls` or alter wildcard coverage.
- Do not delete any resource outside the Aliyun-specific migration scope.

**Execution Note**

After implementation, verify manifests locally, then follow the repository GitOps rule for reconciliation when the user asks for deployment-related actions.

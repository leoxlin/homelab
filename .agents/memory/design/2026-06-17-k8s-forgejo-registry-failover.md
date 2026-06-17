# Running Forgejo and Docker registry on k8s as a Hetzner failover

Date: 2026-06-17
Scope: investigation/recommendations only (no changes shipped). How the current Forgejo and Docker pull-through registry on `falcon` could be failed over to the k3s cluster during a Hetzner outage.

## Current architecture

- **falcon (`192.168.4.10`) is the Hetzner box**: it is in `ansible/inventory/hosts.yaml:43` `servers` but **not** in `k3s` (`hosts.yaml:54-58`). It runs the Docker Compose stacks defined in `ansible/roles/dev/defaults/main.yaml:3-19`.
- **Forgejo** (`ansible/roles/dev/templates/forgejo/compose.yaml:12-26`):
  - `codeberg.org/forgejo/forgejo:15` on ports `10101:3000` (HTTP) and `10102:22` (SSH).
  - Data bind-mounted to `/opt/forgejo/data`.
  - Exposed publicly as `git.hydrahmlb.dev` through the **falcon Cloudflare Tunnel** (`cloudflare-tunnel` stack, `ansible/roles/dev/templates/cloudflare-tunnel/compose.yaml:5-27`).
  - CI runner (`forgejo-runner:12`) talks to `https://git.hydrahmlb.dev/` (`forgejo/config.yaml.tpl:206`).
- **Docker pull-through registry caches** (`ansible/roles/dev/templates/docker-registry/compose.yaml:9-79`):
  - Three `registry:3` containers on ports `5001/5002/5003`.
  - Backed by **Backblaze B2 S3** (`s3.eu-central-003.backblazeb2.com`), independent of Hetzner.
  - Exposed as `docker.hydrahmlb.dev`, `ghcr.hydrahmlb.dev`, `quay.hydrahmlb.dev` through the same falcon tunnel.
  - k3s containerd is already configured to use them via `flux/infrastructure/registry-mirrors/configmap.yaml:8-34` / `daemonset.yaml:2-85`, falling back to upstream registries.
- **k3s cluster** (`hosts.yaml:54-68`): `marmot-[01:03]` servers, `pika-[01:04]`/`marten`/`numbat` agents — all on `192.168.2.x`, separate from falcon's subnet.
- **k3s ingress path**: Cloudflare Tunnel k8s daemon (`flux/infrastructure/cloudflared/deployment.yaml:2-51`) → Istio public gateway (`192.168.3.x` via MetalLB, `flux/infrastructure/metallb/resources.yaml:8-9`) → VirtualService (`flux/application/cloud-code/service.yaml:14-33`).
- **Domains split**: k8s services use `*.hydrahmlb.cc`; falcon services use `*.hydrahmlb.dev`. `external-dns` only manages `singularr.app` (`flux/infrastructure/external-dns/release.yaml:38-39`).

## Can k8s host the Docker registry? Yes — and it is the easier failover

A `registry:3` container runs trivially in the cluster:

- **Storage**: keep Backblaze B2 as the backend (same bucket, different `rootdirectory`, e.g. `/k8s-registry-docker`) so cached blobs survive pod moves and are independent of Longhorn node placement. Longhorn is an alternative but adds latency and a cross-node sync concern for a cache.
- **Config**: replicate the env from `docker-registry/compose.yaml:19-31` in a Deployment + Secret (htpasswd) + OnePasswordItem.
- **Exposure**: add a `VirtualService` on the k8s Istio gateway. For k3s to consume it without leaving the LAN, point `registry-mirrors/configmap.yaml:12-20` at the in-cluster Service first, then the public hostname, then upstream.
- **Bootstrap risk**: the cluster needs the registry image to start the registry pod. Mitigate by:
  1. Pre-pulling `registry:3` on all nodes (image is tiny).
  2. Keeping upstream fallbacks in `registries.yaml`.
  3. Enabling **Spegel** (`--embedded-registry`) so nodes can pull from each other when the central cache is unavailable.

## Can k8s host Forgejo? Yes, but SSH is the hard part

Forgejo has a Helm chart/operator and can use existing cluster primitives:

- **Database**: CloudNativePG is already deployed (`flux/database/postgres-operator/release.yaml:12-13`); create a `Cluster` like `litellm/database.yaml:1-15`.
- **Storage**: Longhorn PVC for `/data` repositories.
- **HTTP/HTTPS**: VirtualService on Istio public gateway + cert-manager, same pattern as `cloud-code/service.yaml:14-33`.
- **SSH/Git (`git@git.hydrahmlb.dev:2222` or `:22`)**: Cloudflare Tunnel (free) only proxies HTTP/HTTPS. TCP/SSH requires either:
  - **Cloudflare Spectrum** (paid) on port 22.
  - **Pangolin/MetalLB** exposing a `LoadBalancer` Service with a public IP and port-forwarding/1:1 NAT on the edge router.
  - Running SSH on a non-standard HTTPS port and relying on `CONNECT` — brittle and not standard Git tooling.
  If you only need the web UI and CI (HTTPS), Forgejo in k8s is straightforward. Full Git-over-SSH parity requires an extra public TCP path.
- **CI runners**: the existing runner config bind-mounts `/var/run/docker.sock` (`forgejo/config.yaml.tpl:38-39`). In k8s you would run runners as pods (e.g. `code.forgejo.org/forgejo/runner`) and either use Docker-in-Docker or switch to Kubernetes executor. This is a meaningful change to workflow behavior.
- **Data continuity**: failing over means either (a) a cold standby with an empty/backup-restored instance, or (b) active-active replication of the Postgres DB and object storage. For a home failover, **cold standby restored from backup** is the practical choice.

## Recommended priority

1. **Ship the registry in k8s first** — highest value, lowest risk.
   - It already backs onto B2, so Hetzner being down does not destroy storage.
   - Fixes the immediate pain: k3s image pulls stop depending on falcon.
   - Can coexist with the falcon registries; switch by changing `registry-mirrors/configmap.yaml` endpoints.
2. **Enable Spegel** (`--embedded-registry`) as a belt-and-suspenders fallback so nodes serve images to each other.
3. **Add LAN-direct fallback endpoints** in `registry-mirrors/configmap.yaml` so when falcon is reachable locally the cluster does not hairpin through Cloudflare.
4. **Defer Forgejo-on-k8s** unless you can solve SSH exposure and accept a cold-standby restore workflow. If SSH can move to a non-22 port or Spectrum/Pangolin TCP, revisit.

## Suggested change bundle (registry failover)

- `flux/application/registry/{namespace,deployment,service,virtualservice,secrets,kustomization,registry-app}.yaml` — run `registry:3` in cluster, backed by B2 with a new `rootdirectory`.
- `flux/application/registry/configmap.yaml` (or env in Deployment) — `REGISTRY_STORAGE_*`, `REGISTRY_PROXY_REMOTEURL`, `REGISTRY_AUTH_HTPASSWD_*`.
- `flux/infrastructure/registry-mirrors/configmap.yaml` — reorder endpoints to cluster Service first, add `docker.hydrahmlb.dev` fallback, keep upstream last.
- `ansible/roles/k3s/defaults/main.yaml:19` — add `--embedded-registry` to `k3s_extra_server_args`.
- `flux/kustomization.yaml` — add `application/registry/registry-app.yaml` (after `infrastructure`).
- Optionally update `external-dns` domainFilters to manage `hydrahmlb.dev` if you want DNS failover automated; otherwise repoint `git.hydrahmlb.dev` / `docker.hydrahmlb.dev` CNAMEs manually in Cloudflare during an outage.

## What an actual Hetzner-down failover looks like

1. DNS: point `docker.hydrahmlb.dev`, `ghcr.hydrahmlb.dev`, `quay.hydrahmlb.dev` to the k8s tunnel CNAME instead of the falcon tunnel CNAME.
2. `registry-mirrors/configmap.yaml` already points at the public hostnames, so k3s starts using the k8s registry once DNS propagates.
3. For Forgejo: point `git.hydrahmlb.dev` to k8s tunnel CNAME for HTTPS; SSH requires the separate TCP path noted above.
4. When falcon returns, flip DNS back.

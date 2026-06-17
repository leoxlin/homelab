# Automating Cloudflare Zero Trust tunnel configs

Date: 2026-06-17
Scope: investigation/recommendations only. How public traffic enters Hydra via Cloudflare Tunnels and how to move tunnel ingress rules and Zero Trust config from the Cloudflare dashboard into code.

## Current architecture

- **Two tunnels**
  - k8s tunnel: `flux/infrastructure/cloudflared/deployment.yaml:23-51` runs `cloudflared:2026.6.0` in `istio-public-ingress`, auth via `TUNNEL_TOKEN` from 1Password `main.cloudflared`.
  - falcon tunnel: `ansible/roles/dev/templates/cloudflare-tunnel/compose.yaml:5-27` runs the same image on falcon (`192.168.4.10`) for docker registry cache mirrors (`docker.hydrahmlb.dev`, etc.).
- **DNS is automated**: `flux/infrastructure/external-dns/release.yaml:26-40` uses the Cloudflare provider, watches `service` and `istio-virtualservice`, and syncs `singularr.app` with `policy: sync`. The VirtualService sets `external-dns.alpha.kubernetes.io/target: ${CLOUDFLARE_TUNNEL_CNAME}` via Flux `postBuild.substituteFrom` (`flux/application/singularr/singularr-app.yaml:16-19`, `flux/system/secrets.yaml:1-10`).
- **Traffic path**: public request → Cloudflare edge → cloudflared pod → Istio public gateway (`192.168.3.x` via MetalLB) → backend service.
- **Gap**: tunnel ingress rules (public hostname → internal origin) and any Zero Trust Access apps/policies are configured manually in the Cloudflare dashboard. The repo automates DNS records and the tunnel daemon lifecycle, but not the Cloudflare-side tunnel config.

## Options

### 1. Locally-managed tunnels with `config.yaml` in Git (recommended if avoiding Terraform)
Create tunnels with `cloudflared tunnel create`, store the credentials JSON in 1Password, and mount a `config.yaml` ConfigMap into the cloudflared pod. Ingress rules then live in the repo.

- Pros: no Terraform or Cloudflare API automation needed; config is plain YAML in Git; `cloudflared tunnel ingress validate` can check it locally.
- Cons: you must switch from dashboard-managed (`TUNNEL_TOKEN`) to CLI-created tunnels; credential rotation is manual; Zero Trust Access policies still need the dashboard/API.

### 2. Terraform / OpenTofu with the Cloudflare provider
Manage `cloudflare_tunnel`, `cloudflare_tunnel_config`, public DNS records, and optionally `cloudflare_access_application` + `cloudflare_access_policy` through the Cloudflare API.

- Pros: covers the full Cloudflare side; existing dashboard config can be imported with `cf-terraforming`; state can live in S3/B2; reuses the repo's 1Password API-token pattern.
- Cons: adds a new toolchain; state needs backup and locking.

### 3. Kubernetes operator (e.g., `adyanth/cloudflare-operator` or `strrl/cloudflare-tunnel-ingress-controller`)
Let a controller create/manage tunnels and DNS records from Kubernetes Services or Ingress resources.

- Pros: native GitOps, no Terraform.
- Cons: adds another controller; less control over exact ingress ordering and origin settings.

### 4. Continue manual dashboard + external-dns
Keep the current split.

- Pros: zero change.
- Cons: no PR review for public ingress changes; config drifts from the repo.

## Recommendation

Since you want to avoid Terraform, use **Option 1**: convert to **locally-managed tunnels** and keep the ingress `config.yaml` in Git. This is the only way to set tunnel config "within cloudflared" itself; cloudflared cannot push ingress rules back to Cloudflare for dashboard-managed tunnels.

### Suggested change bundle

- Create new local tunnels:
  ```bash
  cloudflared tunnel create hydra-k8s
  cloudflared tunnel create hydra-falcon
  ```
  This writes `<tunnel-id>.json` credential files. Note the tunnel IDs.
- Store the credential JSONs in 1Password and update the k8s Secret (`flux/infrastructure/cloudflared/secrets.yaml`) and falcon `.env.tpl` to inject credentials instead of `TUNNEL_TOKEN`.
- Add a ConfigMap with `config.yaml` next to the cloudflared Deployment:
  ```yaml
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: cloudflared-config
    namespace: istio-public-ingress
  data:
    config.yaml: |
      tunnel: <k8s-tunnel-id>
      credentials-file: /etc/cloudflared/creds.json
      no-autoupdate: true
      loglevel: info
      metrics: 0.0.0.0:2000
      ingress:
        - hostname: singularr.app
          service: https://hydrahmlb-public-gateway.istio-public-ingress.svc.cluster.local
          originRequest:
            noTLSVerify: true
        - service: http_status:404
  ```
- Update `flux/infrastructure/cloudflared/deployment.yaml` to mount the ConfigMap and credentials Secret, and change the command to:
  ```yaml
  command:
    - cloudflared
    - tunnel
    - --config
    - /etc/cloudflared/config.yaml
    - run
  ```
- Update the tunnel CNAME target used by external-dns (`flux-build-secrets` item `CLOUDFLARE_TUNNEL_CNAME`) to `<k8s-tunnel-id>.cfargotunnel.com`.
- Repeat the ConfigMap/credentials pattern for the falcon Docker Compose stack.
- Add `cloudflared tunnel ingress validate` to `mise lint` or a pre-commit check.

### What cloudflared can and cannot do

- `cloudflared tunnel route dns <tunnel-id> <hostname>` creates a CNAME record; useful if you ever drop external-dns.
- `cloudflared tunnel ingress validate` checks a local `config.yaml`.
- For **remotely-managed** tunnels (the current `TUNNEL_TOKEN` setup), ingress rules must be edited in the dashboard or via the Cloudflare API — cloudflared cannot push them. Switching to locally-managed tunnels is what puts the config back in your hands.

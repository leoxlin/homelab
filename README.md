# Hydra Homelab

Infrastructure-as-code repository for my self-hosted Kubernetes homelab.

## Hardware

| Hostname    | Harware          | OS             | Role                    |
|-------------|------------------|----------------|-------------------------|
| marten      | Mac Mini 2018    | debian/omv     | nas / media server      |
| marmot[1:3] | Elitedesk 300 G3 | debain         | k3s server              |
| pika[1:4]   | RPi 5 8GB        | dietpi         | k3s agent               |
| numbat      | Jetson AGX Orin  | ubuntu l4t     | ai / ml workloads       |
| apodemus    | Beelink MINI S12 | debian         | git / docker            |

## Infrastructure

| Category       | Technology                                             |
|----------------|--------------------------------------------------------|
| Orchestration  | k3s                                                    |
| GitOps         | FluxCD                                                 |
| Load Balancer  | MetalLB                                                |
| Ingress        | Istio, Cloudflared                                     |
| Service Mesh   | Istio (ambient)                                        |
| Storage        | Longhorn                                               |
| Certificates   | cert-manager                                           |
| Secrets        | External Secrets, 1Password Connect                    |
| Monitoring     | Victoria Metrics, Grafana                              |

## Development

Install development tools and setup requirements with mise:

```
mise install
mise setup
```

Running linters

```
mise lint
```

## Bootstrap New Nodes

Copy and run the bootstrap script on new nodes:

```
scp ./bootstrap/bootstrap.sh root@hostname:~
ssh root@hostname ./bootstrap.sh
```

This creates the required users, configures SSH keys, and prepares the node for Ansible.

## Running Ansible

```
cd ansible
ansible-playbook playbooks/core.yaml   # Base configuration
ansible-playbook playbooks/k3s.yaml    # Kubernetes cluster
```

## Flux Bootstrap

Initialize FluxCD on a fresh cluster:

```
./bootstrap/onepass.sh
./bootstrap/flux.sh
```

# Hydra Homelab

Infrastructure-as-code repository for my self-hosted Kubernetes homelab.

## Hardware

| Hostname    | Harware          | OS             | Role                    |
|-------------|------------------|----------------|-------------------------|
| marten      | Mac Mini 2018    | debian/omv     | nas / media server      |
| pika[1:2]   | RPi 5 8GB        | dietpi         | k8s control             |
| pika[3:4]   | RPi 5 8GB        | dietpi         | k8s worker              |
| marmot[1:3] | Elitedesk 300 G3 | debain         | k8s worker              |
| numbat      | Jetson AGX Orin  | ubuntu l4t     | ai / ml workloads       |

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

## Development Setup

Install development tools with mise:

```
mise install
mise exec -- ansible-galaxy install -r requirements.yaml
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
./bootstrap/onepass-operator.sh
./bootstrap/flux-operator.sh
```

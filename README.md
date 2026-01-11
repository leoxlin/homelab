# Hydra Hmlb

All of the configuration for my homelab.

## Development

Setup all required development tools with `mise`

```
mise install
```

## Bootstrap new nodes

All automation will require new nodes to be bootstrapped first. Bootstrap should
setup ansible and critical configurations.

- Install the llin user
- Install the homelab user
- Add personal SSH key to the human user
- Add agent SSH key to homelab user

```
scp ./bootstrap/bootstrap.sh root@hostname:~
```

## Running ansible

Run any ansible playbooks from the ansible dir.

```
cd ansible
ansible-playbook playbooks/k3s.yaml
```

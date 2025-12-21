# Hydra Hmlb

All of the configuration for my homelab.

## Bootstrap new nodes

All automation will require new nodes to be bootstrapped first. Bootstrap should
setup ansible and critical configurations.

- Install the llin user
- Install the homelab user
- Add personal SSH key to the human user
- Add agent SSH key to homelab user

```
scp ./scripts/bootstrap.sh root@hostname:~
```

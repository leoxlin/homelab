#!/bin/bash
# Bootstrap a host to be managed by Ansible

AGENT_SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFz7Kzh1klG58YsBnoEn/LcDXaVSM6Ye4/9Tb5Jy1kdt agent@hydra"
HUMAN_SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINVVzpr3kf+2Y18UTEXwe79JOLkUKda26aDWcWYUQtge me@leoxlin.com"

echo "Bootstrapping ansible user and group"

if ! id -u hydra > /dev/null 2>&1; then
    echo "Creating hydra agent user and group..."
    groupadd -g 1111 hydra
    useradd -u 1111 -g 1111 -m -s /bin/bash hydra

    # Create .ssh directory for homelab agents
    mkdir -p /home/hydra/.ssh
    chmod 700 /home/hydra/.ssh

    # Add homelab agent SSH public key to authorized_keys
    echo "$AGENT_SSH_PUBLIC_KEY" > /home/hydra/.ssh/authorized_keys
    chmod 600 /home/hydra/.ssh/authorized_keys
    chown -R 1111:1111 /home/hydra/.ssh

    # Add homelab agent to sudoers (passwordless)
    echo "hydra ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/hydra
    chmod 440 /etc/sudoers.d/hydra
fi

if ! id -u llin > /dev/null 2>&1; then
    echo "Creating human user and group..."
    groupadd -g 1000 llin
    useradd -u 1000 -g 1000 -m -s /bin/bash llin

    # Create .ssh directory for this human
    mkdir -p /home/llin/.ssh
    chmod 700 /home/llin/.ssh

    # Add this human SSH public key to authorized_keys
    echo "$HUMAN_SSH_PUBLIC_KEY" > /home/llin/.ssh/authorized_keys
    chmod 600 /home/llin/.ssh/authorized_keys
    chown -R 1000:1000 /home/llin/.ssh

    # Add this human user to sudoers (passwordless)
    echo "llin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/llin
    chmod 440 /etc/sudoers.d/llin
fi

echo "Bootstrapped users and groups!"

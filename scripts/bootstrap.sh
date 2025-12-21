#!/bin/bash
# Bootstrap a host to be managed by Ansible

AGENT_USER="agent"
AGENT_UID=1111
AGENT_GID=1111
AGENT_SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFz7Kzh1klG58YsBnoEn/LcDXaVSM6Ye4/9Tb5Jy1kdt"

HUMAN_USER="llin"
HUMAN_UID=1000
HUMAN_GID=1000
HUMAN_SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINVVzpr3kf+2Y18UTEXwe79JOLkUKda26aDWcWYUQtge me@leoxlin.com"

echo "Bootstrapping ansible user and group"

if ! getent group $AGENT_GID > /dev/null 2>&1; then
    echo "Creating ansible group..."
    groupadd -g $AGENT_GID $AGENT_USER
fi

if ! id -u $AGENT_USER > /dev/null 2>&1; then
    echo "Creating ansible user..."
    useradd -u $AGENT_UID -g $AGENT_GID -m -s /bin/bash $AGENT_USER
fi

# Create .ssh directory for homelab agents
mkdir -p /home/$AGENT_USER/.ssh
chmod 700 /home/$AGENT_USER/.ssh

# Add homelab agent SSH public key to authorized_keys
echo "$AGENT_SSH_PUBLIC_KEY" > /home/$AGENT_USER/.ssh/authorized_keys
chmod 600 /home/$AGENT_USER/.ssh/authorized_keys
chown -R $AGENT_USER:$AGENT_USER /home/$AGENT_USER/.ssh

# Add ansible user to sudoers (passwordless)
echo "$AGENT_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$AGENT_USER
chmod 440 /etc/sudoers.d/$AGENT_USER

echo "Bootstrapped ansible user and group!"

#!/bin/bash
# Bootstrap a host to be managed by Ansible

ANSIBLE_USER="ansible"
ANSIBLE_UID=1100
ANSIBLE_GID=1100
SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFz7Kzh1klG58YsBnoEn/LcDXaVSM6Ye4/9Tb5Jy1kdt"

echo "Bootstrapping ansible user and group"

if ! getent group $ANSIBLE_GID > /dev/null 2>&1; then
    echo "Creating ansible group..."
    groupadd -g $ANSIBLE_GID $ANSIBLE_USER
fi

if ! id -u $ANSIBLE_USER > /dev/null 2>&1; then
    echo "Creating ansible user..."
    useradd -u $ANSIBLE_UID -g $ANSIBLE_GID -m -s /bin/bash $ANSIBLE_USER
fi

# Create .ssh directory for homelab agents
mkdir -p /home/$ANSIBLE_USER/.ssh
chmod 700 /home/$ANSIBLE_USER/.ssh

# Add homelab agent SSH public key to authorized_keys
echo "$SSH_PUBLIC_KEY" > /home/$ANSIBLE_USER/.ssh/authorized_keys
chmod 600 /home/$ANSIBLE_USER/.ssh/authorized_keys
chown -R $ANSIBLE_USER:$ANSIBLE_USER /home/$ANSIBLE_USER/.ssh

# Add ansible user to sudoers (passwordless)
echo "$ANSIBLE_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$ANSIBLE_USER
chmod 440 /etc/sudoers.d/$ANSIBLE_USER

echo "Bootstrapped ansible user and group!"

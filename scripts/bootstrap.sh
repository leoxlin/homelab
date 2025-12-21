#!/bin/bash
# Bootstrap a host to be managed by Ansible

AGENT_SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFz7Kzh1klG58YsBnoEn/LcDXaVSM6Ye4/9Tb5Jy1kdt agent@hydra"
HUMAN_SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINVVzpr3kf+2Y18UTEXwe79JOLkUKda26aDWcWYUQtge me@leoxlin.com"
OMV_KEY_DIR="/var/lib/openmediavault/ssh/authorized_keys"

bootstrap_user() {
    local USER=$1
    local USER_ID=$2
    local PUBLIC_KEY=$3

    if ! id -u $USER > /dev/null 2>&1; then
        echo "Creating $USER user and group..."
        groupadd -g $USER_ID $USER
        useradd -u $USER_ID -g $USER_ID -m -s /bin/bash $USER
    fi

    if [ ! -f /etc/sudoers.d/$USER ]; then
        echo "hydra ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USER
        chmod 440 /etc/sudoers.d/$USER
    fi

    if [ ! -d /home/$USER/.ssh ]; then
        mkdir -p /home/$USER/.ssh
        chmod 700 /home/$USER/.ssh
        echo "$PUBLIC_KEY" > /home/$USER/.ssh/authorized_keys
        chmod 600 /home/$USER/.ssh/authorized_keys
        chown -R $USER:$USER /home/$USER/.ssh
    fi

    if [ -d $OMV_KEY_DIR ] && [ ! -f $OMV_KEY_DIR/$USER ]; then
        usermod -aG _ssh $USER
        usermod -aG sudo $USER
        echo "$PUBLIC_KEY" > $OMV_KEY_DIR/$USER
        chmod 600 $OMV_KEY_DIR/$USER
        chown -R $USER:root $OMV_KEY_DIR/$USER
    fi
}

echo "Bootstrapping ansible user and group"

bootstrap_user hydra 1111 "$AGENT_SSH_PUBLIC_KEY"
bootstrap_user llin 1000 "$HUMAN_SSH_PUBLIC_KEY"

echo "Bootstrapped users and groups!"

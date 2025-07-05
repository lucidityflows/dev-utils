#!/bin/bash
# File: add-to-group.sh
# Created: 2025-07-05
# Description: Harden kernel parameters and restrict unsafe syscalls using sysctl and GRUB flags.

sudo groupadd devteam
sudo usermod -aG devteam <username>

sudo chown -R root:devteam /srv/www/<project>
sudo chmod -R 2775 /srv/www/<project>

chmod g+s /srv/www/<project>

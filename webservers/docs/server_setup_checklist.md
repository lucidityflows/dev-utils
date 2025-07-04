## Dev-Ready Secure Server Setup: Ubuntu CI/CD Environment

### ✅ Provision → Secure → Configure → Deploy

---

### 🧱 1. Provision Instance
- [ ] Launch Ubuntu LTS (22.04 or later) VM (min: 2 vCPU / 4GB RAM)
- [ ] Assign static IP, hostname, tags/labels
- [ ] Upload SSH keys

---

### 🔐 2. Initial Security Hardening
- [ ] `apt update && apt full-upgrade -y`
- [ ] Set timezone via `timedatectl set-timezone`
- [ ] Install packages:
  ```bash
  apt install -y fail2ban ufw curl vim git gnupg lsb-release bash-completion net-tools
  ```
- [ ] Configure firewall:
  ```bash
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH
  ufw allow 8080/tcp
  ufw enable
  ```
- [ ] Harden SSH (`/etc/ssh/sshd_config`):
  - `PasswordAuthentication no`
  - `PermitRootLogin no`
  - Add `AllowUsers rob zac`
  - Restart: `systemctl restart sshd`

---

### 👥 3. User & SSH Setup
- [ ] Create users & add to sudo:
  ```bash
  adduser rob && usermod -aG sudo rob
  adduser zac && usermod -aG sudo zac
  ```
- [ ] Setup `.ssh` directories:
  ```bash
  mkdir -p /home/{rob,zac}/.ssh
  curl https://github.com/rob.keys > /home/rob/.ssh/authorized_keys
  curl https://github.com/zac.keys > /home/zac/.ssh/authorized_keys
  chown -R rob:rob /home/rob/.ssh && chmod 700 /home/rob/.ssh
  chown -R zac:zac /home/zac/.ssh && chmod 700 /home/zac/.ssh
  chmod 600 /home/*/.ssh/authorized_keys
  ```
- [ ] Test login for both users

---

### 🛡️ 4. Root Environment Setup
- [ ] Deploy `/usr/local/sbin/deploy_admin_script_layout.sh`
- [ ] Harden sudo (require tty, log to `/var/log/sudo.log`)
- [ ] Create `/etc/profile.d/hardening.sh` (if needed)

---

### ⚙️ 5. System Services & Logging
- [ ] Enable & start fail2ban
- [ ] Configure auditd or psacct
- [ ] Setup logrotate for Jenkins and admin logs
- [ ] (Optional) `unattended-upgrades` for security patches

---

### 📆 6. Jenkins Setup
- [ ] Install via official repo
- [ ] UFW: allow port `8080`
- [ ] Start and enable Jenkins:
  ```bash
  systemctl enable jenkins
  systemctl start jenkins
  ```
- [ ] Secure Jenkins:
  - Setup admin users (`rob`, `zac`)
  - Disable signup, CLI remoting
  - Install plugins: Git, Pipeline, Blue Ocean, etc.
  - Configure webhook triggers for GitHub

---

### 📦 7. Developer Tooling
- [ ] Install:
  ```bash
  apt install -y docker.io docker-compose make unzip build-essential
  ```
- [ ] Add `rob`, `zac` to `docker` group
- [ ] Pull base images for CI/CD pipeline
- [ ] (Optional) Install Node.js, Python, Go, etc.

---

### 📂 8. Dev Directory Layout
- [ ] Create:
  ```bash
  mkdir -p /srv/devops /srv/projects /opt/admin-scripts
  ```
- [ ] Set ownership and permissions

---

### ⚙️ 9. CI/CD Automation
- [ ] Connect Jenkins to GitHub repo
- [ ] Setup declarative Jenkinsfile pipeline
- [ ] Include linting, build, test, deploy
- [ ] Store secrets in `.env`/`secrets/` (chmod 600)

---

### 🕊️ 10. Final Audit & Lockdown
- [ ] Verify UFW, SSH, user access
- [ ] Port scan: `ss -tuln`, `netstat -plant`
- [ ] Run `lynis` or `osquery` for audit
- [ ] Take snapshot/backups

---

Output options:
- Deployable bash script
- GitHub issue template
- Markdown documentation


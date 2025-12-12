# Migration of users from one virtual machine to another 

<img src="portada.png" alt="GitHub Action Test">

### Verify users on two different virtual machines running Linux (Red Hat/Ubuntu).  

## 📌 Workflows Overview  

### 🟢 `verify-users.yml` (Using `users.yml`)  
- **Input:** `users.yml` → List of users to verify.  
- **Action:** Connects to VMs and verifies each user's UID/GID against `users.yml`.  
- **Result:** If a user doesn’t exist, configure LDAP.  

### 🔵 `direct-verification.yml` (Using `users.yml`)  
- **Input:** `users.yml` → List of users to verify.  
- **Action:** Connects to VMs and verifies each user's UID/GID against `users.yml`.  
- **Result:** If a user doesn’t exist or UID/GID mismatch is found, create or update the user. LDAP is not used; authentication is host-based.  

### 🟠 `verify_and_sync_users.yml` (Without `users.yml`)  
- **Reference Machine:** `VM1_HOST` (Primary source of truth for user data).  
- **Action:** Retrieves all user UID/GID data from `VM1_HOST` (excluding system accounts) and verifies against `VM2_HOST`. Also synchronizes home directory files (names, sizes, permissions) from `VM1` to `VM2` using `rsync` (via the runner).
- **Result:** If a user doesn’t exist or has a UID/GID mismatch, create or update the user on `VM2_HOST`. Files missing or differing in `VM2` are synced from `VM1`. Authentication is host-based (no LDAP).
- **Testing (`test-verify-and-sync` job):**
  - **Docker-based Mock Environment:** Spins up two Ubuntu containers (`vm1`, `vm2`) to simulate the source and destination VMs.
  - **Automated Setup:** Installs `openssh-server`, `sudo`, and `rsync` in the containers. Configures SSH keys (ED25519) and `sshd` settings (`StrictModes no`, `PubkeyAuthentication yes`) for passwordless access from the runner.
  - **Network Aliases:** Localhost ports (2221, 2222) are mapped to container SSH ports. A `~/.ssh/config` file is generated on the runner to alias `vm1` and `vm2`, allowing the script to run unchanged (`bash scripts/verify_and_sync_users.sh "vm1" "vm2"`).
  - **Execution Control:** When triggering the workflow manually, use the **Execution Mode** input to choose between:
    - `test`: Runs the verification against the mock Docker environment (No secrets needed).
    - `production`: Runs against the real VMs defined in secrets.  

### 🔴 `disaster_recovery.yml` (Without `users.yml`)  
- **Reference Machines:** Both `VM1_HOST` and `VM2_HOST` are treated as sources of truth.  
- **Action:** Extracts user data (UID/GID) from `/etc/passwd` on both machines.  
- **Result:** If a user doesn’t exist or has a UID/GID mismatch, create or update the user on the affected machine.  
- **Testing:** Run the workflow using GitHub Actions and Docker (`test_disaster_recovery.yml`). No secret keys are used in the test.  

---

## 🔑 Setting Up Secrets  

To run these workflows, you need to configure secret keys in your repository:  

1. Go to **Settings > Secrets and variables > Actions**.  
2. Create a new secret named **`SSH_PRIVATE_KEY`**, then paste your private SSH key.  
3. Add the following secrets for VM connection details:  
   - **`VM1_HOST`** → Format: `username@IP-TO-HOST`  
   - **`VM2_HOST`** → Format: `username@IP-TO-HOST`  

---


## 🔧 Generating and Configuring an SSH Key  

If you don’t have an SSH key, follow these steps to create one:  

1) Generate a pair of SSH keys (public and private) with any string:
   
   ```bash
    ssh-keygen -t rsa -b 4096 -C "my_email@example.com"
   ```
2) It will ask for a path to save the new keys, to avoid overwrite another key, select a new filename. Example:

   ```bash
    /home/usuario/github-action-key
   ```

3) Leave the password in blank, just to avoid problems with the GitHub Actions Runner

4) You will see two new files:

   - Private key: `/home/usuario/github-action-key`
   - Public key: `/home/usuario/github-action-key.pub`

5) You will need to copy the `Public key`. Open the file to copy it at:

   ```bash
   cat /home/usuario/github-action-key.pub
   ```

6) The following process must be repeated  on your machines, in order to authorize access with the public keys:

  6.1) Access to you machines phisically or through SSH with:

  ```bash
  ssh user@<IP_O_HOSTNAME>
  ```

  6.2) Add the public key to the `~/.ssh/authorized_keys` file of the same user that you connected with SSH:

  ```bash
  echo "YOUR_PUBLIC_KEY" >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  ```

  6.3) Check if the SSH server has enabled the authentication with public keys in the file `/etc/ssh/sshd_config`, and check the following lines:

  ```bash
  PubkeyAuthentication yes
  AuthorizedKeysFile .ssh/authorized_keys
  ```

  6.4) Restart the SSH service:

  ```ssh
  sudo systemctl restart sshd
  ```



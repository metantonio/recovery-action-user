#!/bin/bash

VM1_HOST=$1
VM2_HOST=$2

# Function to get a list of users, their UID/GID, and Home Directory from a host
get_users_from_host() {
  local host=$1
  ssh -o StrictHostKeyChecking=no user@$host "awk -F: '\$3 >= 1000 && \$3 < 65534 {print \$1,\$3,\$4,\$6}' /etc/passwd"
}

# Fetch users from VM1
echo "Fetching users from $VM1_HOST..."
users_vm1=$(get_users_from_host $VM1_HOST)

# Process each user from VM1
echo "$users_vm1" | while read -r user uid gid home_dir; do
  echo "Checking user $user (UID=$uid, GID=$gid, Home=$home_dir) on $VM2_HOST..."

  # Check if the user exists on VM2
  ssh -o StrictHostKeyChecking=no user@$VM2_HOST <<EOF
if id "$user" >/dev/null 2>&1; then
  EXISTING_UID=\$(id -u "$user")
  EXISTING_GID=\$(id -g "$user")

  if [[ "\$EXISTING_UID" -ne "$uid" || "\$EXISTING_GID" -ne "$gid" ]]; then
    echo "User $user exists on $VM2_HOST but with mismatched UID/GID. Updating..."
    sudo usermod -u $uid -g $gid "$user"
  else
    echo "User $user exists on $VM2_HOST with matching UID/GID."
  fi
else
  echo "User $user does not exist on $VM2_HOST. Creating..."
  sudo groupadd -g $gid "$user" || echo "Group $user already exists."
  sudo useradd -u $uid -g $gid -m -d "$home_dir" "$user"
fi
EOF

  # File Synchronization Logic (VM1 -> Runner -> VM2)
  echo "Syncing files for user $user from $VM1_HOST to $VM2_HOST..."
  
  TEMP_DIR="/tmp/sync_${user}_$$"
  mkdir -p "$TEMP_DIR"

  # Step 1: Sync from VM1 to Runner (Temporary Dir)
  # Using -a to preserve permissions, owner, groups, times (archive mode)
  # Using --delete to remove files in destination that are not in source? 
  # Note: running as 'user' might have permission issues accessing other users' files if not root/sudo. 
  # Assuming the SSH user has sudo NOPASSWD or we just sync what we can. 
  # Actually, usually these recovery scripts run as a privileged user or via sudo.
  # The original script uses `sudo useradd` inside the ssh block, implying the ssh user has sudo rights.
  # rsync over ssh with sudo is tricky. For now, assuming standard access or sudo is handled via config if needed. 
  # To keep it simple and consistent with the request "copy missing files... verify names and size", rsync -av is best.
  
  if rsync -avzq -e "ssh -o StrictHostKeyChecking=no" "user@$VM1_HOST:$home_dir/" "$TEMP_DIR/"; then
      echo "  - Successfully pulled files from $VM1_HOST"
      
      # Step 2: Sync from Runner to VM2
      if rsync -avzq -e "ssh -o StrictHostKeyChecking=no" "$TEMP_DIR/" "user@$VM2_HOST:$home_dir/"; then
         echo "  - Successfully pushed files to $VM2_HOST"
      else
         echo "  - FAILED to push files to $VM2_HOST"
      fi
  else
      echo "  - FAILED to pull files from $VM1_HOST"
  fi

  # Cleanup
  rm -rf "$TEMP_DIR"

done

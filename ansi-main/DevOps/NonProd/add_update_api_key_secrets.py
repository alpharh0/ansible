#!/usr/bin/env python3
import os
import subprocess
import sys

### ===========================================================
## Update if necessary
### ===========================================================
base_path = '/var/ansible/var_files/secret_keys/'

### ===========================================================
### Get current user's username
### ===========================================================
def get_current_username():
    try:
        return os.getlogin()
    except Exception as e:
        print(f"Error fetching username: {e}")
        sys.exit(1)

### ===========================================================
### Ensure a Directory Exists with Proper Permissions
### ===========================================================
def ensure_directory_exists(directory):
    try:
        os.makedirs(directory, exist_ok=True)
    except PermissionError:
        print(f"[!] Permission denied: Cannot create {directory}. Trying with sudo...")
        try:
            subprocess.run(["sudo", "mkdir", "-p", directory], check=True)
            subprocess.run(["sudo", "chown", f"{username}:{username}", directory], check=True)
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] Failed to create directory with sudo: {e}")
            sys.exit(1)

### ===========================================================
### Encrypt Credentials using ansible-vault
### ===========================================================
def encrypt_file_with_vault(file_path, fw_name):
    print(f"Encrypting {file_path} with ansible-vault...")
    try:
        subprocess.run(["ansible-vault", "encrypt", file_path], check=True)
        print(f"File {file_path} successfully encrypted!")
        print("\nNext Step:")
        print(f'sudo ansible-playbook -i hosts.firewall main.yml --ask-vault-pass --tags "rule_add" -l {fw_name} -e user={username}')
    except subprocess.CalledProcessError as e:
        print(f"Error encrypting file: {e}")
        sys.exit(1)

### ===========================================================
### Save Credentials into yml file
### ===========================================================
def save_credentials(fw_name, api_key, api_secret):
    user_base_path = os.path.join(base_path, username)
    ensure_directory_exists(user_base_path)
    full_path = os.path.join(user_base_path, f"{fw_name}.yml")

    with open(full_path, "w") as f:
        f.write(f"key: {api_key}\n")
        f.write(f"secret: {api_secret}\n")
    
    os.chmod(full_path, 0o766)
    encrypt_file_with_vault(full_path, fw_name)

### ===========================================================
### Add/update secret keys
### ===========================================================
def add_entry(fw_name):
    user_base_path = os.path.join(base_path, username)
    full_path = os.path.join(user_base_path, f"{fw_name}.yml")

    # If credentials file exists, skip prompt
    if os.path.exists(full_path):
        print(f"Credentials already exist for firewall '{fw_name}' at {full_path}. Skipping input.")
        return

    print(f"Selected Firewall: {fw_name}")
    api_key = input("Enter the API Key   : ").strip()
    api_secret = input("Enter the API Secret: ").strip()
    save_credentials(fw_name, api_key, api_secret)

### ===========================================================
### Check user's Folder contents for secret keys
### ===========================================================
def check_user_folder():
    user_folder = os.path.join(base_path, username)
    if os.path.isdir(user_folder):
        files = os.listdir(user_folder)
        if files:
            print("Current list of FWs with credentials:")
            for file in files:
                print(f"  - {file}")
            return "WithContents"
        else:
            print("The folder is empty.")
            return "FolderEmpty"
    else:
        print("You don't have any key/secret yet. Let's add an entry.")
        return "NoFolder"

### ===========================================================
### Main Script
### ===========================================================
def main():
    global username
    username = get_current_username()
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <firewall_name>")
        sys.exit(1)
    
    fw_name = sys.argv[1].strip()
    check_user_folder()
    add_entry(fw_name)

if __name__ == "__main__":
    main()
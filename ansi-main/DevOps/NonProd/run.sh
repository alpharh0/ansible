#!/bin/bash
set -euo pipefail

# Usage:
#   ./run.sh customer_name project_1 apply fw PAT-AWG rules
#   ./run.sh customer_name project_1 apply router mt1 upgrade

CUSTOMER=${1:-}
PROJECT=${2:-}
ACTION=${3:-apply}
MODULE=${4:-}
TARGET_NAME=${5:-}
TARGET_SECTION=${6:-}

CONFIG_FILE="./config.json"

if [ -z "$CUSTOMER" ] || [ -z "$PROJECT" ] || [ -z "$MODULE" ]; then
  echo "Usage:"
  echo "  $0 <CUSTOMER> <PROJECT> apply fw <FW_NAME> <SECTION>"
  echo "  $0 <CUSTOMER> <PROJECT> apply router <ROUTER_NAME> <SECTION>"
  exit 1
fi

# ----------------------
# Ansible Firewall Runner
# ----------------------
run_ansible_firewall() {
  local FW_NAME=$1
  local FW_SECTION=$2

  echo "Deploying firewall [$FW_NAME] section [$FW_SECTION]"

  local INVENTORY_FILE="/tmp/inventory_${FW_NAME}.ini"

  # Get management IP from config.json
  local FW_IP
  FW_IP=$(jq -r \
    ".\"$CUSTOMER\".\"$PROJECT\".\"conf-opnsense\".\"$FW_NAME\".\"mgmt_ip\"" \
    "$CONFIG_FILE")

  if [ -z "$FW_IP" ] || [ "$FW_IP" = "null" ]; then
    echo "Error: mgmt_ip not found for firewall $FW_NAME"
    exit 1
  fi

  # Generate inventory dynamically
  cat > "$INVENTORY_FILE" <<EOF
[$FW_NAME]
$FW_NAME ansible_host=$FW_IP
EOF

  # Extract firewall section config
  local FW_SECTION_DATA
  FW_SECTION_DATA=$(jq -c \
    ".\"$CUSTOMER\".\"$PROJECT\".\"conf-opnsense\".\"$FW_NAME\".\"$FW_SECTION\"" \
    "$CONFIG_FILE")

  if [ "$FW_SECTION_DATA" = "null" ]; then
    echo "Error: Section $FW_SECTION not found for firewall $FW_NAME"
    rm -f "$INVENTORY_FILE"
    exit 1
  fi

  local ROLE="${FW_SECTION}_add"

  echo "Running Ansible role: $ROLE"

  # Wrap JSON under section key
  local EXTRA_VARS
  EXTRA_VARS=$(jq -nc \
    --argjson data "$FW_SECTION_DATA" \
    --arg section "$FW_SECTION" \
    '{($section): $data}')

  # Optional secret injection
  if [ -f "./add_update_api_key_secrets.py" ]; then
    python3 ./add_update_api_key_secrets.py "$FW_NAME"
  fi

  # Run Ansible
  ansible-playbook \
    -i "$INVENTORY_FILE" \
    /root/Dev/ansi-main/Infrastructure/conf-opnsense/roles/main.yaml \
    --tags "$ROLE" \
    -l "$FW_NAME" \
    -e "username=root" \
    -e "ansible_password=opnsense" \
    --extra-vars "$EXTRA_VARS" \
    --vault-password-file ~/.vault_pass.txt

  rm -f "$INVENTORY_FILE"
}

# ----------------------
# Ansible MikroTik Runner
# ----------------------
run_ansible_router() {
  local ROUTER_NAME=$1
  local ROUTER_SECTION=$2
  local ROLE="$ROUTER_SECTION"

  echo "Deploying router [$ROUTER_NAME] section [$ROUTER_SECTION]"

  local INVENTORY_FILE="/tmp/inventory_${ROUTER_NAME}.ini"

  local ROUTER_IP
  ROUTER_IP=$(jq -r \
    ".\"$CUSTOMER\".\"$PROJECT\".\"conf-mikrotik\".\"$ROUTER_NAME\".\"mgmt_ip\"" \
    "$CONFIG_FILE")

  if [ -z "$ROUTER_IP" ] || [ "$ROUTER_IP" = "null" ]; then
    echo "Error: mgmt_ip not found for router $ROUTER_NAME"
    exit 1
  fi

  cat > "$INVENTORY_FILE" <<EOF
[routers]
$ROUTER_NAME ansible_host=$ROUTER_IP ansible_user=admin ansible_password='Emergency/Pine9'
EOF

  local ROUTER_SECTION_DATA
  ROUTER_SECTION_DATA=$(jq -c \
    ".\"$CUSTOMER\".\"$PROJECT\".\"conf-mikrotik\".\"$ROUTER_NAME\".\"$ROUTER_SECTION\"" \
    "$CONFIG_FILE")

  if [ -z "$ROUTER_SECTION_DATA" ] || [ "$ROUTER_SECTION_DATA" = "null" ]; then
    echo "Error: Section $ROUTER_SECTION not found for router $ROUTER_NAME"
    rm -f "$INVENTORY_FILE"
    exit 1
  fi

  local EXTRA_VARS
  EXTRA_VARS="$ROUTER_SECTION_DATA"

  echo "ROUTER_SECTION_DATA=$ROUTER_SECTION_DATA"
  echo "EXTRA_VARS=$EXTRA_VARS"
  echo "Running Ansible role: $ROLE"

  ansible-playbook \
    -i "$INVENTORY_FILE" \
    /root/Dev/ansi-main/Infrastructure/conf-mikrotik/roles/main.yaml \
    --tags "$ROLE" \
    -l "$ROUTER_NAME" \
    --extra-vars "$EXTRA_VARS"

  rm -f "$INVENTORY_FILE"
}

# ----------------------
# Ansible EdgeRouter Runner
# ----------------------
# run_ansible_edgerouter() {
#   local ROUTER_NAME=$1
#   local ROUTER_SECTION=$2
#   local ROLE="$ROUTER_SECTION"

#   echo "Deploying EdgeRouter [$ROUTER_NAME] section [$ROUTER_SECTION]"

#   local INVENTORY_FILE="/tmp/inventory_${ROUTER_NAME}.ini"

#   local ROUTER_IP
#   ROUTER_IP=$(jq -r \
#     ".\"$CUSTOMER\".\"$PROJECT\".\"conf-edgerouter\".\"$ROUTER_NAME\".\"mgmt_ip\"" \
#     "$CONFIG_FILE")

#   if [ -z "$ROUTER_IP" ] || [ "$ROUTER_IP" = "null" ]; then
#     echo "Error: mgmt_ip not found for router $ROUTER_NAME"
#     exit 1
#   fi

#   cat > "$INVENTORY_FILE" <<EOF
# [edgerouters]
# $ROUTER_NAME ansible_host=$ROUTER_IP ansible_user=admin ansible_password='yourpassword'
# EOF

#   local ROUTER_SECTION_DATA
#   ROUTER_SECTION_DATA=$(jq -c \
#     ".\"$CUSTOMER\".\"$PROJECT\".\"conf-edgerouter\".\"$ROUTER_NAME\".\"$ROUTER_SECTION\"" \
#     "$CONFIG_FILE")

#   if [ -z "$ROUTER_SECTION_DATA" ] || [ "$ROUTER_SECTION_DATA" = "null" ]; then
#     echo "Error: Section $ROUTER_SECTION not found for router $ROUTER_NAME"
#     rm -f "$INVENTORY_FILE"
#     exit 1
#   fi

#   ansible-playbook \
#     -i "$INVENTORY_FILE" \
#     /root/Dev/ansi-main/Infrastructure/conf-edgerouter/roles/main.yaml \
#     --tags "$ROLE" \
#     -l "$ROUTER_NAME" \
#     --extra-vars "$ROUTER_SECTION_DATA"

#   rm -f "$INVENTORY_FILE"
#}

run_ansible_edgerouter() {
  local ROUTER_NAME=$1
  local ROUTER_SECTION=$2

  echo "Deploying EdgeRouter [$ROUTER_NAME] section [$ROUTER_SECTION]"

  local INVENTORY_FILE="/tmp/inventory_${ROUTER_NAME}.ini"

  DEVICES=$(jq -c \
    ".\"$CUSTOMER\".\"$PROJECT\".\"conf_edgerouter\".\"$ROUTER_NAME\".devices[]" \
    "$CONFIG_FILE")

  echo "[edgerouter]" > "$INVENTORY_FILE"

  for DEVICE in $DEVICES; do
    IP=$(echo "$DEVICE" | jq -r '.ip')
    PASS=$(echo "$DEVICE" | jq -r '.password')

    echo "${ROUTER_NAME}_${IP} ansible_host=$IP" >> "$INVENTORY_FILE"
  done

  ROUTER_DATA=$(jq -c \
    ".\"$CUSTOMER\".\"$PROJECT\".\"conf_edgerouter\".\"$ROUTER_NAME\"" \
    "$CONFIG_FILE")

  EXTRA_VARS=$(jq -nc --argjson data "$ROUTER_DATA" '{conf_edgerouter: $data}')

  ansible-playbook \
  -i "$INVENTORY_FILE" \
  -i /root/Dev/ansi-main/DevOps/NonProd/inventory.ini \
  /root/Dev/ansi-main/Infrastructure/conf-edgerouter/roles/main.yaml \
  --tags "$ROUTER_SECTION" \
  -l "${ROUTER_NAME}_*" \
  --extra-vars "$EXTRA_VARS"

  rm -f "$INVENTORY_FILE"
}

# ----------------------
# Execution
# ----------------------
echo "=== Execution: $CUSTOMER / $PROJECT -> $ACTION $MODULE ==="

case "$MODULE" in
  fw)
    if [ -z "$TARGET_NAME" ] || [ -z "$TARGET_SECTION" ]; then
      echo "Usage: $0 $CUSTOMER $PROJECT apply fw <FW_NAME> <SECTION>"
      exit 1
    fi

    run_ansible_firewall "$TARGET_NAME" "$TARGET_SECTION"
    ;;

  router)
    if [ -z "$TARGET_NAME" ] || [ -z "$TARGET_SECTION" ]; then
      echo "Usage: $0 $CUSTOMER $PROJECT apply router <ROUTER_NAME> <SECTION>"
      exit 1
    fi

    run_ansible_router "$TARGET_NAME" "$TARGET_SECTION"
    ;;

  edgerouter)
    if [ -z "$TARGET_NAME" ] || [ -z "$TARGET_SECTION" ]; then
      echo "Usage: $0 $CUSTOMER $PROJECT apply edgerouter <ROUTER_NAME> <SECTION>"
      exit 1
    fi

    run_ansible_edgerouter "$TARGET_NAME" "$TARGET_SECTION"
    ;;

  *)
    echo "Invalid module: $MODULE"
    exit 1
    ;;
esac

echo "Completed configuration"
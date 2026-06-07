#!/bin/bash
# ==============================================================
# Clean Local Workspace Script
# Restores the git repository to its clean state and clears local
# environment configurations and reports to start fresh.
# ==============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# 1. Ask for confirmation before destroying local config files
echo -e "${YELLOW}!!! WARNING !!!${NC}"
echo -e "This script will reset all local changes in the repository and delete local configurations (.env files, report files, etc.)."
read -p "Are you sure you want to clean your local workspace? (y/N): " -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# 2. Reset Git modifications
log "Discarding local git changes..."
if command -v git &>/dev/null; then
    git restore .
    git clean -fd
    log "Git working directory reset successfully."
else
    warn "Git command not found. Skipping git restore."
fi

# 3. Clean environment files
log "Removing local environment configuration files..."
ENV_FILES=(".env" ".env.cloud" ".env.edge" ".env.benchmark" ".env.peersight-local")
for f in "${ENV_FILES[@]}"; do
    if [[ -f "$f" ]]; then
        rm -f "$f"
        log "Removed: $f"
    fi
done

# 4. Clean reports
log "Cleaning generated benchmark reports..."
if [[ -d "benchmark/reports" ]]; then
    rm -rf benchmark/reports/*
    log "Benchmark reports cleared."
fi

# 5. Clean terraform files (with safety checks)
log "Cleaning local Terraform cache..."
# We will NOT delete terraform.tfstate automatically to avoid losing track of AWS resources.
# Warn the user about state files.
if [[ -d "cloud/terraform/ec2/.terraform" ]]; then
    rm -rf "cloud/terraform/ec2/.terraform"
    rm -f "cloud/terraform/ec2/.terraform.lock.hcl"
    rm -f "cloud/terraform/ec2/*.tfplan"
    log "Removed local terraform cache and plans."
fi

if ls cloud/terraform/ec2/terraform.tfstate* &>/dev/null; then
    echo ""
    warn "Active Terraform state files (terraform.tfstate) were found!"
    warn "If you delete these, Terraform will lose track of your deployed AWS resources and you will have to delete them manually on AWS Console."
    read -p "Do you want to delete the Terraform state files as well? (y/N): " -r DEL_STATE
    if [[ "$DEL_STATE" =~ ^[Yy]$ ]]; then
        rm -f cloud/terraform/ec2/terraform.tfstate*
        log "Terraform state files removed."
    else
        log "Kept Terraform state files."
    fi
fi

echo ""
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}  Local Workspace is Clean and Ready!      ${NC}"
echo -e "${GREEN}===========================================${NC}"

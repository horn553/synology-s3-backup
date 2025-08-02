#!/bin/bash

set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly CONFIG_DIR="/volume1/backup-config"
readonly CONFIG_FILE="${CONFIG_DIR}/backup.conf"
readonly LOG_DIR="${CONFIG_DIR}/logs"
readonly AWS_DIR="${HOME}/.aws"
readonly DOCKER_CMD="/usr/local/bin/docker"

log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "${LOG_FILE:-/dev/stdout}"
}

error() {
    log "ERROR" "$@"
    exit 1
}

info() {
    log "INFO" "$@"
}

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file not found: $CONFIG_FILE"
    fi
    
    source "$CONFIG_FILE"
    
    # Set defaults
    COMPRESSION_LEVEL=${COMPRESSION_LEVEL:-6}
    MIN_FREE_SPACE_GB=${MIN_FREE_SPACE_GB:-1500}
    LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-30}
    TEMP_DIR=${TEMP_DIR:-/volume1/backup-temp}
}

ensure_aws_cli() {
    if ! $DOCKER_CMD images amazon/aws-cli --quiet | grep -q .; then
        info "Pulling AWS CLI Docker image..."
        $DOCKER_CMD pull amazon/aws-cli
    fi
}

aws_cli() {
    $DOCKER_CMD run --rm \
        -v "${AWS_DIR}:/root/.aws:ro" \
        -v "/volume1:/volume1" \
        -e AWS_PROFILE="${AWS_PROFILE}" \
        amazon/aws-cli "$@"
}

init_command() {
    info "Starting initialization..."
    
    # Create directories
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$AWS_DIR"
    
    # Create config file if not exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        info "Creating configuration file..."
        cat > "$CONFIG_FILE" << 'EOF'
# AWS Settings
AWS_PROFILE="nas-backup"
AWS_REGION="ap-northeast-1"
S3_BUCKET=""
S3_PREFIX="synology-backup"

# Backup Settings
BACKUP_SOURCE="/var/services/homes"
TEMP_DIR="/volume1/backup-temp"
LOG_DIR="/volume1/backup-config/logs"
LOG_RETENTION_DAYS=30
COMPRESSION_LEVEL="6"
MIN_FREE_SPACE_GB="1500"

# GitHub Settings
GITHUB_REPO="username/synology-s3-backup"
EOF
        chmod 600 "$CONFIG_FILE"
        info "Configuration file created. Please edit: $CONFIG_FILE"
        exit 0
    fi
    
    load_config
    
    # Configure AWS credentials
    if [[ ! -f "${AWS_DIR}/credentials" ]]; then
        info "Configuring AWS credentials..."
        read -p "AWS Access Key ID: " aws_access_key
        read -s -p "AWS Secret Access Key: " aws_secret_key
        echo
        
        mkdir -p "$AWS_DIR"
        cat > "${AWS_DIR}/credentials" << EOF
[${AWS_PROFILE}]
aws_access_key_id = ${aws_access_key}
aws_secret_access_key = ${aws_secret_key}
EOF
        chmod 600 "${AWS_DIR}/credentials"
        
        cat > "${AWS_DIR}/config" << EOF
[profile ${AWS_PROFILE}]
region = ${AWS_REGION}
EOF
        chmod 600 "${AWS_DIR}/config"
    fi
    
    # Create S3 bucket if needed
    if [[ -z "$S3_BUCKET" ]]; then
        read -p "Enter S3 bucket name: " S3_BUCKET
        sed -i "s/^S3_BUCKET=.*/S3_BUCKET=\"${S3_BUCKET}\"/" "$CONFIG_FILE"
    fi
    
    ensure_aws_cli
    
    # Check if bucket exists
    if ! aws_cli s3 ls "s3://${S3_BUCKET}" &>/dev/null; then
        info "Creating S3 bucket: $S3_BUCKET"
        aws_cli s3 mb "s3://${S3_BUCKET}" --region "$AWS_REGION"
    fi
    
    # Set lifecycle policy
    info "Setting lifecycle policy..."
    local lifecycle_policy=$(cat <<EOF
{
  "Rules": [{
    "ID": "synology-backup-auto-delete",
    "Status": "Enabled",
    "Filter": {"Prefix": "${S3_PREFIX}/"},
    "Transitions": [{"Days": 0, "StorageClass": "DEEP_ARCHIVE"}],
    "Expiration": {"Days": 180}
  }]
}
EOF
)
    
    echo "$lifecycle_policy" > /tmp/lifecycle.json
    aws_cli s3api put-bucket-lifecycle-configuration \
        --bucket "$S3_BUCKET" \
        --lifecycle-configuration "file:///tmp/lifecycle.json"
    rm -f /tmp/lifecycle.json
    
    # Test compression performance
    info "Testing compression performance..."
    mkdir -p "$TEMP_DIR"
    dd if=/dev/zero of="${TEMP_DIR}/test_100mb" bs=1M count=100 &>/dev/null
    
    for level in 1 6 9; do
        start_time=$(date +%s)
        tar -czf "${TEMP_DIR}/test_${level}.tar.gz" -C "$TEMP_DIR" test_100mb --gzip-level=$level
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        size=$(ls -lh "${TEMP_DIR}/test_${level}.tar.gz" | awk '{print $5}')
        estimated_2tb=$((duration * 20480 / 100))
        estimated_hours=$((estimated_2tb / 3600))
        info "Level $level: ${duration}s for 100MB, size: $size, estimated for 2TB: ${estimated_hours}h"
        rm -f "${TEMP_DIR}/test_${level}.tar.gz"
    done
    
    rm -f "${TEMP_DIR}/test_100mb"
    
    info "Initialization complete!"
}

verify_setup() {
    load_config
    
    # Check config
    [[ -f "$CONFIG_FILE" ]] || error "Configuration file not found"
    [[ -n "$S3_BUCKET" ]] || error "S3_BUCKET not configured"
    
    # Check AWS credentials
    [[ -f "${AWS_DIR}/credentials" ]] || error "AWS credentials not found"
    
    ensure_aws_cli
    
    # Test AWS connection
    aws_cli sts get-caller-identity &>/dev/null || error "AWS authentication failed"
    
    # Test S3 access
    aws_cli s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" &>/dev/null || error "S3 access failed"
    
    info "Verification passed"
}

backup_command() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    LOG_FILE="${LOG_DIR}/backup-${timestamp}.log"
    
    info "Starting backup..."
    
    # Verify setup first
    verify_setup
    
    # Check free space
    local free_space_gb=$(df -BG "$TEMP_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $free_space_gb -lt $MIN_FREE_SPACE_GB ]]; then
        error "Insufficient free space: ${free_space_gb}GB < ${MIN_FREE_SPACE_GB}GB"
    fi
    
    # Create backup
    local backup_file="${TEMP_DIR}/backup-${timestamp}.tar.gz"
    info "Creating backup archive..."
    tar -czf "$backup_file" -C / "${BACKUP_SOURCE#/}" --gzip-level=$COMPRESSION_LEVEL
    
    local backup_size=$(ls -lh "$backup_file" | awk '{print $5}')
    info "Backup created: $backup_file ($backup_size)"
    
    # Upload to S3
    info "Uploading to S3..."
    aws_cli s3 cp "$backup_file" "s3://${S3_BUCKET}/${S3_PREFIX}/backup-${timestamp}.tar.gz" \
        --storage-class DEEP_ARCHIVE
    
    # Cleanup
    rm -f "$backup_file"
    
    # Rotate logs
    find "$LOG_DIR" -name "backup-*.log" -mtime +$LOG_RETENTION_DAYS -delete
    
    info "Backup completed successfully!"
}

restore_command() {
    local restore_timestamp=$1
    local restore_dir="/volume1/restore"
    
    load_config
    ensure_aws_cli
    
    if [[ -z "$restore_timestamp" ]]; then
        info "Available backups:"
        aws_cli s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | grep "backup-" | awk '{print $4}' | sed 's/backup-//' | sed 's/.tar.gz//'
        exit 0
    fi
    
    local backup_key="${S3_PREFIX}/backup-${restore_timestamp}.tar.gz"
    
    # Check if restore is already in progress
    local restore_status=$(aws_cli s3api head-object \
        --bucket "$S3_BUCKET" \
        --key "$backup_key" \
        --query 'Restore' --output text 2>/dev/null || echo "none")
    
    if [[ "$restore_status" == "none" ]]; then
        info "Initiating Glacier restore (12-48 hours)..."
        aws_cli s3api restore-object \
            --bucket "$S3_BUCKET" \
            --key "$backup_key" \
            --restore-request '{"Days": 7, "GlacierJobParameters": {"Tier": "Bulk"}}'
        info "Restore initiated. Check status later."
        exit 0
    elif [[ "$restore_status" =~ "ongoing-request=\"true\"" ]]; then
        info "Restore is still in progress. Please check later."
        exit 0
    else
        info "Downloading backup..."
        mkdir -p "$restore_dir"
        aws_cli s3 cp "s3://${S3_BUCKET}/${backup_key}" "${restore_dir}/backup-${restore_timestamp}.tar.gz"
        
        info "Extracting backup..."
        tar -xzf "${restore_dir}/backup-${restore_timestamp}.tar.gz" -C "$restore_dir"
        
        info "Restore completed to: $restore_dir"
    fi
}

main() {
    local command=${1:-}
    
    case "$command" in
        init)
            init_command
            ;;
        backup)
            backup_command
            ;;
        restore)
            restore_command "${2:-}"
            ;;
        *)
            echo "Usage: $0 {init|backup|restore [YYYYMMDD-HHMMSS]}"
            exit 1
            ;;
    esac
}

main "$@"
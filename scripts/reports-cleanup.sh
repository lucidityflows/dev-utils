#!/bin/bash

# Reports Cleanup and Retention Management
# Usage: reports-cleanup.sh [--dry-run] [--verbose]

set -euo pipefail

REPORTS_DIR="${REPORTS_DIR:-/home/robert/Reports}"
DRY_RUN=false
VERBOSE=false

# Retention policies (in days)
WEEKLY_RETENTION=90      # Keep 3 months of weekly reports
SECURITY_RETENTION=180   # Keep 6 months of security reports  
PERFORMANCE_RETENTION=60 # Keep 2 months of performance reports
COMPLIANCE_RETENTION=365 # Keep 1 year of compliance reports
INFRASTRUCTURE_RETENTION=90 # Keep 3 months of infrastructure reports

# Parse arguments
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
        --verbose) VERBOSE=true ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

show_help() {
    cat << EOF
Reports Cleanup and Retention Management

Usage: $0 [OPTIONS]

Options:
    --dry-run    Show what would be deleted without actually deleting
    --verbose    Show detailed information about cleanup process
    -h, --help   Show this help message

Retention Policies:
    Weekly reports:        ${WEEKLY_RETENTION} days
    Security reports:      ${SECURITY_RETENTION} days  
    Performance reports:   ${PERFORMANCE_RETENTION} days
    Compliance reports:    ${COMPLIANCE_RETENTION} days
    Infrastructure reports: ${INFRASTRUCTURE_RETENTION} days

Examples:
    $0                # Run cleanup
    $0 --dry-run      # Preview what would be deleted
    $0 --verbose      # Show detailed progress
EOF
}

log_info() { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_warning() { echo "⚠️  $*"; }

cleanup_directory() {
    local dir="$1"
    local retention_days="$2"
    local category="$3"
    
    if [[ ! -d "$dir" ]]; then
        [[ "$VERBOSE" == "true" ]] && log_info "Directory $dir does not exist, skipping"
        return 0
    fi
    
    [[ "$VERBOSE" == "true" ]] && log_info "Cleaning $category reports in $dir (${retention_days} day retention)"
    
    local files_found=0
    local files_deleted=0
    local space_freed=0
    
    while IFS= read -r -d '' file; do
        ((files_found++))
        local file_age_days=$(( ($(date +%s) - $(stat -c %Y "$file")) / 86400 ))
        
        if [[ $file_age_days -gt $retention_days ]]; then
            local file_size=$(stat -c %s "$file" 2>/dev/null || echo 0)
            space_freed=$((space_freed + file_size))
            
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "  [DRY RUN] Would delete: $(basename "$file") (${file_age_days} days old, $(numfmt --to=iec $file_size))"
            else
                [[ "$VERBOSE" == "true" ]] && echo "  Deleting: $(basename "$file") (${file_age_days} days old, $(numfmt --to=iec $file_size))"
                rm "$file"
            fi
            ((files_deleted++))
        elif [[ "$VERBOSE" == "true" ]]; then
            echo "  Keeping: $(basename "$file") (${file_age_days} days old)"
        fi
    done < <(find "$dir" -type f -print0 2>/dev/null)
    
    if [[ $files_found -eq 0 ]]; then
        log_info "$category: No files found"
    elif [[ $files_deleted -eq 0 ]]; then
        log_success "$category: All $files_found files within retention period"
    else
        local action="Would delete"
        [[ "$DRY_RUN" == "false" ]] && action="Deleted"
        log_success "$category: $action $files_deleted of $files_found files ($(numfmt --to=iec $space_freed) freed)"
    fi
}

compress_old_reports() {
    local dir="$1"
    local compress_age_days="$2"
    local category="$3"
    
    if [[ ! -d "$dir" ]]; then
        return 0
    fi
    
    [[ "$VERBOSE" == "true" ]] && log_info "Compressing old $category reports (older than ${compress_age_days} days)"
    
    local files_compressed=0
    local space_saved=0
    
    while IFS= read -r -d '' file; do
        if [[ "$file" == *.gz ]]; then
            continue  # Already compressed
        fi
        
        local file_age_days=$(( ($(date +%s) - $(stat -c %Y "$file")) / 86400 ))
        
        if [[ $file_age_days -gt $compress_age_days ]]; then
            local original_size=$(stat -c %s "$file")
            
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "  [DRY RUN] Would compress: $(basename "$file")"
            else
                gzip "$file"
                local compressed_size=$(stat -c %s "${file}.gz" 2>/dev/null || echo $original_size)
                local saved=$((original_size - compressed_size))
                space_saved=$((space_saved + saved))
                [[ "$VERBOSE" == "true" ]] && echo "  Compressed: $(basename "$file") (saved $(numfmt --to=iec $saved))"
            fi
            ((files_compressed++))
        fi
    done < <(find "$dir" -type f -print0 2>/dev/null)
    
    if [[ $files_compressed -gt 0 ]]; then
        local action="Would compress"
        [[ "$DRY_RUN" == "false" ]] && action="Compressed"
        log_success "$category: $action $files_compressed files ($(numfmt --to=iec $space_saved) saved)"
    fi
}

main() {
    log_info "Starting reports cleanup process"
    [[ "$DRY_RUN" == "true" ]] && log_warning "DRY RUN MODE - No files will be deleted"
    echo
    
    # Show current disk usage
    if [[ -d "$REPORTS_DIR" ]]; then
        local current_usage=$(du -sh "$REPORTS_DIR" | cut -f1)
        log_info "Current reports directory size: $current_usage"
        echo
    fi
    
    # Compress reports older than 30 days (before deletion)
    compress_old_reports "$REPORTS_DIR/weekly" 30 "weekly"
    compress_old_reports "$REPORTS_DIR/security" 30 "security"
    compress_old_reports "$REPORTS_DIR/performance" 30 "performance"
    compress_old_reports "$REPORTS_DIR/infrastructure" 30 "infrastructure"
    echo
    
    # Clean up based on retention policies
    cleanup_directory "$REPORTS_DIR/weekly" "$WEEKLY_RETENTION" "weekly"
    cleanup_directory "$REPORTS_DIR/security" "$SECURITY_RETENTION" "security"
    cleanup_directory "$REPORTS_DIR/performance" "$PERFORMANCE_RETENTION" "performance"
    cleanup_directory "$REPORTS_DIR/compliance" "$COMPLIANCE_RETENTION" "compliance"
    cleanup_directory "$REPORTS_DIR/infrastructure" "$INFRASTRUCTURE_RETENTION" "infrastructure"
    
    echo
    if [[ -d "$REPORTS_DIR" ]]; then
        local final_usage=$(du -sh "$REPORTS_DIR" | cut -f1)
        log_success "Final reports directory size: $final_usage"
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Cleanup completed successfully"
    else
        log_info "Dry run completed - use without --dry-run to perform actual cleanup"
    fi
}

main "$@"
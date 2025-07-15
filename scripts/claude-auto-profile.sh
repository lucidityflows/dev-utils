#!/bin/bash

# Claude Auto-Profile with MCP Discovery and Risk Assessment
# Usage: claude-auto-profile.sh [--mode=suggest|safe|discover] [--project-path=PATH]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
PROFILES_DIR="$CLAUDE_DIR/profiles"
RISK_DB_FILE="$SCRIPT_DIR/mcp-risk-database.json"
PROJECT_PATH="${PWD}"
MODE="suggest"

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        (--mode=*)
            MODE="${arg#*=}"
            shift
            ;;
        (--project-path=*)
            PROJECT_PATH="${arg#*=}"
            shift
            ;;
        (-h|--help)
            show_help
            exit 0
            ;;
        (*)
            echo "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

show_help() {
    cat << EOF
Claude Auto-Profile with MCP Discovery

Usage: $0 [OPTIONS]

Options:
    --mode=MODE         Discovery mode: suggest, safe, discover (default: suggest)
    --project-path=PATH Project directory to analyze (default: current directory)
    -h, --help         Show this help message

Modes:
    suggest    Analyze project, suggest new MCPs with risk scores, log decisions
    safe       Only use existing configured MCPs based on project context
    discover   Auto-install suggested MCPs (use with caution)

Examples:
    $0 --mode=suggest
    $0 --mode=safe --project-path=/path/to/project
    $0 --mode=discover
EOF
}

# Color output functions
red() { echo -e "\033[31m$*\033[0m"; }
green() { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
blue() { echo -e "\033[34m$*\033[0m"; }
cyan() { echo -e "\033[36m$*\033[0m"; }
bold() { echo -e "\033[1m$*\033[0m"; }

log_info() { echo "$(blue "ℹ") $*"; }
log_success() { echo "$(green "✅") $*"; }
log_warning() { echo "$(yellow "⚠") $*"; }
log_error() { echo "$(red "❌") $*"; }

analyze_project_context() {
    local project_path="$1"
    local context=()
    
    cd "$project_path"
    
    # Kubernetes detection
    if find . -name "*.yaml" -o -name "*.yml" | xargs grep -l "kind:\|apiVersion:" 2>/dev/null | head -1 >/dev/null; then
        context+=("kubernetes")
    fi
    
    # Terraform detection
    if find . -name "*.tf" -type f | head -1 >/dev/null 2>&1; then
        context+=("terraform")
    fi
    
    # Docker detection
    if [[ -f "Dockerfile" ]] || [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
        context+=("docker")
    fi
    
    # Node.js detection
    if [[ -f "package.json" ]]; then
        context+=("nodejs")
    fi
    
    # Python detection
    if [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
        context+=("python")
    fi
    
    # Go detection
    if [[ -f "go.mod" ]] || [[ -f "go.sum" ]]; then
        context+=("golang")
    fi
    
    # Data science detection
    if find . -name "*.ipynb" | head -1 >/dev/null 2>&1; then
        context+=("jupyter")
    fi
    
    # Database detection
    if grep -r "mongodb\|postgres\|mysql" . 2>/dev/null | head -1 >/dev/null; then
        context+=("database")
    fi
    
    # Cloud provider detection
    if grep -r "aws\|s3\|ec2" . 2>/dev/null | head -1 >/dev/null; then
        context+=("aws")
    fi
    
    if grep -r "gcp\|bigquery\|cloud\.google" . 2>/dev/null | head -1 >/dev/null; then
        context+=("gcp")
    fi
    
    # Git repository
    if [[ -d ".git" ]]; then
        context+=("git")
    fi
    
    printf '%s\n' "${context[@]}"
}

get_existing_mcps() {
    local existing_mcps=()
    
    if [[ -f "$CLAUDE_DIR/settings.json" ]]; then
        while IFS= read -r mcp; do
            existing_mcps+=("$mcp")
        done < <(jq -r '.mcpServers // {} | keys[]' "$CLAUDE_DIR/settings.json" 2>/dev/null || true)
    fi
    
    printf '%s\n' "${existing_mcps[@]}"
}

suggest_mcps_for_context() {
    local -a context=("$@")
    local suggestions=()
    
    for ctx in "${context[@]}"; do
        case "$ctx" in
            (kubernetes)
                suggestions+=("kubernetes-mcp-server")
                suggestions+=("helm-mcp-server")
                ;;
            (terraform)
                suggestions+=("terraform-mcp-server")
                suggestions+=("terragrunt-mcp-server")
                ;;
            (docker)
                suggestions+=("docker-mcp-server")
                suggestions+=("docker-compose-mcp-server")
                ;;
            
            (nodejs)
                suggestions+=("npm-mcp-server")
                suggestions+=("yarn-mcp-server")
                ;;
            (python)
                suggestions+=("pip-mcp-server")
                suggestions+=("conda-mcp-server")
                ;;
            (golang)
                suggestions+=("go-mcp-server")
                ;;
            (jupyter)
                suggestions+=("jupyter-mcp-server")
                suggestions+=("pandas-mcp-server")
                ;;
            (database)
                suggestions+=("sql-mcp-server")
                suggestions+=("mongodb-mcp-server")
                ;;
            (aws)
                suggestions+=("aws-mcp-server")
                suggestions+=("s3-mcp-server")
                ;;
            (gcp)
                suggestions+=("gcp-mcp-server")
                suggestions+=("bigquery-mcp-server")
                ;;
            (git)
                suggestions+=("github-mcp-server")
                suggestions+=("gitlab-mcp-server")
                ;;
        esac
    done
    
    # Remove duplicates and return
    printf '%s\n' "${suggestions[@]}" | sort -u
}

load_risk_database() {
    if [[ ! -f "$RISK_DB_FILE" ]]; then
        create_risk_database
    fi
    cat "$RISK_DB_FILE"
}

create_risk_database() {
    cat > "$RISK_DB_FILE" << 'EOF'
{
  "mcps": {
    "kubernetes-mcp-server": {
      "risk_score": 2,
      "source": "https://github.com/kubernetes/mcp-server",
      "official": true,
      "github_stars": 2300,
      "requires_credentials": "kubeconfig",
      "privilege_level": "user",
      "network_access": true,
      "install_command": "npm install -g @kubernetes/mcp-server",
      "description": "kubectl operations, pod management, log viewing"
    },
    "terraform-mcp-server": {
      "risk_score": 3,
      "source": "https://github.com/hashicorp/terraform-mcp",
      "official": true,
      "github_stars": 1800,
      "requires_credentials": "terraform auth",
      "privilege_level": "user",
      "network_access": true,
      "install_command": "go install github.com/hashicorp/terraform-mcp@latest",
      "description": "Plan/apply operations, state inspection"
    },
    "docker-mcp-server": {
      "risk_score": 2,
      "source": "https://github.com/docker/mcp-server",
      "official": true,
      "github_stars": 1500,
      "requires_credentials": "docker socket",
      "privilege_level": "user",
      "network_access": false,
      "install_command": "npm install -g @docker/mcp-server",
      "description": "Container management, image operations"
    },
    "github-mcp-server": {
      "risk_score": 1,
      "source": "https://github.com/modelcontextprotocol/server-github",
      "official": true,
      "github_stars": 3200,
      "requires_credentials": "github token",
      "privilege_level": "user",
      "network_access": true,
      "install_command": "npx @modelcontextprotocol/server-github",
      "description": "Repository management, issues, PRs"
    },
    "aws-mcp-server": {
      "risk_score": 4,
      "source": "https://github.com/aws/aws-mcp-server",
      "official": true,
      "github_stars": 890,
      "requires_credentials": "aws credentials",
      "privilege_level": "varies",
      "network_access": true,
      "install_command": "pip install aws-mcp-server",
      "description": "AWS service management, resource operations"
    },
    "bigquery-mcp-server": {
      "risk_score": 3,
      "source": "https://github.com/google-cloud/bigquery-mcp",
      "official": true,
      "github_stars": 670,
      "requires_credentials": "gcp service account",
      "privilege_level": "user",
      "network_access": true,
      "install_command": "pip install google-cloud-bigquery-mcp",
      "description": "BigQuery dataset and query management"
    },
    "jupyter-mcp-server": {
      "risk_score": 2,
      "source": "https://github.com/jupyter/mcp-server",
      "official": true,
      "github_stars": 1200,
      "requires_credentials": "none",
      "privilege_level": "user",
      "network_access": false,
      "install_command": "pip install jupyter-mcp-server",
      "description": "Notebook management, kernel operations"
    },
    "mongodb-mcp-server": {
      "risk_score": 3,
      "source": "https://github.com/mongodb/mcp-server",
      "official": true,
      "github_stars": 580,
      "requires_credentials": "mongodb connection",
      "privilege_level": "user",
      "network_access": true,
      "install_command": "npm install -g @mongodb/mcp-server",
      "description": "Database operations, collection management"
    },
    "helm-mcp-server": {
      "risk_score": 4,
      "source": "https://github.com/helm/mcp-server",
      "official": true,
      "github_stars": 450,
      "requires_credentials": "kubeconfig",
      "privilege_level": "admin",
      "network_access": true,
      "install_command": "helm plugin install https://github.com/helm/mcp-server",
      "description": "Helm chart management, releases"
    },
    "npm-mcp-server": {
      "risk_score": 2,
      "source": "https://github.com/npm/mcp-server",
      "official": true,
      "github_stars": 780,
      "requires_credentials": "npm token",
      "privilege_level": "user",
      "network_access": true,
      "install_command": "npm install -g @npm/mcp-server",
      "description": "Package management, version operations"
    },
    "sql-mcp-server": {
      "risk_score": 5,
      "source": "https://github.com/community/sql-mcp",
      "official": false,
      "github_stars": 320,
      "requires_credentials": "database connections",
      "privilege_level": "varies",
      "network_access": true,
      "install_command": "pip install sql-mcp-server",
      "description": "Generic SQL database operations"
    },
    "vault-mcp-server": {
      "risk_score": 7,
      "source": "https://github.com/third-party/vault-mcp",
      "official": false,
      "github_stars": 89,
      "requires_credentials": "vault admin token",
      "privilege_level": "admin",
      "network_access": true,
      "install_command": "curl -sSL install.vault-mcp.io | bash",
      "description": "Secret management, token operations"
    },
    "prometheus-mcp-server": {
      "risk_score": 5,
      "source": "https://github.com/community/prometheus-mcp",
      "official": false,
      "github_stars": 456,
      "requires_credentials": "prometheus api key",
      "privilege_level": "user",
      "network_access": true,
      "install_command": "docker pull prometheus-mcp:latest",
      "description": "Metrics querying, alert management"
    }
  }
}
EOF
}

get_risk_info() {
    local mcp_name="$1"
    local risk_db="$2"
    
    echo "$risk_db" | jq -r --arg mcp "$mcp_name" '.mcps[$mcp] // empty'
}

format_risk_level() {
    local risk_score="$1"
    
    if [[ $risk_score -le 2 ]]; then
        echo "$(green "LOW")"
    elif [[ $risk_score -le 5 ]]; then
        echo "$(yellow "MEDIUM")"
    elif [[ $risk_score -le 7 ]]; then
        echo "$(red "HIGH")"
    else
        echo "$(red "CRITICAL")"
    fi
}

display_mcp_suggestion() {
    local mcp_name="$1"
    local risk_info="$2"
    local reason="$3"
    
    if [[ -z "$risk_info" ]]; then
        log_warning "Unknown MCP: $mcp_name (not in risk database)"
        return 1
    fi
    
    local risk_score=$(echo "$risk_info" | jq -r '.risk_score')
    local source=$(echo "$risk_info" | jq -r '.source')
    local description=$(echo "$risk_info" | jq -r '.description')
    local install_cmd=$(echo "$risk_info" | jq -r '.install_command')
    local requires_creds=$(echo "$risk_info" | jq -r '.requires_credentials')
    local official=$(echo "$risk_info" | jq -r '.official')
    local stars=$(echo "$risk_info" | jq -r '.github_stars')
    
    local risk_level=$(format_risk_level "$risk_score")
    local official_badge=""
    [[ "$official" == "true" ]] && official_badge="$(green "Official")" || official_badge="$(yellow "Community")"
    
    echo
    echo "$(bold "[RISK: $risk_score/10 - $risk_level]") $(cyan "$mcp_name")"
    echo "├── $(bold "Why:") $reason"
    echo "├── $(bold "Function:") $description"
    echo "├── $(bold "Source:") $source ($official_badge, $stars stars)"
    echo "├── $(bold "Credentials:") $requires_creds"
    echo "└── $(bold "Install:") $install_cmd"
    
    return 0
}

interactive_selection() {
    local -a suggestions=("$@")
    local -a approved=()
    local -a rejected=()
    local risk_db
    
    risk_db=$(load_risk_database)
    
    echo
    echo "$(bold "Continue?") [y]es/[n]o/[s]elective: "
    read -r choice
    
    case "$choice" in
        y|Y|yes|Yes)
            approved=("${suggestions[@]}")
            ;;
        n|N|no|No)
            rejected=("${suggestions[@]}")
            ;;
        s|S|selective|Selective)
            echo
            echo "$(bold "Select MCPs to install:")"
            for mcp in "${suggestions[@]}"; do
                local risk_info
                risk_info=$(get_risk_info "$mcp" "$risk_db")
                local risk_score=$(echo "$risk_info" | jq -r '.risk_score // 0')
                
                echo -n "$(cyan "[$mcp]") (Risk: $risk_score/10) - Install? [y/n]: "
                read -r install_choice
                
                case "$install_choice" in
                    y|Y|yes|Yes)
                        approved+=("$mcp")
                        ;;
                    *)
                        rejected+=("$mcp")
                        ;;
                esac
            done
            ;;
        *)
            echo "Invalid choice. Exiting."
            exit 1
            ;;
    esac
    
    # Return results via global arrays
    printf '%s\n' "${approved[@]}" > /tmp/mcp_approved.txt
    printf '%s\n' "${rejected[@]}" > /tmp/mcp_rejected.txt
}

log_session_to_readme() {
    local project_path="$1"
    local -a context=("${!2}")
    local -a existing=("${!3}")
    local -a approved=("${!4}")
    local -a rejected=("${!5}")
    local risk_db="$6"
    
    local readme_file="$project_path/README.md"
    local timestamp=$(date -Iseconds)
    local session_id=$(date +%Y%m%d_%H%M%S)
    
    # Create README.md if it doesn't exist
    if [[ ! -f "$readme_file" ]]; then
        echo "# $(basename "$project_path")" > "$readme_file"
        echo >> "$readme_file"
    fi
    
    # Check if MCP Discovery Log section exists
    if ! grep -q "## MCP Discovery Log" "$readme_file"; then
        echo >> "$readme_file"
        echo "## MCP Discovery Log" >> "$readme_file"
        echo >> "$readme_file"
    fi
    
    # Append new session
    {
        echo "### Session: $timestamp"
        echo "**Project:** $(basename "$project_path")"
        echo "**Context:** $(IFS=', '; echo "${context[*]}")"
        echo
        
        if [[ ${#existing[@]} -gt 0 ]]; then
            echo "#### Existing MCPs (loaded):"
            for mcp in "${existing[@]}"; do
                echo "- ✅ \`$mcp\` (already configured)"
            done
            echo
        fi
        
        if [[ ${#approved[@]} -gt 0 ]]; then
            echo "#### MCPs Added:"
            for mcp in "${approved[@]}"; do
                local risk_info
                risk_info=$(get_risk_info "$mcp" "$risk_db")
                local risk_score=$(echo "$risk_info" | jq -r '.risk_score // 0')
                local description=$(echo "$risk_info" | jq -r '.description // "No description"')
                echo "- ✅ \`$mcp\` (Risk: $risk_score/10) - $description"
            done
            echo
        fi
        
        if [[ ${#rejected[@]} -gt 0 ]]; then
            echo "#### MCPs Rejected:"
            for mcp in "${rejected[@]}"; do
                local risk_info
                risk_info=$(get_risk_info "$mcp" "$risk_db")
                local risk_score=$(echo "$risk_info" | jq -r '.risk_score // 0')
                local description=$(echo "$risk_info" | jq -r '.description // "No description"')
                echo "- ❌ \`$mcp\` (Risk: $risk_score/10) - $description"
            done
            echo
        fi
        
        echo "#### Rationale:"
        if [[ ${#approved[@]} -gt 0 ]]; then
            echo "Added $([ ${#approved[@]} -eq 1 ] && echo "low-risk tool" || echo "tools") for enhanced project workflow."
        fi
        if [[ ${#rejected[@]} -gt 0 ]]; then
            echo "Rejected higher-risk or unnecessary tools pending review."
        fi
        if [[ ${#approved[@]} -eq 0 && ${#rejected[@]} -eq 0 ]]; then
            echo "No new MCPs suggested - existing configuration sufficient."
        fi
        echo
        echo "---"
        echo
    } >> "$readme_file"
    
    log_success "Session logged to $(cyan "$readme_file")"
}

create_temporary_profile() {
    local session_id="$1"
    local -a existing=("${!2}")
    local -a approved=("${!3}")
    local risk_db="$4"
    
    local temp_profile="$PROFILES_DIR/auto-${session_id}.json"
    local all_mcps=()
    all_mcps+=("${existing[@]}")
    all_mcps+=("${approved[@]}")
    
    # Create profile JSON
    {
        echo "{"
        echo "  \"profile\": \"auto-$session_id\","
        echo "  \"description\": \"Auto-generated profile from discovery session\","
        echo "  \"mcpServers\": {"
        
        local first=true
        for mcp in "${all_mcps[@]}"; do
            [[ "$first" == "true" ]] && first=false || echo ","
            
            if [[ " ${existing[*]} " =~ " $mcp " ]]; then
                # Use existing configuration
                echo -n "    \"$mcp\": $(jq --arg mcp "$mcp" '.mcpServers[$mcp] // {"command": "echo", "args": ["MCP not configured"]}' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo '{"command": "echo", "args": ["MCP not configured"]}')"
            else
                # Create basic configuration for approved MCP
                local risk_info
                risk_info=$(get_risk_info "$mcp" "$risk_db")
                local install_cmd=$(echo "$risk_info" | jq -r '.install_command // "echo MCP not found"')
                
                echo -n "    \"$mcp\": {"
                echo -n "\"command\": \"echo\", \"args\": [\"Install first: $install_cmd\"], \"disabled\": true"
                echo -n "}"
            fi
        done
        echo
        echo "  },"
        echo "  \"settings\": {"
        echo "    \"maxConcurrentMCPs\": ${#all_mcps[@]},"
        echo "    \"mcpTimeout\": 30000,"
        echo "    \"enableLogging\": true"
        echo "  }"
        echo "}"
    } > "$temp_profile"
    
    echo "$temp_profile"
}

main() {
    local project_context
    local existing_mcps
    local suggested_mcps
    local risk_db
    
    # Ensure required directories exist
    mkdir -p "$PROFILES_DIR"
    
    # Display project info
    log_info "Analyzing project: $(cyan "$PROJECT_PATH")"
    echo
    echo "$(bold "📁 Project Context Detected:")"
    
    # Analyze project
    mapfile -t project_context < <(analyze_project_context "$PROJECT_PATH")
    
    # Display detected technologies
    if [[ ${#project_context[@]} -gt 0 ]]; then
        for i in "${!project_context[@]}"; do
            local prefix="├──"
            [[ $i -eq $((${#project_context[@]} - 1)) ]] && prefix="└──"
            
            case "${project_context[$i]}" in
                kubernetes) echo "$prefix Kubernetes manifests (.yaml files with k8s resources)" ;;
                terraform) echo "$prefix Terraform files (*.tf)" ;;
                docker) echo "$prefix Docker configuration (Dockerfile/docker-compose)" ;;
                nodejs) echo "$prefix Node.js application (package.json)" ;;
                python) echo "$prefix Python application (requirements.txt/pyproject.toml)" ;;
                golang) echo "$prefix Go application (go.mod)" ;;
                jupyter) echo "$prefix Jupyter notebooks (*.ipynb)" ;;
                database) echo "$prefix Database references found" ;;
                aws) echo "$prefix AWS references found" ;;
                gcp) echo "$prefix Google Cloud references found" ;;
                git) echo "$prefix Git repository (.git/)" ;;
                *) echo "$prefix ${project_context[$i]}" ;;
            esac
        done
    else
        echo "└── No specific technologies detected"
    fi
    echo
    
    # Get existing MCPs
    mapfile -t existing_mcps < <(get_existing_mcps)
    
    # Show existing MCPs
    echo "$(bold "✅ EXISTING MCPs (will be loaded):")"
    if [[ ${#existing_mcps[@]} -gt 0 ]]; then
        for mcp in "${existing_mcps[@]}"; do
            echo "├── $mcp (already configured)"
        done
    else
        echo "├── (none configured)"
    fi
    echo
    
    # Get suggestions based on context
    mapfile -t suggested_mcps < <(suggest_mcps_for_context "${project_context[@]}")
    
    # Remove existing MCPs from suggestions
    local -a new_suggestions=()
    for suggestion in "${suggested_mcps[@]}"; do
        if [[ ! " ${existing_mcps[*]} " =~ " $suggestion " ]]; then
            new_suggestions+=("$suggestion")
        fi
    done
    
    if [[ ${#new_suggestions[@]} -eq 0 ]]; then
        log_success "No new MCPs suggested - existing configuration covers detected technologies"
        exit 0
    fi
    
    # Load risk database
    risk_db=$(load_risk_database)
    
    # Display suggestions
    echo "$(bold "💡 SUGGESTED MCPs:")"
    
    local suggestions_shown=0
    for mcp in "${new_suggestions[@]}"; do
        local risk_info
        risk_info=$(get_risk_info "$mcp" "$risk_db")
        
        if [[ -n "$risk_info" ]]; then
            local detected_techs=""
            for tech in "${project_context[@]}"; do
                [[ -n "$detected_techs" ]] && detected_techs+=", "
                detected_techs+="$tech"
            done
            local reason="Detected $detected_techs in project"
            display_mcp_suggestion "$mcp" "$risk_info" "$reason"
            ((suggestions_shown++))
        fi
    done
    
    if [[ $suggestions_shown -eq 0 ]]; then
        log_warning "No valid suggestions found in risk database"
        exit 0
    fi
    
    # Handle different modes
    case "$MODE" in
        suggest)
            interactive_selection "${new_suggestions[@]}"
            
            # Read results
            local -a approved=()
            local -a rejected=()
            [[ -f /tmp/mcp_approved.txt ]] && mapfile -t approved < /tmp/mcp_approved.txt
            [[ -f /tmp/mcp_rejected.txt ]] && mapfile -t rejected < /tmp/mcp_rejected.txt
            
            # Log session
            log_session_to_readme "$PROJECT_PATH" project_context[@] existing_mcps[@] approved[@] rejected[@] "$risk_db"
            
            # Create temporary profile if approved MCPs exist
            if [[ ${#approved[@]} -gt 0 ]]; then
                local session_id=$(date +%Y%m%d_%H%M%S)
                local temp_profile
                temp_profile=$(create_temporary_profile "$session_id" existing_mcps[@] approved[@] "$risk_db")
                
                echo
                log_info "Temporary profile created: $(cyan "$temp_profile")"
                log_warning "Install approved MCPs manually, then load profile with:"
                echo "  $(cyan "cp $temp_profile $CLAUDE_DIR/settings.json")"
            fi
            
            # Cleanup
            rm -f /tmp/mcp_approved.txt /tmp/mcp_rejected.txt
            ;;
        safe)
            log_info "Safe mode: Using only existing MCPs"
            # Could implement profile selection logic here
            ;;
        discover)
            log_warning "Discover mode not implemented - would auto-install MCPs"
            log_warning "Use suggest mode for safer operation"
            ;;
    esac
}

# Run main function
main "$@"
#!/bin/bash

# Weekly MCP Recommendation Report Generator
# Usage: weekly-mcp-report.sh [--scan-path=PATH] [--output=FILE]
#
# This script scans git repositories and generates a weekly report section
# recommending MCP (Model Context Protocol) servers for development workflows.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
RISK_DB_FILE="$SCRIPT_DIR/mcp-risk-database.json"
SCAN_PATH="$HOME"
OUTPUT_FILE=""
REPORT_DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Use centralized reporting directory from environment variable
REPORTS_DIR="${REPORTS_DIR:-/home/robert/Reports}"
DEFAULT_OUTPUT_FILE="$REPORTS_DIR/weekly/mcp-recommendations-$(date +%Y-%m-%d).txt"

# Configuration for report size management
MAX_REPOS_PER_REPORT=50           # Limit repos to prevent huge reports
MAX_DESCRIPTION_LENGTH=120        # Truncate long descriptions
CLEANUP_OLD_REPORTS=true          # Auto-cleanup old reports

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --scan-path=*)
            SCAN_PATH="${arg#*=}"
            shift
            ;;
        --output=*)
            OUTPUT_FILE="${arg#*=}"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

show_help() {
    cat << EOF
Weekly MCP Recommendation Report Generator

Usage: $0 [OPTIONS]

Options:
    --scan-path=PATH   Directory to scan for git repositories (default: $HOME)
    --output=FILE      Output file (default: $DEFAULT_OUTPUT_FILE)
    -h, --help         Show this help message

Examples:
    $0                                    # Uses default centralized location
    $0 --scan-path=/home/user/projects    # Custom scan path
    $0 --output=custom-report.txt         # Custom output file

Default output location: $DEFAULT_OUTPUT_FILE
Centralized reports directory: $REPORTS_DIR
EOF
}

# Find all git repositories
find_git_repositories() {
    local scan_path="$1"
    find "$scan_path" -type d -name ".git" 2>/dev/null | while read -r git_dir; do
        dirname "$git_dir"
    done | sort
}

# Get repository description from README or repo name
get_repo_description() {
    local repo_path="$1"
    local repo_name=$(basename "$repo_path")
    
    # Look for description in README files
    local readme_file=""
    for readme in "$repo_path/README.md" "$repo_path/README.txt" "$repo_path/readme.md"; do
        if [[ -f "$readme" ]]; then
            readme_file="$readme"
            break
        fi
    done
    
    if [[ -n "$readme_file" ]]; then
        # Extract first paragraph or heading
        local description=$(head -20 "$readme_file" | grep -E "^[^#]" | head -3 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-120)
        if [[ ${#description} -gt 20 ]]; then
            echo "$description..."
            return
        fi
    fi
    
    # Check package.json for description
    if [[ -f "$repo_path/package.json" ]]; then
        local desc=$(jq -r '.description // empty' "$repo_path/package.json" 2>/dev/null)
        if [[ -n "$desc" && "$desc" != "null" ]]; then
            echo "$desc"
            return
        fi
    fi
    
    # Check pyproject.toml for description
    if [[ -f "$repo_path/pyproject.toml" ]]; then
        local desc=$(grep -E "^description\s*=" "$repo_path/pyproject.toml" 2>/dev/null | cut -d'"' -f2)
        if [[ -n "$desc" ]]; then
            echo "$desc"
            return
        fi
    fi
    
    # Fallback to repository name analysis
    case "$repo_name" in
        *web*|*site*|*frontend*) echo "Web application or frontend project" ;;
        *api*|*backend*|*server*) echo "API or backend service" ;;
        *cli*|*tool*) echo "Command-line tool or utility" ;;
        *lib*|*package*) echo "Library or package" ;;
        *config*|*dotfiles*) echo "Configuration files and settings" ;;
        *docker*|*k8s*|*kubernetes*) echo "Container orchestration project" ;;
        *terraform*|*infra*) echo "Infrastructure as code project" ;;
        *data*|*ml*|*ai*) echo "Data science or machine learning project" ;;
        *) echo "Development project" ;;
    esac
}

# Analyze project context (simplified version)
analyze_project_context() {
    local project_path="$1"
    local context=()
    
    cd "$project_path"
    
    # Technology detection
    [[ -f "package.json" ]] && context+=("nodejs")
    [[ -f "requirements.txt" || -f "pyproject.toml" || -f "setup.py" ]] && context+=("python")
    [[ -f "go.mod" || -f "go.sum" ]] && context+=("golang")
    [[ -f "Dockerfile" || -f "docker-compose.yml" || -f "docker-compose.yaml" ]] && context+=("docker")
    find . -name "*.tf" -type f | head -1 >/dev/null 2>&1 && context+=("terraform")
    find . -name "*.yaml" -o -name "*.yml" | xargs grep -l "kind:\|apiVersion:" 2>/dev/null | head -1 >/dev/null && context+=("kubernetes")
    find . -name "*.ipynb" | head -1 >/dev/null 2>&1 && context+=("jupyter")
    grep -r "mongodb\|postgres\|mysql" . 2>/dev/null | head -1 >/dev/null && context+=("database")
    grep -r "aws\|s3\|ec2" . 2>/dev/null | head -1 >/dev/null && context+=("aws")
    grep -r "gcp\|bigquery\|cloud\.google" . 2>/dev/null | head -1 >/dev/null && context+=("gcp")
    [[ -d ".git" ]] && context+=("git")
    
    printf '%s\n' "${context[@]}"
}

# Get existing MCPs
get_existing_mcps() {
    local existing_mcps=()
    
    if [[ -f "$CLAUDE_DIR/settings.json" ]]; then
        while IFS= read -r mcp; do
            existing_mcps+=("$mcp")
        done < <(jq -r '.mcpServers // {} | keys[]' "$CLAUDE_DIR/settings.json" 2>/dev/null || true)
    fi
    
    printf '%s\n' "${existing_mcps[@]}"
}

# Suggest MCPs based on context
suggest_mcps_for_context() {
    local -a context=("$@")
    local suggestions=()
    
    for ctx in "${context[@]}"; do
        case "$ctx" in
            kubernetes) suggestions+=("kubernetes-mcp-server" "helm-mcp-server") ;;
            terraform) suggestions+=("terraform-mcp-server") ;;
            docker) suggestions+=("docker-mcp-server") ;;
            nodejs) suggestions+=("npm-mcp-server") ;;
            python) suggestions+=("pip-mcp-server") ;;
            golang) suggestions+=("go-mcp-server") ;;
            jupyter) suggestions+=("jupyter-mcp-server") ;;
            database) suggestions+=("sql-mcp-server" "mongodb-mcp-server") ;;
            aws) suggestions+=("aws-mcp-server") ;;
            gcp) suggestions+=("gcp-mcp-server" "bigquery-mcp-server") ;;
            git) suggestions+=("github-mcp-server") ;;
        esac
    done
    
    printf '%s\n' "${suggestions[@]}" | sort -u
}

# Load risk database
load_risk_database() {
    if [[ ! -f "$RISK_DB_FILE" ]]; then
        create_risk_database
    fi
    cat "$RISK_DB_FILE"
}

# Create risk database (simplified version)
create_risk_database() {
    cat > "$RISK_DB_FILE" << 'EOF'
{
  "mcps": {
    "kubernetes-mcp-server": { "risk_score": 2, "description": "kubectl operations, pod management" },
    "terraform-mcp-server": { "risk_score": 3, "description": "Plan/apply operations, state inspection" },
    "docker-mcp-server": { "risk_score": 2, "description": "Container management, image operations" },
    "github-mcp-server": { "risk_score": 1, "description": "Repository management, issues, PRs" },
    "aws-mcp-server": { "risk_score": 4, "description": "AWS service management" },
    "bigquery-mcp-server": { "risk_score": 3, "description": "BigQuery dataset and query management" },
    "jupyter-mcp-server": { "risk_score": 2, "description": "Notebook management, kernel operations" },
    "mongodb-mcp-server": { "risk_score": 3, "description": "Database operations, collection management" },
    "helm-mcp-server": { "risk_score": 4, "description": "Helm chart management, releases" },
    "npm-mcp-server": { "risk_score": 2, "description": "Package management, version operations" },
    "sql-mcp-server": { "risk_score": 5, "description": "Generic SQL database operations" },
    "gcp-mcp-server": { "risk_score": 4, "description": "Google Cloud Platform service management" },
    "go-mcp-server": { "risk_score": 2, "description": "Go module and build management" },
    "pip-mcp-server": { "risk_score": 2, "description": "Python package management" }
  }
}
EOF
}

# Get risk info for MCP
get_risk_info() {
    local mcp_name="$1"
    local risk_db="$2"
    
    echo "$risk_db" | jq -r --arg mcp "$mcp_name" '.mcps[$mcp] // empty'
}

# Generate report section
generate_report() {
    local repos=()
    mapfile -t repos < <(find_git_repositories "$SCAN_PATH")
    
    cat << EOF
## Weekly MCP Recommendations Report
**Generated:** $REPORT_DATE  
**Repositories Scanned:** ${#repos[@]}

### Summary
This automated scan evaluates git repositories for potential MCP (Model Context Protocol) server integrations that could enhance development workflows with Claude Code.

### Repository Analysis

EOF

    local existing_mcps=()
    mapfile -t existing_mcps < <(get_existing_mcps)
    local risk_db
    risk_db=$(load_risk_database)
    
    local repos_with_recommendations=0
    local total_recommendations=0
    
    for repo in "${repos[@]}"; do
        # Skip if not accessible
        [[ ! -r "$repo" ]] && continue
        
        local repo_name=$(basename "$repo")
        local description
        description=$(get_repo_description "$repo")
        
        echo "#### $repo_name"
        echo "**Path:** \`$repo\`  "
        echo "**Description:** $description"
        echo
        
        # Analyze the repository
        local project_context=()
        mapfile -t project_context < <(analyze_project_context "$repo")
        
        # Get suggestions
        local suggested_mcps=()
        mapfile -t suggested_mcps < <(suggest_mcps_for_context "${project_context[@]}")
        
        # Remove existing MCPs from suggestions
        local new_suggestions=()
        for suggestion in "${suggested_mcps[@]}"; do
            if [[ ! " ${existing_mcps[*]} " =~ " $suggestion " ]]; then
                new_suggestions+=("$suggestion")
            fi
        done
        
        if [[ ${#new_suggestions[@]} -gt 0 ]]; then
            echo "**Recommendations:** ${#new_suggestions[@]} new MCP(s) suggested"
            ((repos_with_recommendations++))
            
            for mcp in "${new_suggestions[@]}"; do
                local risk_info
                risk_info=$(get_risk_info "$mcp" "$risk_db")
                
                if [[ -n "$risk_info" ]]; then
                    local risk_score=$(echo "$risk_info" | jq -r '.risk_score // 0')
                    local description=$(echo "$risk_info" | jq -r '.description // "No description"')
                    
                    local risk_level="LOW"
                    [[ $risk_score -gt 2 && $risk_score -le 5 ]] && risk_level="MEDIUM"
                    [[ $risk_score -gt 5 ]] && risk_level="HIGH"
                    
                    echo "- **$mcp** (Risk: $risk_score/10 - $risk_level): $description"
                    ((total_recommendations++))
                fi
            done
            
            echo "**Reasoning:** Detected ${project_context[*]} technologies that could benefit from enhanced tooling integration."
        else
            echo "**Recommendations:** No new MCPs suggested - current configuration appears sufficient"
        fi
        
        echo
    done
    
    cat << EOF

### Week Ahead Action Items
- **Repositories requiring MCP updates:** $repos_with_recommendations
- **Total MCP recommendations:** $total_recommendations
- **Recommended priority:** Review LOW and MEDIUM risk MCPs first
- **Next review:** $(date -d '+7 days' '+%Y-%m-%d')

EOF
}

# Main execution
main() {
    # Ensure centralized reporting directories exist
    mkdir -p "$REPORTS_DIR"/{weekly,security,performance,compliance,infrastructure}
    
    local report_content
    report_content=$(generate_report)
    
    # Use default output file if none specified
    local output_file="${OUTPUT_FILE:-$DEFAULT_OUTPUT_FILE}"
    
    if [[ "$output_file" != "/dev/stdout" ]]; then
        # Ensure output directory exists
        mkdir -p "$(dirname "$output_file")"
        echo "$report_content" > "$output_file"
        echo "Report written to: $output_file"
        echo "Centralized reports location: $REPORTS_DIR"
    else
        echo "$report_content"
    fi
}

# Run main function
main "$@"
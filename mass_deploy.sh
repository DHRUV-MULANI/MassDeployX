#!/bin/bash

# =================================================================
# MASS DEPLOY - Ultra Master Company AI Deployer
# =================================================================

GITHUB_USER="DM-Mulani-963"
ROOT_DIR=$(pwd)
ARCHIVE_PATH="$HOME/Main-Root-Archive"
ARCHIVE_REPO="Main-Root-Archive"
INDEX_FILE="$ARCHIVE_PATH/README.md"
SIZE_LIMIT="+50M"

# Setup Gemini API Key
export GEMINI_API_KEY="GEMINI_API"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Defaults
REPO_VISIBILITY="private"
FORCE_PUSH=true
MOVE_LARGE=true
CLEAN_NESTED=true
SYNC_ARCHIVE=true
DRY_RUN=false

# AI Generation Defaults
AI_NAME_MODE="auto"
AI_DESC_MODE="auto"
AI_README_MODE="auto"

# =================================================================
# THE ULTRA MASTER COMPANY PERSONA
# =================================================================
COMPANY_PERSONA=$(cat <<'EOF'
You are not a single AI assistant. You are the complete executive board, engineering division, security division, design division, product division, finance division, operations division, marketing division, branding division, and growth division of a world-class technology company. 

You operate as a unified team with one goal: Build, improve, analyze, design, secure, market, scale, and manage this company at the highest professional standard possible.

CRITICAL RULES:
- Everything must be precise, professional, data-driven, investor-grade, and LinkedIn-friendly.
- Be catchy for the public. Market-ready. No generic fluff.
EOF
)

print_banner() {
    echo -e "${MAGENTA}${BOLD}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║  MASS DEPLOY - Ultra Master Company Edition  ║"
    echo "  ║            by $GITHUB_USER               ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_sep() {
    echo -e "${CYAN}────────────────────────────────────────────────${NC}"
}

generate_smart_ignore() {
    cat <<'EOT' > .gitignore
node_modules/
.npm/
venv/
.venv/
__pycache__/
.env
*.log
bin/
obj/
.DS_Store
*.pyc
EOT
}

# =================================================================
# PRE-FLIGHT CHECKS
# =================================================================
preflight_check() {
    local fail=0
    echo -e "${BOLD}Pre-flight checks...${NC}"
    for cmd in git gh jq curl; do
        if command -v "$cmd" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $cmd"
        else
            echo -e "  ${RED}✗${NC} $cmd not found"
            fail=1
        fi
    done
    if ! gh auth status &>/dev/null; then
        echo -e "  ${RED}✗${NC} GitHub not authenticated (run: gh auth login)"
        fail=1
    else
        echo -e "  ${GREEN}✓${NC} GitHub authenticated"
    fi
    
    [ "$fail" -eq 1 ] && { echo -e "\n${RED}Fix issues above first.${NC}"; exit 1; }
    echo ""
}

# =================================================================
# AI ENGINE (With Exponential Backoff)
# =================================================================
ask_gemini() {
    local system_prompt="$1"
    local user_context="$2"
    local max_retries=3
    local retry_delay=5
    local attempt=1
    
    local payload
    payload=$(jq -n --arg txt "$system_prompt\n\nContext:\n$user_context" '{"contents":[{"parts":[{"text":$txt}]}]}')
    
    while [ $attempt -le $max_retries ]; do
        local response
        response=$(curl -s -X POST -H "Content-Type: application/json" \
            -d "$payload" \
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=$GEMINI_API_KEY")
        
        local result
        result=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty')
        
        if [ -n "$result" ]; then
            echo "$result"
            return 0
        fi
        
        local api_error
        api_error=$(echo "$response" | jq -r '.error.message // "Unknown API Error"')
        
        echo -e "  ${YELLOW}⚠ API Error (Attempt $attempt/$max_retries): $api_error${NC}" >&2
        
        if [ $attempt -lt $max_retries ]; then
            echo -e "  ${CYAN}⏳ Retrying in $retry_delay seconds...${NC}" >&2
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))
            ((attempt++))
        else
            echo -e "  ${RED}✗ Max retries reached. Using fallback.${NC}" >&2
            echo "system-error-fallback"
            return 1
        fi
    done
}

get_repo_context() {
    local structure
    structure=$(ls -1 --group-directories-first | head -n 15)
    
    local file_content=""
    local count=0
    while IFS= read -r f; do
        [ "$count" -ge 7 ] && break
        file_content+="\n--- FILE: $f ---\n"
        file_content+=$(head -n 25 "$f")
        ((count++))
    done < <(find . -maxdepth 2 -type f \( -name "*.md" -o -name "*.html" -o -name "*.js" -o -name "*.py" -o -name "*.json" -o -name "*.php" -o -name "*.sh" \) ! -path "*/node_modules/*" ! -path "*/.*" 2>/dev/null)

    echo -e "Structure:\n$structure\n\nSnippets:$file_content"
}

# =================================================================
# MENUS
# =================================================================
select_directories() {
    local all_dirs=()
    for d in */; do
        [[ "$(realpath "$d")" == "$ARCHIVE_PATH" ]] && continue
        [[ "$d" == "node_modules/" ]] && continue
        all_dirs+=("${d%/}")
    done
    if [ ${#all_dirs[@]} -eq 0 ]; then
        echo -e "${RED}No subdirectories found.${NC}"; exit 1
    fi

    echo -e "${BOLD}Which directories to push?${NC}"
    print_sep
    for i in "${!all_dirs[@]}"; do
        printf "  ${CYAN}%2d)${NC} %s\n" $((i+1)) "${all_dirs[$i]}"
    done
    echo -e "  ${GREEN} A)${NC} All directories"
    echo -e "  ${RED} Q)${NC} Quit"
    print_sep
    read -rp "Select (space-separated numbers, A=all, Q=quit): " choice

    [[ "$choice" =~ ^[Qq]$ ]] && { echo "Bye."; exit 0; }

    DIRS_TO_PROCESS=()
    if [[ "$choice" =~ ^[Aa]$ ]]; then
        for d in "${all_dirs[@]}"; do DIRS_TO_PROCESS+=("$d/"); done
        echo -e "${GREEN}→ All ${#all_dirs[@]} directories selected${NC}"
    else
        for n in $choice; do
            if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#all_dirs[@]} ]; then
                DIRS_TO_PROCESS+=("${all_dirs[$((n-1))]}/")
            else
                echo -e "${YELLOW}Skipping invalid: $n${NC}"
            fi
        done
        [ ${#DIRS_TO_PROCESS[@]} -eq 0 ] && { echo -e "${RED}Nothing selected.${NC}"; exit 1; }
    fi
}

select_visibility() {
    echo -e "\n${BOLD}Repository visibility:${NC}"
    print_sep
    echo -e "  ${CYAN}1)${NC} Private (default)"
    echo -e "  ${CYAN}2)${NC} Public"
    echo -e "  ${CYAN}3)${NC} Ask for each repo individually"
    print_sep
    read -rp "Choose [1/2/3]: " vis
    case "$vis" in
        2) REPO_VISIBILITY="public" ;;
        3) REPO_VISIBILITY="ask" ;;
        *) REPO_VISIBILITY="private" ;;
    esac
}

select_ai_options() {
    echo -e "\n${BOLD}AI Generation Preferences:${NC}"
    print_sep
    
    read -rp "  1. Generate Repo Names using AI? [Y/n] (Manual uses folder name): " opt
    AI_NAME_MODE=$([[ "$opt" =~ ^[Nn]$ ]] && echo "manual" || echo "auto")

    read -rp "  2. Generate Descriptions using AI? [Y/n] (Manual asks for input): " opt
    AI_DESC_MODE=$([[ "$opt" =~ ^[Nn]$ ]] && echo "manual" || echo "auto")

    read -rp "  3. Generate missing README.md using AI? [Y/n] (Manual skips): " opt
    AI_README_MODE=$([[ "$opt" =~ ^[Nn]$ ]] && echo "manual" || echo "auto")
}

# =================================================================
# DEPLOY ENGINE
# =================================================================
run_deploy() {
    mkdir -p "$ARCHIVE_PATH/LARGE_FILES"

    if [ ! -f "$INDEX_FILE" ]; then
        cat <<EOT > "$INDEX_FILE"
# Global Project Master Index
| Project Name | GitHub Link | Local Source Path |
| :--- | :--- | :--- |
EOT
    fi

    local ok=0 fail=0 skip=0

    for dir in "${DIRS_TO_PROCESS[@]}"; do
        local orig_dir_name="${dir%/}"
        echo ""
        print_sep
        echo -e "${BOLD}⚙️ Processing: $orig_dir_name${NC}"
        print_sep

        cd "$ROOT_DIR/$dir" || { echo -e "  ${RED}Not found, skipping.${NC}"; ((fail++)); continue; }

        # Pre-fetch context only if AI is needed for something
        local repo_context=""
        if [ "$AI_NAME_MODE" = "auto" ] || [ "$AI_DESC_MODE" = "auto" ] || [ "$AI_README_MODE" = "auto" ]; then
            echo -e "  ${CYAN}Analyzing files to generate AI context...${NC}"
            repo_context=$(get_repo_context)
        fi

        local repo_name="$orig_dir_name"
        local repo_desc=""

        # -------------------------------------------------------------
        # 1. README CHECK & REPO NAME LOGIC
        # -------------------------------------------------------------
        if [ -f "README.md" ]; then
            echo -e "  ${GREEN}✓ README.md found. Skipping AI Name and AI README generation.${NC}"
            repo_name="$orig_dir_name"
        else
            # Handle Name
            if [ "$AI_NAME_MODE" = "auto" ]; then
                local ai_repo_name
                ai_repo_name=$(ask_gemini "$COMPANY_PERSONA As the CEO and Marketing Director, return ONLY the best, regular trendy, highly professional GitHub repository name. It MUST be strictly in kebab-case (e.g., modern-web-app). Do not include any other text, quotes, or markdown. Return strictly the name." "$repo_context")
                
                if [[ "$ai_repo_name" == *"API_ERROR"* ]] || [[ "$ai_repo_name" == "system-error-fallback" ]]; then
                    ai_repo_name="$orig_dir_name"
                else
                    ai_repo_name=$(echo "$ai_repo_name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
                fi
                
                echo -e "  ${MAGENTA}🤖 CEO AI Suggests Repo Name: ${BOLD}$ai_repo_name${NC}"
                read -rp "  Press [Enter] to keep, or type a new name: " user_repo_name
                repo_name="${user_repo_name:-$ai_repo_name}"
            else
                read -rp "  Enter Repo Name (default: $orig_dir_name): " user_repo_name
                repo_name="${user_repo_name:-$orig_dir_name}"
            fi

            # Handle Folder Rename
            if [ "$repo_name" != "$orig_dir_name" ]; then
                cd ..
                mv "$orig_dir_name" "$repo_name"
                cd "$repo_name" || continue
                echo -e "  ${GREEN}✓ Renamed local folder to $repo_name${NC}"
            fi

            # Handle README Generation
            if [ "$AI_README_MODE" = "auto" ]; then
                echo -e "  ${CYAN}Generating Deep Executive README...${NC}"
                local ai_readme
                ai_readme=$(ask_gemini "$COMPANY_PERSONA As the full executive board, create a deeply comprehensive, investor-grade, and strictly professional README.md. Give the readme in detail deeply and ready to copy paste. Include modern icons and visual structures for understanding. You MUST include these sections: Executive Summary, Business Analysis, Technical Architecture, Security Analysis, 🚀 Features, 🛠️ Tech Stack, and ⚙️ Installation. Make it visually impressive." "$repo_context")
                echo "$ai_readme" > README.md
                echo -e "  ${GREEN}✓ Master README.md created${NC}"
            fi
        fi

        # -------------------------------------------------------------
        # 2. DESCRIPTION LOGIC
        # -------------------------------------------------------------
        if [ "$AI_DESC_MODE" = "auto" ]; then
            echo -e "  ${CYAN}Generating Executive GitHub description...${NC}"
            repo_desc=$(ask_gemini "$COMPANY_PERSONA As the Marketing Director, write a catchy, highly professional, LinkedIn-friendly description. It MUST be strictly under 300 characters. No markdown. Give me ONLY the description text." "$repo_context")
            repo_desc=${repo_desc:0:299}
        else
            read -rp "  Enter Repo Description (leave blank for none): " repo_desc
        fi

        # -------------------------------------------------------------
        # 3. COMMIT MESSAGE LOGIC (Always AI for speed, unless you want it manual)
        # -------------------------------------------------------------
        local commit_msg
        if [ -n "$repo_context" ]; then
            commit_msg=$(ask_gemini "$COMPANY_PERSONA Write a single, precise, descriptive git commit message based on the code. Return ONLY the one-line commit message without quotes." "$repo_context")
            commit_msg=$(echo "$commit_msg" | tr -d '"' | tr -d '\`')
        else
            commit_msg="feat: initial project backup and master deployment"
        fi

        if [ "$CLEAN_NESTED" = "true" ]; then
            find . -mindepth 2 -name ".git" -type d -exec rm -rf {} + 2>/dev/null
        fi

        # Git Init
        git init -b main &>/dev/null || (git init && git branch -M main) &>/dev/null
        generate_smart_ignore
        git rm -r --cached . &>/dev/null

        # Repo Creation
        local vis_flag="--private"
        if [ "$REPO_VISIBILITY" = "ask" ]; then
            read -rp "  Visibility for ${repo_name} [private/public]: " v
            [[ "$v" == "public" ]] && vis_flag="--public"
        elif [ "$REPO_VISIBILITY" = "public" ]; then
            vis_flag="--public"
        fi

        if gh repo create "$repo_name" $vis_flag --description "$repo_desc" --source=. --remote=origin 2>/dev/null; then
            echo -e "  ${GREEN}✓ Created repo ($vis_flag)${NC}"
        else
            echo -e "  ${YELLOW}! Linking existing repo${NC}"
            git remote remove origin 2>/dev/null
            git remote add origin "https://github.com/$GITHUB_USER/$repo_name.git"
            gh repo edit "$repo_name" --description "$repo_desc" &>/dev/null
        fi

        # Master index
        if ! grep -q "https://github.com/$GITHUB_USER/$repo_name" "$INDEX_FILE"; then
            echo "| $repo_name | [Link](https://github.com/$GITHUB_USER/$repo_name) | $ROOT_DIR |" >> "$INDEX_FILE"
        fi

        # Commit & Push
        git add .
        git commit -m "$commit_msg" --quiet 2>/dev/null
        
        echo -e "  ${CYAN}Pushing to GitHub...${NC}"
        if [ "$FORCE_PUSH" = "true" ]; then
            git push -u origin main --force 2>/dev/null
        else
            git push -u origin main 2>/dev/null
        fi

        if [ $? -eq 0 ]; then
            echo -e "  ${GREEN}✓ Deployment Successful${NC}"
            ((ok++))
        else
            echo -e "  ${RED}✗ Push failed${NC}"
            ((fail++))
        fi

        cd "$ROOT_DIR" || exit
    done

    # Report
    echo ""
    print_sep
    echo -e "${BOLD}  RESULTS${NC}"
    print_sep
    echo -e "  ${GREEN}Success : $ok${NC}"
    echo -e "  ${RED}Failed  : $fail${NC}"
    echo -e "  ${YELLOW}Skipped : $skip${NC}"
    print_sep
}

# =================================================================
# EXECUTION LOGIC
# =================================================================
print_banner
preflight_check

if [ -n "$1" ]; then
    if [ -d "$1" ]; then
        DIRS_TO_PROCESS=("$1/")
        echo -e "${CYAN}Quick mode: deploying $1${NC}"
        run_deploy
        exit 0
    else
        echo -e "${RED}Error: '$1' is not a directory.${NC}"
        exit 1
    fi
fi

select_directories
select_visibility
select_ai_options
run_deploy

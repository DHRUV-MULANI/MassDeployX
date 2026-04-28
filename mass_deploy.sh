#!/bin/bash

# =================================================================
# MASS DEPLOY - Interactive GitHub Bulk Deployer
# =================================================================

GITHUB_USER="DM-Mulani-963"
ROOT_DIR=$(pwd)
ARCHIVE_PATH="$HOME/Main-Root-Archive"
ARCHIVE_REPO="Main-Root-Archive"
INDEX_FILE="$ARCHIVE_PATH/README.md"
SIZE_LIMIT="+50M"

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
COMMIT_MODE="auto"
COMMIT_MSG=""
FORCE_PUSH=true
MOVE_LARGE=true
CLEAN_NESTED=true
SYNC_ARCHIVE=true
DRY_RUN=false

print_banner() {
    echo -e "${MAGENTA}${BOLD}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║      MASS DEPLOY - GitHub Bulk Deployer      ║"
    echo "  ║           by $GITHUB_USER             ║"
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
    for cmd in git gh; do
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
    if command -v git-lfs &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Git LFS"
    else
        echo -e "  ${YELLOW}!${NC} Git LFS not installed (large files won't use LFS)"
    fi
    [ "$fail" -eq 1 ] && { echo -e "\n${RED}Fix issues above first.${NC}"; exit 1; }
    echo ""
}

# =================================================================
# MENU 1: SELECT DIRECTORIES
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
        echo -e "${GREEN}→ ${#DIRS_TO_PROCESS[@]} directory(s) selected${NC}"
    fi
}

# =================================================================
# MENU 2: REPO VISIBILITY
# =================================================================
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
    echo -e "→ ${GREEN}$REPO_VISIBILITY${NC}"
}

# =================================================================
# MENU 3: COMMIT MESSAGE
# =================================================================
select_commit_msg() {
    echo -e "\n${BOLD}Commit message:${NC}"
    print_sep
    echo -e "  ${CYAN}1)${NC} Auto: \"Full Backup YYYY-MM-DD\" (default)"
    echo -e "  ${CYAN}2)${NC} Custom message (same for all)"
    echo -e "  ${CYAN}3)${NC} Ask for each repo individually"
    print_sep
    read -rp "Choose [1/2/3]: " mc
    case "$mc" in
        2)
            read -rp "Enter commit message: " COMMIT_MSG
            COMMIT_MODE="custom"
            ;;
        3) COMMIT_MODE="ask" ;;
        *) COMMIT_MODE="auto" ;;
    esac
}

# =================================================================
# MENU 4: OPTIONS
# =================================================================
select_options() {
    echo -e "\n${BOLD}Options:${NC}"
    print_sep

    read -rp "  Move large files (>50MB) to archive? [Y/n]: " opt
    MOVE_LARGE=$([[ "$opt" =~ ^[Nn]$ ]] && echo false || echo true)

    read -rp "  Remove nested .git dirs? [Y/n]: " opt
    CLEAN_NESTED=$([[ "$opt" =~ ^[Nn]$ ]] && echo false || echo true)

    read -rp "  Force push (overwrite remote)? [Y/n]: " opt
    FORCE_PUSH=$([[ "$opt" =~ ^[Nn]$ ]] && echo false || echo true)

    read -rp "  Sync master archive after deploy? [Y/n]: " opt
    SYNC_ARCHIVE=$([[ "$opt" =~ ^[Nn]$ ]] && echo false || echo true)

    read -rp "  Dry run (preview only)? [y/N]: " opt
    DRY_RUN=$([[ "$opt" =~ ^[Yy]$ ]] && echo true || echo false)
}

# =================================================================
# CONFIRMATION
# =================================================================
confirm_deploy() {
    echo ""
    print_sep
    echo -e "${BOLD}  DEPLOY SUMMARY${NC}"
    print_sep
    echo -e "  Directories : ${CYAN}${#DIRS_TO_PROCESS[@]}${NC}"
    echo -e "  Visibility  : ${CYAN}$REPO_VISIBILITY${NC}"
    echo -e "  Commit      : ${CYAN}$COMMIT_MODE${NC}"
    echo -e "  Large files : ${CYAN}$MOVE_LARGE${NC}"
    echo -e "  Clean nested: ${CYAN}$CLEAN_NESTED${NC}"
    echo -e "  Force push  : ${CYAN}$FORCE_PUSH${NC}"
    echo -e "  Sync archive: ${CYAN}$SYNC_ARCHIVE${NC}"
    echo -e "  Dry run     : ${CYAN}$DRY_RUN${NC}"
    print_sep
    read -rp "Proceed? [y/N]: " go
    [[ ! "$go" =~ ^[Yy]$ ]] && { echo "Aborted."; exit 0; }
}

# =================================================================
# HELPERS
# =================================================================
get_visibility_flag() {
    local repo_name="$1"
    if [ "$REPO_VISIBILITY" = "ask" ]; then
        read -rp "  Visibility for ${repo_name} [private/public]: " v
        [[ "$v" == "public" ]] && echo "--public" || echo "--private"
    elif [ "$REPO_VISIBILITY" = "public" ]; then
        echo "--public"
    else
        echo "--private"
    fi
}

get_commit_msg() {
    local repo_name="$1"
    case "$COMMIT_MODE" in
        ask)
            read -rp "  Commit msg for ${repo_name}: " m
            [[ -z "$m" ]] && echo "Full Backup $(date +'%Y-%m-%d')" || echo "$m"
            ;;
        custom) echo "$COMMIT_MSG" ;;
        *) echo "Full Backup $(date +'%Y-%m-%d')" ;;
    esac
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
        repo_name="${dir%/}"
        echo ""
        print_sep
        echo -e "${BOLD}  $repo_name${NC}"
        print_sep

        if [ "$DRY_RUN" = "true" ]; then
            echo -e "  ${YELLOW}[DRY RUN] Would deploy $repo_name${NC}"
            ((skip++)); continue
        fi

        cd "$ROOT_DIR/$dir" || { echo -e "  ${RED}Not found, skipping.${NC}"; ((fail++)); continue; }

        # Large files
        if [ "$MOVE_LARGE" = "true" ]; then
            find . -type f -size $SIZE_LIMIT -not -path '*/.*' | while read -r f; do
                echo -e "  ${YELLOW}Moving large file: $f${NC}"
                target="$ARCHIVE_PATH/LARGE_FILES/$repo_name/$(dirname "$f")"
                mkdir -p "$target"
                mv "$f" "$target/"
            done
        fi

        # Nested .git cleanup
        if [ "$CLEAN_NESTED" = "true" ]; then
            find . -mindepth 2 -name ".git" -type d -exec rm -rf {} + 2>/dev/null
        fi

        # Init
        git init -b main &>/dev/null || (git init && git branch -M main) &>/dev/null

        # Gitignore + cache clean
        generate_smart_ignore
        git rm -r --cached . &>/dev/null

        # Create or link repo
        local vis_flag
        vis_flag=$(get_visibility_flag "$repo_name")
        if gh repo create "$repo_name" $vis_flag --source=. --remote=origin 2>/dev/null; then
            echo -e "  ${GREEN}Created repo ($vis_flag)${NC}"
        else
            echo -e "  ${YELLOW}Linking existing repo${NC}"
            git remote remove origin 2>/dev/null
            git remote add origin "https://github.com/$GITHUB_USER/$repo_name.git"
        fi

        # Master index
        if ! grep -q "https://github.com/$GITHUB_USER/$repo_name" "$INDEX_FILE"; then
            echo "| $repo_name | [Link](https://github.com/$GITHUB_USER/$repo_name) | $ROOT_DIR |" >> "$INDEX_FILE"
        fi

        # Commit
        local msg
        msg=$(get_commit_msg "$repo_name")
        git add .
        git commit -m "$msg" --quiet 2>/dev/null

        # Push
        echo -e "  ${CYAN}Pushing...${NC}"
        if [ "$FORCE_PUSH" = "true" ]; then
            git push -u origin main --force 2>/dev/null
        else
            git push -u origin main 2>/dev/null
        fi

        if [ $? -eq 0 ]; then
            echo -e "  ${GREEN}✓ Done${NC}"
            ((ok++))
        else
            echo -e "  ${RED}✗ Push failed${NC}"
            ((fail++))
        fi

        cd "$ROOT_DIR"
    done

    # Archive sync
    if [ "$SYNC_ARCHIVE" = "true" ] && [ "$DRY_RUN" != "true" ]; then
        echo ""
        print_sep
        echo -e "${BOLD}  Syncing Master Archive${NC}"
        print_sep
        cd "$ARCHIVE_PATH"
        git init -b main &>/dev/null || (git init && git branch -M main) &>/dev/null
        generate_smart_ignore
        gh repo create "$ARCHIVE_REPO" --private --source=. --remote=origin 2>/dev/null || \
            (git remote remove origin 2>/dev/null && git remote add origin "https://github.com/$GITHUB_USER/$ARCHIVE_REPO.git")
        if command -v git-lfs &>/dev/null; then
            git lfs install &>/dev/null
            git lfs track "LARGE_FILES/**/*" &>/dev/null
            git add .gitattributes
        fi
        git add .
        git commit -m "Update Global Index from $ROOT_DIR" --quiet 2>/dev/null
        git push -u origin main --force 2>/dev/null
        echo -e "  ${GREEN}✓ Archive synced${NC}"
        cd "$ROOT_DIR"
    fi

    # Report
    echo ""
    print_sep
    echo -e "${BOLD}  RESULTS${NC}"
    print_sep
    echo -e "  ${GREEN}Success : $ok${NC}"
    echo -e "  ${RED}Failed  : $fail${NC}"
    echo -e "  ${YELLOW}Skipped : $skip${NC}"
    echo -e "  Archive: ${CYAN}https://github.com/$GITHUB_USER/$ARCHIVE_REPO${NC}"
    print_sep
}

# =================================================================
# QUICK MODE (backward compatible: pass folder as argument)
# =================================================================
if [ -n "$1" ]; then
    case "$1" in
        -h|--help)
            echo "Usage: mass_deploy.sh [OPTIONS] [FOLDER]"
            echo ""
            echo "  (no args)     Interactive mode with menus"
            echo "  FOLDER        Quick-deploy a single folder (private, force push)"
            echo "  -h, --help    Show this help"
            exit 0
            ;;
    esac

    if [ -d "$1" ]; then
        DIRS_TO_PROCESS=("$1/")
        echo -e "${CYAN}Quick mode: deploying $1${NC}"
        preflight_check
        run_deploy
        exit 0
    else
        echo -e "${RED}Error: '$1' is not a directory.${NC}"
        exit 1
    fi
fi

# =================================================================
# INTERACTIVE MODE
# =================================================================
print_banner
preflight_check
select_directories
select_visibility
select_commit_msg
select_options
confirm_deploy
run_deploy

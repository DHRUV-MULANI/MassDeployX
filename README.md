# Mass Deploy - GitHub Bulk Deployer

Batch-deploy multiple local project directories to GitHub with a single command. Interactive menus let you pick which folders to push, set visibility (public/private), customize commit messages, and more.

## Features

- **Directory picker** — select specific folders by number, or push all at once
- **Public / Private toggle** — set globally or choose per-repo
- **Commit message options** — auto-dated, custom, or per-repo prompts
- **Large file handling** — auto-moves files >50MB to a separate archive repo (with Git LFS support)
- **Nested .git cleanup** — removes inner `.git` dirs that break submodule detection
- **Dry run mode** — preview what would happen without touching anything
- **Force push control** — enable or disable `--force` per run
- **Master archive sync** — maintains a global index of all deployed repos
- **Pre-flight checks** — verifies `git`, `gh`, and auth before starting
- **Quick mode** — pass a folder name as argument to skip menus entirely
- **Deploy summary + confirmation** — review all settings before execution

## Requirements

- [Git](https://git-scm.com/)
- [GitHub CLI (`gh`)](https://cli.github.com/) — authenticated (`gh auth login`)
- [Git LFS](https://git-lfs.github.com/) (optional, for large file tracking)

## Usage

### Interactive mode (recommended)

```bash
./mass_deploy.sh
```

Walks you through:
1. Which directories to push
2. Public or private repos
3. Commit message style
4. Additional options (force push, large files, dry run, etc.)
5. Confirmation summary before executing

### Quick mode (single folder)

```bash
./mass_deploy.sh my-project
```

Deploys `my-project/` immediately as a private repo with default settings. No menus.

### Help

```bash
./mass_deploy.sh --help
```

## Interactive Menu Flow

```
┌─────────────────────────────────┐
│  1. Select directories          │
│     - Pick by number            │
│     - A = all, Q = quit         │
├─────────────────────────────────┤
│  2. Repo visibility             │
│     - Private / Public / Ask    │
├─────────────────────────────────┤
│  3. Commit message              │
│     - Auto / Custom / Per-repo  │
├─────────────────────────────────┤
│  4. Options                     │
│     - Large file archival       │
│     - Nested .git cleanup       │
│     - Force push on/off         │
│     - Archive sync on/off       │
│     - Dry run                   │
├─────────────────────────────────┤
│  5. Confirm & deploy            │
└─────────────────────────────────┘
```

## Configuration

Edit the top of `mass_deploy.sh` to change defaults:

```bash
GITHUB_USER="DM-Mulani-963"    # Your GitHub username
ARCHIVE_PATH="$HOME/Main-Root-Archive"  # Where large files go
SIZE_LIMIT="+50M"              # Files larger than this get archived
```

## What it does per directory

1. Scans for files >50MB and moves them to the archive (optional)
2. Removes nested `.git` directories (optional)
3. Runs `git init -b main`
4. Generates a `.gitignore` (node_modules, venv, .env, etc.)
5. Creates a GitHub repo via `gh` (or links to existing one)
6. Logs the repo to a global master index
7. Commits and pushes

## Archive Repo

All large files and a master index of every deployed project are kept in a separate private repo (`Main-Root-Archive`). If Git LFS is installed, large files are tracked automatically.

## License

MIT

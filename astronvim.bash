#!/bin/bash

# Exit on error
set -e

# Default values
AUTO_YES=false
AUTO_NO=false
SKIP_NVIM_INSTALL=false

# Help function
show_help() {
    echo "Neovim Installation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message and exit"
    echo "  -y, --yes     Automatically answer 'yes' to all prompts (will backup existing configs)"
    echo "  -n, --no      Automatically answer 'no' to all prompts (will delete existing configs)"
    echo ""
    echo "This script installs Neovim, AstroNvim, configures GitHub Copilot, Python IDE settings,"
    echo "and sets up ctags for code navigation. It works on macOS and Debian-based Linux distributions."
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        -n|--no)
            AUTO_NO=true
            shift
            ;;
        *)
            echo "[ERROR] Unknown option: $1"
            echo "Use '$0 --help' for more information."
            exit 1
            ;;
    esac
done

# Check for conflicting options
if $AUTO_YES && $AUTO_NO; then
    echo "[ERROR] Cannot specify both -y/--yes and -n/--no at the same time."
    exit 1
fi

echo "[DETECT] Detecting platform..."

OS="$(uname -s)"
ARCH="$(uname -m)"
NVIM_URL=""
TEMP_DIR=$(mktemp -d)

# Function to prompt for confirmation
confirm() {
    local prompt="$1"
    local response

    if $AUTO_YES; then
        echo "$prompt (Automatically answering: yes)"
        return 0
    fi

    if $AUTO_NO; then
        echo "$prompt (Automatically answering: no)"
        return 1
    fi

    while true; do
        read -p "$prompt [y/n]: " response
        case "${response,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "[ERROR] Please answer with 'y' or 'n'" ;;
        esac
    done
}

# Function to create a backup with incremental naming
create_backup() {
    local dir_to_backup="$1"
    local base_backup_name="${dir_to_backup}.bak"

    # Check if directory exists before backing up
    if [[ ! -d "$dir_to_backup" ]]; then
        echo "[INFO] No directory to backup at $dir_to_backup"
        return 0
    fi

    # Find the next available backup number
    local backup_num=0
    local backup_dir="${base_backup_name}"

    while [[ -d "$backup_dir" ]]; do
        backup_num=$((backup_num + 1))
        backup_dir="${base_backup_name}.${backup_num}"
    done

    echo "[BACKUP] Backing up $dir_to_backup to $backup_dir"
    mkdir -p "$backup_dir"
    cp -a "$dir_to_backup/." "$backup_dir/" 2>/dev/null || true

    return 0
}

# Check if Neovim is already installed
if command -v nvim &> /dev/null; then
    NVIM_VERSION=$(nvim --version | head -n 1)
    echo "[INFO] Neovim is already installed: $NVIM_VERSION"

    if ! confirm "Do you want to reinstall Neovim?"; then
        echo "[INFO] Skipping Neovim installation"
        SKIP_NVIM_INSTALL=true
    fi
fi

# Determine platform and set direct download URL based on official documentation
if [[ "$OS" == "Linux" ]]; then
    PLATFORM="linux"
    case "$ARCH" in
        x86_64)
            NVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
            ;;
        aarch64 | arm64)
            NVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-arm64.tar.gz"
            ;;
        *)
            echo "[ERROR] Unsupported Linux architecture: $ARCH"
            exit 1
            ;;
    esac
    echo "[INFO] Linux platform detected, architecture: $ARCH"

elif [[ "$OS" == "Darwin" ]]; then
    PLATFORM="mac"
    case "$ARCH" in
        x86_64)
            NVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-macos-x86_64.tar.gz"
            ;;
        arm64)
            NVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-macos-arm64.tar.gz"
            ;;
        *)
            echo "[ERROR] Unsupported macOS architecture: $ARCH"
            exit 1
            ;;
    esac
    echo "[INFO] macOS platform detected, architecture: $ARCH"
else
    echo "[ERROR] Unsupported OS: $OS"
    exit 1
fi

echo "[INFO] Using download URL: $NVIM_URL"

# Install Neovim
if [[ "$SKIP_NVIM_INSTALL" != "true" ]]; then
    echo "[DOWNLOAD] Downloading Neovim..."
    cd "$TEMP_DIR"

    echo "[INFO] Running: curl -L \"$NVIM_URL\" -o nvim.tar.gz"
    if ! curl -L "$NVIM_URL" -o nvim.tar.gz --fail --progress-bar; then
        echo "[ERROR] Failed to download Neovim from: $NVIM_URL"
        exit 1
    fi

    echo "[EXTRACT] Extracting Neovim..."
    if ! tar xzf nvim.tar.gz; then
        echo "[ERROR] Failed to extract Neovim archive"
        exit 1
    fi

    echo "[DEBUG] Contents of temp directory:"
    ls -la

    echo "[INSTALL] Installing Neovim to /usr/local..."

    # Find the extracted directory - more robust pattern matching
    NVIM_DIR=$(find . -maxdepth 1 -type d -name "nvim*" | grep -v "^.$" | head -1)
    if [[ -z "$NVIM_DIR" ]]; then
        # Try to find any directory that might contain Neovim files
        NVIM_DIR=$(find . -maxdepth 2 -type f -name "nvim" -executable | head -1 | xargs dirname 2>/dev/null || echo "")
    fi

    if [[ -z "$NVIM_DIR" ]]; then
        echo "[ERROR] Could not find extracted Neovim directory"
        echo "[DEBUG] Contents of download directory:"
        find . -type f | sort
        exit 1
    fi

    echo "[INFO] Installing from directory: $NVIM_DIR"

    # Install to /usr/local/ or create an opt directory if sudo is not available
    if command -v sudo &> /dev/null; then
        if ! sudo cp -r "$NVIM_DIR"/* /usr/local/; then
            echo "[ERROR] Failed to install Neovim to /usr/local/"

            # Alternative installation to /opt
            echo "[INFO] Trying alternative installation to /opt..."
            sudo mkdir -p /opt/nvim
            if ! sudo cp -r "$NVIM_DIR"/* /opt/nvim/; then
                echo "[ERROR] Failed to install Neovim to /opt/nvim/"
                exit 1
            fi

            echo "[INFO] Neovim installed to /opt/nvim/"
            echo "[INFO] Add the following to your shell configuration file:"
            echo 'export PATH="$PATH:/opt/nvim/bin"'
        fi
    else
        echo "[WARN] sudo not available, installing to $HOME/nvim"
        mkdir -p "$HOME/nvim"
        cp -r "$NVIM_DIR"/* "$HOME/nvim/"
        echo "[INFO] Neovim installed to $HOME/nvim"
        echo "[INFO] Add the following to your shell configuration file:"
        echo 'export PATH="$PATH:$HOME/nvim/bin"'
    fi

    echo "[OK] Neovim installation complete"
else
    echo "[SKIP] Skipping Neovim installation"
fi

# Install additional system dependencies
install_system_deps() {
    echo "[INFO] Installing additional system dependencies..."

    if [[ "$OS" == "Linux" ]]; then
        if command -v apt-get &> /dev/null; then
            echo "[INFO] Debian/Ubuntu detected, installing additional tools..."
            sudo apt-get update && sudo apt-get install -y fd-find ripgrep xclip || true

            # Create a symlink for fd-find to fd if not exists
            if command -v fdfind &> /dev/null && ! command -v fd &> /dev/null; then
                echo "[INFO] Creating symlink for fd-find to fd..."
                sudo ln -sf $(which fdfind) /usr/local/bin/fd || true
            fi
        elif command -v dnf &> /dev/null; then
            echo "[INFO] Fedora/RHEL detected, installing additional tools..."
            sudo dnf install -y fd-find ripgrep || true
        elif command -v pacman &> /dev/null; then
            echo "[INFO] Arch Linux detected, installing additional tools..."
            sudo pacman -S --noconfirm fd ripgrep || true
        else
            echo "[WARN] Unsupported package manager for system dependencies"
            echo "[INFO] Please manually install: fd-find, ripgrep, and clipboard tools"
        fi
    elif [[ "$OS" == "Darwin" ]]; then
        if command -v brew &> /dev/null; then
            echo "[INFO] macOS detected, installing additional tools using Homebrew..."
            brew install fd ripgrep || true
        else
            echo "[WARN] Homebrew not found"
            echo "[INFO] Please install Homebrew and then install: fd, ripgrep"
        fi
    else
        echo "[WARN] Unsupported OS for system dependencies installation"
    fi

    # Check if fd is installed and provide instructions if not
    if ! command -v fd &> /dev/null; then
        echo "[WARN] 'fd' command not found. Some plugins might not work correctly."
        echo "[INFO] Please install 'fd' manually:"
        echo "  - Debian/Ubuntu: sudo apt install fd-find && sudo ln -s $(which fdfind) /usr/local/bin/fd"
        echo "  - Fedora: sudo dnf install fd-find"
        echo "  - Arch: sudo pacman -S fd"
        echo "  - macOS: brew install fd"
    else
        echo "[OK] 'fd' command is available: $(which fd)"
    fi

    # Check if ripgrep is installed
    if ! command -v rg &> /dev/null; then
        echo "[WARN] 'ripgrep' command not found. Some plugins might not work correctly."
        echo "[INFO] Please install 'ripgrep' manually"
    else
        echo "[OK] 'ripgrep' command is available: $(which rg)"
    fi

    return 0
}

# Ask if user wants to install additional system dependencies
if confirm "Would you like to install additional system dependencies (fd-find, ripgrep)?"; then
    install_system_deps
else
    echo "[INFO] Skipping additional system dependencies installation"
    echo "[WARN] Some plugins may not work correctly without these tools"
fi

# Install Python dependencies
install_python_deps() {
    echo "[INFO] Installing Python dependencies for Neovim..."

    if [[ "$OS" == "Linux" ]]; then
        if command -v apt-get &> /dev/null; then
            echo "[INFO] Debian/Ubuntu detected, installing Python dependencies..."
            if ! sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-venv python3-full; then
                echo "[WARN] Failed to install some Python dependencies using apt-get"
                # Still try to install core requirements
                sudo apt-get install -y python3 python3-pip python3-venv
            fi

            # Try to install pipx if available in repositories
            sudo apt-get install -y pipx 2>/dev/null || true
        elif command -v dnf &> /dev/null; then
            echo "[INFO] Fedora/RHEL detected, installing Python dependencies..."
            if ! sudo dnf install -y python3 python3-pip pipx; then
                echo "[ERROR] Failed to install Python dependencies using dnf"
                return 1
            fi
        elif command -v yum &> /dev/null; then
            echo "[INFO] CentOS/RHEL detected, installing Python dependencies..."
            if ! sudo yum install -y python3 python3-pip; then
                echo "[ERROR] Failed to install Python dependencies using yum"
                return 1
            fi
        elif command -v pacman &> /dev/null; then
            echo "[INFO] Arch Linux detected, installing Python dependencies..."
            if ! sudo pacman -S --noconfirm python python-pip python-pipx; then
                echo "[ERROR] Failed to install Python dependencies using pacman"
                return 1
            fi
        else
            echo "[ERROR] Unsupported package manager for Python dependencies"
            echo "[INFO] Please install Python 3 and pip manually"
            return 1
        fi
    elif [[ "$OS" == "Darwin" ]]; then
        if command -v brew &> /dev/null; then
            echo "[INFO] macOS detected, installing Python dependencies using Homebrew..."
            if ! brew install python pipx; then
                echo "[ERROR] Failed to install Python dependencies using Homebrew"
                return 1
            fi
        else
            echo "[ERROR] Homebrew not found"
            echo "[INFO] Please install Homebrew first: https://brew.sh/"
            return 1
        fi
    else
        echo "[ERROR] Unsupported OS for Python dependencies installation"
        return 1
    fi

    # Create a Python virtual environment for Neovim
    echo "[INFO] Creating a virtual environment for Neovim Python tools..."
    NVIM_VENV_DIR="$HOME/.config/nvim/venv"

    # Remove existing venv if it exists to start clean
    if [ -d "$NVIM_VENV_DIR" ]; then
        echo "[INFO] Removing existing virtual environment..."
        rm -rf "$NVIM_VENV_DIR"
    fi

    # Create venv
    if ! python3 -m venv "$NVIM_VENV_DIR"; then
        echo "[ERROR] Failed to create virtual environment"
        return 1
    fi

    # Activate and install packages in venv
    echo "[INFO] Installing Python development tools in virtual environment..."
    "$NVIM_VENV_DIR/bin/pip" install --upgrade pip
    "$NVIM_VENV_DIR/bin/pip" install pynvim black isort pylint flake8 djlint

    # Create a script to ensure these tools are in PATH
    cat > "$HOME/.config/nvim/env_setup.sh" << 'EOL'
#!/bin/bash
# Add Neovim Python venv tools to PATH
export PATH="$HOME/.config/nvim/venv/bin:$PATH"
EOL

    chmod +x "$HOME/.config/nvim/env_setup.sh"

    # Install core tools using pipx if available
    if command -v pipx &> /dev/null; then
        echo "[INFO] Installing global tools with pipx..."
        for tool in black isort flake8 pylint djlint; do
            if ! pipx install "$tool" &>/dev/null; then
                echo "[WARN] Failed to install $tool with pipx"
            else
                echo "[INFO] Successfully installed $tool with pipx"
            fi
        done
    else
        echo "[INFO] pipx not available - Python tools installed in venv only"
    fi

    # Try to install system packages if available
    if command -v apt-get &> /dev/null; then
        echo "[INFO] Attempting to install Python tools via apt..."
        # Capture available packages
        PYTHON_PACKAGES=$(apt-cache search python3- | grep -E "black|isort|flake8|pylint|pynvim" | awk '{print $1}')

        if [ -n "$PYTHON_PACKAGES" ]; then
            echo "[INFO] Found some Python packages in apt: $PYTHON_PACKAGES"
            sudo apt-get install -y $PYTHON_PACKAGES || true
        else
            echo "[INFO] No Python tooling packages found in apt repositories"
        fi
    fi

    echo "[INFO] Installed Python packages in virtual environment:"
    "$NVIM_VENV_DIR/bin/pip" list | grep -E "pynvim|black|isort|pylint|flake8|djlint" || echo "No packages found"

    # Create a configuration file for Neovim to find the venv
    echo "[INFO] Configuring Neovim to use the Python virtual environment..."
    mkdir -p "$HOME/.config/nvim/lua/user"

    return 0
}

# Install formatting and linting tools
install_formatting_tools() {
    echo "[INFO] Installing code formatting and linting tools..."

    # Install npm and node if needed for formatters
    if ! command -v npm &> /dev/null; then
        echo "[INFO] npm not found, installing Node.js..."
        if [[ "$OS" == "Linux" ]]; then
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y nodejs npm
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y nodejs npm
            elif command -v yum &> /dev/null; then
                sudo yum install -y nodejs npm
            elif command -v pacman &> /dev/null; then
                sudo pacman -S --noconfirm nodejs npm
            else
                echo "[ERROR] Unsupported package manager for Node.js"
                return 1
            fi
        elif [[ "$OS" == "Darwin" ]]; then
            if command -v brew &> /dev/null; then
                brew install node
            else
                echo "[ERROR] Homebrew not found"
                return 1
            fi
        fi
    fi

    # Install formatters and linters
    if command -v npm &> /dev/null; then
        echo "[INFO] Installing JavaScript/TypeScript formatters..."
        npm install -g prettier typescript-language-server vscode-langservers-extracted || true
    else
        echo "[WARN] npm not available, skipping JavaScript/TypeScript formatters"
    fi

    # Install Go tools if Go is installed
    if command -v go &> /dev/null; then
        echo "[INFO] Installing Go tools..."
        GO_VERSION=$(go version | grep -oP "go\d+\.\d+" | grep -oP "\d+\.\d+")

        if [[ -n "$GO_VERSION" ]]; then
            echo "[INFO] Detected Go version: $GO_VERSION"

            # Install gopls in a safer way
            go install golang.org/x/tools/gopls@latest || echo "[WARN] Failed to install gopls, you may need to install it manually"

            # Try installing golangci-lint with a specific version if the latest fails
            go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest || \
            go install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.55.2 || \
            echo "[WARN] Failed to install golangci-lint, you may need to install it manually"
        else
            echo "[WARN] Could not determine Go version, skipping Go tools installation"
        fi
    else
        echo "[INFO] Go not found, skipping Go tools"
    fi

    echo "[OK] Formatters and linters installation complete"
    return 0
}

# Ask if user wants to install Python dependencies
if command -v python3 &> /dev/null; then
    echo "[INFO] Python is already installed"
    if confirm "Would you like to install Python tools for IDE features?"; then
        install_python_deps
    else
        echo "[INFO] Skipping Python tools installation"
        echo "[WARN] Python IDE features will be limited"
    fi
else
    echo "[INFO] Python not found"
    if confirm "Would you like to install Python and tools for IDE features?"; then
        install_python_deps
    else
        echo "[INFO] Skipping Python installation"
        echo "[WARN] Python IDE features will not be available"
    fi
fi

# Ask if user wants to install formatters and linters
if confirm "Would you like to install code formatters and linters?"; then
    install_formatting_tools
else
    echo "[INFO] Skipping formatters and linters installation"
    echo "[WARN] Some code formatting features may be limited"
fi

# Install ctags
echo "[SETUP] Installing ctags for code navigation..."

install_ctags() {
    echo "[INFO] Installing ctags..."

    if [[ "$OS" == "Linux" ]]; then
        if command -v apt-get &> /dev/null; then
            echo "[INFO] Debian/Ubuntu detected, installing universal-ctags..."
            if ! sudo apt-get update && sudo apt-get install -y universal-ctags; then
                echo "[INFO] Universal ctags not found in repositories, trying exuberant-ctags..."
                if ! sudo apt-get install -y exuberant-ctags; then
                    echo "[ERROR] Failed to install ctags using apt-get"
                    return 1
                fi
                echo "[OK] Exuberant-ctags installed successfully"
            else
                echo "[OK] Universal-ctags installed successfully"
            fi
        elif command -v dnf &> /dev/null; then
            echo "[INFO] Fedora/RHEL detected, installing ctags..."
            if ! sudo dnf install -y ctags; then
                echo "[ERROR] Failed to install ctags using dnf"
                return 1
            fi
            echo "[OK] Ctags installed successfully"
        elif command -v yum &> /dev/null; then
            echo "[INFO] CentOS/RHEL detected, installing ctags..."
            if ! sudo yum install -y ctags; then
                echo "[ERROR] Failed to install ctags using yum"
                return 1
            fi
            echo "[OK] Ctags installed successfully"
        elif command -v pacman &> /dev/null; then
            echo "[INFO] Arch Linux detected, installing ctags..."
            if ! sudo pacman -S --noconfirm ctags; then
                echo "[ERROR] Failed to install ctags using pacman"
                return 1
            fi
            echo "[OK] Ctags installed successfully"
        else
            echo "[ERROR] Unsupported package manager"
            echo "[INFO] Please install ctags manually"
            return 1
        fi
    elif [[ "$OS" == "Darwin" ]]; then
        if command -v brew &> /dev/null; then
            echo "[INFO] macOS detected, installing universal-ctags using Homebrew..."
            if ! brew install universal-ctags; then
                echo "[ERROR] Failed to install universal-ctags using Homebrew"
                return 1
            fi
            echo "[OK] Universal-ctags installed successfully"
        else
            echo "[ERROR] Homebrew not found"
            echo "[INFO] Please install Homebrew first: https://brew.sh/"
            return 1
        fi
    else
        echo "[ERROR] Unsupported OS for ctags installation"
        return 1
    fi

    # Verify installation
    if command -v ctags &> /dev/null; then
        CTAGS_VERSION=$(ctags --version | head -n 1)
        echo "[INFO] Verified ctags installation: $CTAGS_VERSION"
        return 0
    else
        echo "[ERROR] Ctags installation failed verification"
        return 1
    fi
}

# Ask if user wants to install ctags
if ! command -v ctags &> /dev/null; then
    if confirm "Would you like to install ctags for code navigation?"; then
        install_ctags
    else
        echo "[INFO] Skipping ctags installation"
        echo "[WARN] Code navigation will be limited without ctags"
    fi
else
    echo "[INFO] Ctags is already installed"
    CTAGS_VERSION=$(ctags --version | head -n 1)
    echo "[INFO] Ctags version: $CTAGS_VERSION"
fi

# Handle existing Neovim configuration directories
echo "[CHECK] Checking for existing Neovim configuration directories..."

# List of directories to check
NVIM_DIRS=(
    "$HOME/.config/nvim"
    "$HOME/.local/share/nvim"
    "$HOME/.local/state/nvim"
    "$HOME/.cache/nvim"
)

# Process existing directories
for DIR in "${NVIM_DIRS[@]}"; do
    if [[ -d "$DIR" ]]; then
        echo "[FOUND] Existing directory: $DIR"
        if $AUTO_YES; then
            create_backup "$DIR"
            rm -rf "$DIR"
        elif $AUTO_NO; then
            echo "[DELETE] Removing directory: $DIR"
            rm -rf "$DIR"
        elif confirm "Backup existing $DIR?"; then
            create_backup "$DIR"
            rm -rf "$DIR"
        else
            echo "[DELETE] Removing directory: $DIR"
            rm -rf "$DIR"
        fi
    fi
done

# Backup old configuration if it exists
if [[ -d "$HOME/.config/nvim" ]]; then
    BACKUP_DIR="$HOME/.config/nvim.bak.$(date +%Y%m%d%H%M%S)"
    echo "[BACKUP] Backing up existing configuration to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    cp -a "$HOME/.config/nvim/." "$BACKUP_DIR/"
    rm -rf "$HOME/.config/nvim"
fi

# Clone AstroNvim configuration
echo "[CLONE] Cloning AstroNvim template repository..."
mkdir -p "$HOME/.config"
if ! git clone --depth 1 https://github.com/AstroNvim/template ~/.config/nvim; then
    echo "[ERROR] Failed to clone AstroNvim template"
    exit 1
fi

# Remove the .git directory to disconnect from the template repository
echo "[SETUP] Removing template's git connection..."
rm -rf ~/.config/nvim/.git

# Create Python specific configuration
echo "[CONFIG] Setting up Python configuration..."
mkdir -p "$HOME/.config/nvim/lua/plugins"

# Create plugins/python.lua for Python configuration
cat > "$HOME/.config/nvim/lua/plugins/python.lua" << 'EOF'
return {
  -- Python LSP configuration
  {
    "williamboman/mason-lspconfig.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "pyright" })
    end,
  },

  -- Python syntax highlighting
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, {
          "python",
          "html",
          "css",
          "scss",
          "javascript",
          "typescript",
          "json",
        })
      end
    end,
  },

  -- Python tools
  {
    "williamboman/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "black",
        "isort",
        "flake8",
        "pylint",
      })
    end,
  },

  -- Configure formatting
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        python = { "black", "isort" },
      },
      formatters = {
        black = {
          prepend_args = { "--line-length", "100" },
        },
        isort = {
          prepend_args = { "--profile", "black" },
        },
      },
    },
  },

  -- Configure linting
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters_by_ft = {
        python = { "flake8", "pylint" },
      },
      linters = {
        flake8 = {
          args = {
            "--max-line-length=100",
          },
        },
        pylint = {
          args = {
            "--disable=C0111,C0103",
          },
        },
      },
    },
  },
}
EOF

# Set up venv-selector plugin
echo "[CONFIG] Setting up VenvSelector plugin..."
cat > "$HOME/.config/nvim/lua/plugins/venv_selector.lua" << 'EOF'
return {
  "linux-cultist/venv-selector.nvim",
  dependencies = {
    "neovim/nvim-lspconfig",
    "nvim-telescope/telescope.nvim",
    "mfussenegger/nvim-dap-python"
  },
  event = "VeryLazy",
  opts = {
    name = { "venv", ".venv", "env", ".env" },
    auto_refresh = true,
    search_venv_managers = true,
    search_workspace = true,
    parents = 2,
    pipenv_path = os.getenv("HOME") .. "/.local/share/virtualenvs",
    anaconda_base_path = os.getenv("HOME") .. "/anaconda3",
    anaconda_envs_path = os.getenv("HOME") .. "/anaconda3/envs",
  },
  keys = {
    { "<leader>cv", "<cmd>VenvSelect<cr>", desc = "Select Python Venv" },
    { "<leader>cs", "<cmd>VenvSelectCached<cr>", desc = "Use Cached Venv" },
  },
}
EOF

# Configure web development support
echo "[CONFIG] Setting up web development configuration..."
cat > "$HOME/.config/nvim/lua/plugins/web_dev.lua" << 'EOF'
return {
  -- Web development LSP configuration
  {
    "williamboman/mason-lspconfig.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "tsserver",
        "html",
        "cssls",
        "jsonls",
      })
    end,
  },

  -- Web development tools
  {
    "williamboman/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "prettier",
        "eslint_d",
      })
    end,
  },

  -- Configure formatting
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        html = { "prettier" },
        css = { "prettier" },
        scss = { "prettier" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        json = { "prettier" },
      },
    },
  },

  -- Configure linting
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters_by_ft = {
        javascript = { "eslint" },
        typescript = { "eslint" },
      },
    },
  },
}
EOF

# Create user configuration
echo "[CONFIG] Setting up user configuration..."

# Create user directory if it doesn't exist
mkdir -p "$HOME/.config/nvim/lua/user"

# Add settings to user init.lua
cat > "$HOME/.config/nvim/lua/user/init.lua" << 'EOF'
return {
  -- Configure AstroNvim options
  options = {
    opt = {
      relativenumber = true,  -- Show relative line numbers
      number = true,          -- Show line numbers
      spell = false,          -- Disable spell checking
      signcolumn = "auto",    -- Show sign column when needed
      wrap = false,           -- Disable line wrap
      tabstop = 4,            -- Set tab width to 4 spaces
      softtabstop = 4,        -- Set soft tabstop to 4 spaces
      shiftwidth = 4,         -- Set indentation width to 4 spaces
      expandtab = true,       -- Use spaces instead of tabs
    },
    g = {
      mapleader = " ",                 -- Set leader key to space
      autoformat_enabled = true,       -- Enable auto-formatting
      cmp_enabled = true,              -- Enable completion
      autopairs_enabled = true,        -- Enable auto-pairs
      diagnostics_mode = 3,            -- Set diagnostic mode to show in-line and virtual text
      icons_enabled = true,            -- Enable icons
      ui_notifications_enabled = true, -- Enable UI notifications
      python3_host_prog = vim.fn.expand("~/.config/nvim/venv/bin/python3"), -- Point to our venv
    },
  },

  -- Configure LSP settings
  lsp = {
    formatting = {
      format_on_save = {
        enabled = true,
        allow_filetypes = {},
        ignore_filetypes = {},
      },
      disabled = {},
      timeout_ms = 1000,
    },
    servers = {
      "lua_ls",
      "pyright",
      "tsserver",
      "jsonls",
      "html",
      "cssls",
    },
    config = {
      pyright = {
        settings = {
          python = {
            analysis = {
              typeCheckingMode = "basic",
              diagnosticMode = "workspace",
              inlayHints = {
                variableTypes = true,
                functionReturnTypes = true,
              },
            },
          },
        },
      },
    },
  },

  -- Configure plugins
  plugins = {
    -- Configure colorscheme
    {
      "catppuccin/nvim",
      name = "catppuccin",
      config = function()
        require("catppuccin").setup {
          flavour = "mocha", -- can be "latte", "frappe", "macchiato", or "mocha"
          background = { light = "latte", dark = "mocha" },
          term_colors = true,
          transparent_background = false,
          styles = {
            comments = { "italic" },
            conditionals = { "italic" },
            loops = {},
            functions = {},
            keywords = {},
            strings = {},
            variables = {},
            numbers = {},
            booleans = {},
            properties = {},
            types = {},
            operators = {},
          },
        }
      end,
    },
  },

  -- Configure custom mappings
  mappings = {
    n = {
      -- Quick save
      ["<C-s>"] = { ":w!<cr>", desc = "Save File" },

      -- Better pane navigation
      ["<C-h>"] = { "<C-w>h", desc = "Move to left pane" },
      ["<C-j>"] = { "<C-w>j", desc = "Move to bottom pane" },
      ["<C-k>"] = { "<C-w>k", desc = "Move to top pane" },
      ["<C-l>"] = { "<C-w>l", desc = "Move to right pane" },

      -- Clipboard mappings
      ["<C-Insert>"] = { '"+y', desc = "Copy to system clipboard" },
      ["<S-Insert>"] = { '"+p', desc = "Paste from system clipboard" },

      -- Make :q and ZZ close only the current tab, not the whole editor
      ["q"] = {
        function()
          if #vim.api.nvim_list_tabpages() > 1 then
            vim.cmd "tabclose"
          else
            vim.cmd "q"
          end
        end,
        desc = "Close current tab or quit if last tab"
      },
      ["ZZ"] = {
        function()
          vim.cmd "w"
          if #vim.api.nvim_list_tabpages() > 1 then
            vim.cmd "tabclose"
          else
            vim.cmd "q"
          end
        end,
        desc = "Save and close current tab or quit if last tab"
      },
      [":q"] = {
        function()
          if #vim.api.nvim_list_tabpages() > 1 then
            vim.cmd "tabclose"
          else
            vim.cmd "q"
          end
        end,
        desc = "Close current tab or quit if last tab"
      },
    },
    v = {
      -- Clipboard mappings in visual mode
      ["<C-Insert>"] = { '"+y', desc = "Copy to system clipboard" },
      ["<S-Insert>"] = { '"+p', desc = "Paste from system clipboard" },
    },
  },

  -- Configure auto commands
  autocmds = {
    -- Remove trailing whitespace on save
    {
      "BufWritePre",
      {
        pattern = "*",
        callback = function()
          local save_cursor = vim.fn.getpos(".")
          vim.cmd [[%s/\s\+$//e]]
          vim.fn.setpos(".", save_cursor)
        end,
      },
    },
    -- Set tab settings for specific filetypes
    {
      "FileType",
      {
        pattern = { "python", "django" },
        callback = function()
          vim.opt_local.expandtab = true
          vim.opt_local.tabstop = 4
          vim.opt_local.softtabstop = 4
          vim.opt_local.shiftwidth = 4
        end,
      },
    },
    {
      "FileType",
      {
        pattern = { "javascript", "typescript", "html", "css", "scss", "vue", "json", "yaml" },
        callback = function()
          vim.opt_local.expandtab = true
          vim.opt_local.tabstop = 2
          vim.opt_local.softtabstop = 2
          vim.opt_local.shiftwidth = 2
        end,
      },
    },
    -- Detect and use Python virtual environment
    {
      "BufEnter",
      {
        pattern = "*",
        callback = function()
          -- First check for .venv directory
          local venv = vim.fn.findfile(".venv", ".;")
          if venv ~= "" then
            local venv_path = vim.fn.fnamemodify(venv, ":p")
            vim.env.VIRTUAL_ENV = venv_path
            vim.env.PATH = venv_path .. "/bin:" .. vim.env.PATH
            vim.notify("Activated venv: " .. venv_path, vim.log.levels.INFO)
            return
          end

          -- Then check for venv directory
          venv = vim.fn.finddir("venv", ".;")
          if venv ~= "" then
            local venv_path = vim.fn.fnamemodify(venv, ":p")
            vim.env.VIRTUAL_ENV = venv_path
            vim.env.PATH = venv_path .. "/bin:" .. vim.env.PATH
            vim.notify("Activated venv: " .. venv_path, vim.log.levels.INFO)
            return
          end

          -- Finally check for any activate script
          local activate_script = vim.fn.findfile("activate", ".;*/bin")
          if activate_script ~= "" then
            local venv_path = vim.fn.fnamemodify(activate_script, ":p:h:h")
            vim.env.VIRTUAL_ENV = venv_path
            vim.env.PATH = venv_path .. "/bin:" .. vim.env.PATH
            vim.notify("Activated venv: " .. venv_path, vim.log.levels.INFO)
          end
        end,
      },
    },
  },

  -- Configure colorscheme
  colorscheme = "catppuccin",
}
EOF

# Create community plugins configuration file
echo "[CONFIG] Setting up community plugins..."
cat > "$HOME/.config/nvim/lua/plugins/community.lua" << 'EOF'
return {
  "AstroNvim/astrocommunity",
  -- Programming language packs
  { import = "astrocommunity.pack.python" },
  { import = "astrocommunity.pack.json" },
  { import = "astrocommunity.pack.html-css" },
  { import = "astrocommunity.pack.typescript" },
  { import = "astrocommunity.pack.markdown" },
  { import = "astrocommunity.pack.yaml" },

  -- Colorscheme
  { import = "astrocommunity.colorscheme.catppuccin" },

  -- Completion
  { import = "astrocommunity.completion.copilot-lua" },

  -- Editing support
  { import = "astrocommunity.editing-support.auto-save-nvim" },
  { import = "astrocommunity.editing-support.neogen" },
  { import = "astrocommunity.editing-support.nvim-treesitter-endwise" },
  { import = "astrocommunity.editing-support.rainbow-delimiters-nvim" },

  -- Git
  { import = "astrocommunity.git.diffview-nvim" },
  { import = "astrocommunity.git.neogit" },
}
EOF

# Install required packages via Mason (simplified approach)
install_packages_via_mason() {
  echo "[INSTALL] Installing packages via Mason..."

  # Create Mason install script
  MASON_INSTALL_SCRIPT="$TEMP_DIR/mason_install.lua"
  cat > "$MASON_INSTALL_SCRIPT" << 'EOL'
-- Basic Neovim setup
vim.cmd [[set runtimepath=$VIMRUNTIME]]
vim.cmd [[set packpath=]]

-- Lazy setup
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable",
    lazypath
  })
end
vim.opt.rtp:prepend(lazypath)

-- Updated Mason setup - simplified version
local function setup_mason()
  -- Required packages to install
  local packages = {
    -- Languages
    "pyright", "typescript-language-server", "css-lsp", "html-lsp", "json-lsp",
    -- Formatting
    "black", "prettier", "isort", "stylua",
    -- Linting
    "flake8", "eslint_d", "pylint",
    -- DAP
    "debugpy",
  }

  -- Setup Mason
  require("mason").setup({
    ui = { check_outdated_packages_on_open = false },
  })

  -- Get Mason registry
  local registry = require("mason-registry")

  -- Function to install packages
  local function install_packages()
    for _, package_name in ipairs(packages) do
      if not registry.is_installed(package_name) then
        local package = registry.get_package(package_name)
        print("Installing " .. package_name)
        package:install()
      end
    end
  end

  -- Install packages after registry refresh
  registry.refresh(function()
    install_packages()
  end)
end

-- Setup plugins
require("lazy").setup({
  {
    "williamboman/mason.nvim",
    config = setup_mason,
  }
})

-- Wait for installation
vim.cmd[[sleep 20000m]]
vim.cmd[[qa!]]
EOL

  echo "[RUN] Running Mason package installer..."

  # Run Neovim with our script
  nvim --headless -u "$MASON_INSTALL_SCRIPT" &

  # Store the PID of the Neovim process
  NVIM_PID=$!

  # Show spinner while waiting for installation
  echo "[WAIT] Installing packages (this may take a few minutes)..."
  spinner=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
  count=0

  while kill -0 $NVIM_PID 2>/dev/null; do
    echo -ne "\r${spinner[$count]} Installing packages..."
    count=$(( (count+1) % 10 ))
    sleep 0.5
  done

  echo -e "\r[INFO] Mason has attempted to install packages."
  echo "[INFO] Some packages may need to be installed manually using :Mason command after first launch."

  return 0
}

# Install packages via Mason if user agrees
if confirm "Would you like to install LSP servers, formatters, and linters automatically?"; then
    install_packages_via_mason
else
    echo "[INFO] Skipping automatic package installation"
    echo "[INFO] You can install packages later using :Mason command"
fi

# Install Nerd Fonts
install_nerd_fonts() {
    echo "[FONTS] Installing Nerd Fonts for proper symbols display..."

    FONT_DIR="$HOME/.local/share/fonts"
    FONTS_TEMP="$TEMP_DIR/fonts"

    # Create fonts directory if it doesn't exist
    mkdir -p "$FONT_DIR"
    mkdir -p "$FONTS_TEMP"

    # List of fonts to install
    FONT_URLS=(
        "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/AdwaitaMono.zip"
        "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/AnonymousPro.zip"
    )

    FONT_NAMES=(
        "AdwaitaMono"
        "AnonymousPro"
    )

    # Download and install fonts
    for i in "${!FONT_URLS[@]}"; do
        FONT_URL="${FONT_URLS[$i]}"
        FONT_NAME="${FONT_NAMES[$i]}"
        FONT_FILE="$FONTS_TEMP/$FONT_NAME.zip"

        echo "[DOWNLOAD] Downloading $FONT_NAME Nerd Font..."
        if ! curl -L "$FONT_URL" -o "$FONT_FILE" --fail --progress-bar; then
            echo "[WARN] Failed to download $FONT_NAME, skipping..."
            continue
        fi

        echo "[EXTRACT] Extracting $FONT_NAME files..."
        if ! unzip -q -o "$FONT_FILE" -d "$FONT_DIR"; then
            echo "[WARN] Failed to extract $FONT_NAME font files"
            continue
        fi

        echo "[OK] Installed $FONT_NAME successfully"
    done

    echo "[FONTS] Rebuilding font cache..."
    if command -v fc-cache &> /dev/null; then
        fc-cache -f "$FONT_DIR"
    fi

    echo "[OK] Nerd Fonts installed successfully"
    echo "[INFO] Available fonts: ${FONT_NAMES[*]}"
    echo "[INFO] Configure your terminal to use one of these Nerd Fonts for proper symbol display"
    return 0
}

# Ask if user wants to install Nerd Fonts
if [[ "$OS" == "Linux" || "$OS" == "Darwin" ]]; then
    if confirm "Would you like to install Nerd Fonts for proper symbol display?"; then
        install_nerd_fonts
    else
        echo "[INFO] Skipping Nerd Fonts installation"
        echo "[INFO] Note that you may see strange symbols in Neovim without proper fonts"
    fi
fi

# Create troubleshooting file
echo "[SETUP] Creating troubleshooting file..."
cat > "$HOME/.config/nvim/troubleshoot.lua" << 'EOF'
-- Troubleshooting script for Neovim
-- Use with: nvim -u ~/.config/nvim/troubleshoot.lua

-- Print Neovim and system information
local function print_info()
  print("NEOVIM INFO:")
  print("============")
  print("Neovim version: " .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch)
  print("Config dir: " .. vim.fn.stdpath("config"))
  print("Data dir: " .. vim.fn.stdpath("data"))
  print("Python3 host: " .. (vim.g.python3_host_prog or "Not set"))
  print("Clipboard: " .. (vim.fn.has("clipboard") == 1 and "Available" or "Not available"))

  -- Check for essential executables
  local executables = {"python3", "pip3", "node", "npm", "git"}
  print("\nEXECUTABLES:")
  print("============")
  for _, exe in ipairs(executables) do
    local path = vim.fn.exepath(exe)
    if path ~= "" then
      print(exe .. ": " .. path)
    else
      print(exe .. ": Not found")
    end
  end

  -- Check for Pynvim
  print("\nPYNVIM:")
  print("======")
  local pynvim_check = vim.fn.system("python3 -c 'import pynvim; print(\"Found pynvim\", pynvim.__version__)'")
  if pynvim_check:match("Found pynvim") then
    print(pynvim_check)
  else
    print("Pynvim not installed in default Python")
  end

  -- Check for virtual environment
  local nvim_venv = vim.fn.expand("~/.config/nvim/venv")
  if vim.fn.isdirectory(nvim_venv) == 1 then
    print("\nNVIM VIRTUAL ENV:")
    print("================")
    print("Path: " .. nvim_venv)
    local venv_pynvim = vim.fn.system(nvim_venv .. "/bin/python3 -c 'import pynvim; print(\"Found pynvim\", pynvim.__version__)'")
    if venv_pynvim:match("Found pynvim") then
      print("Venv " .. venv_pynvim)
    else
      print("Pynvim not installed in venv")
    end
  end

  -- Check for fd and ripgrep
  print("\nSEARCH TOOLS:")
  print("============")
  local fd_path = vim.fn.exepath("fd")
  if fd_path ~= "" then
    print("fd: " .. fd_path)
  else
    print("fd: Not found - VenvSelect may have issues!")

    -- Check for fdfind (Debian/Ubuntu)
    local fdfind_path = vim.fn.exepath("fdfind")
    if fdfind_path ~= "" then
      print("fdfind found at: " .. fdfind_path)
      print("  Try creating a symlink: sudo ln -s " .. fdfind_path .. " /usr/local/bin/fd")
    end
  end

  local rg_path = vim.fn.exepath("rg")
  if rg_path ~= "" then
    print("ripgrep: " .. rg_path)
  else
    print("ripgrep: Not found - telescope searching may be slower")
  end

  print("\nLazy.nvim:")
  print("==========")
  local lazy_path = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
  if vim.fn.isdirectory(lazy_path) == 1 then
    print("Lazy.nvim found at: " .. lazy_path)
  else
    print("Lazy.nvim not installed")
  end
end

-- Initialize basic UI
vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.wrap = false
vim.opt.termguicolors = true

-- Print header
print("\n==== NEOVIM TROUBLESHOOTING ====\n")
print_info()
print("\n================================")
print("This is a diagnostic script. To use normal Neovim, exit and run without the -u flag.")
EOF

# Cleanup
echo "[CLEANUP] Removing temporary files..."
rm -rf "$TEMP_DIR"

# Verify the installation
if command -v nvim &> /dev/null; then
    NEW_NVIM_VERSION=$(nvim --version | head -n 1)
    echo "[INFO] Verification: $NEW_NVIM_VERSION is now installed"
    echo "[DONE] AstroNvim installation is complete!"
    echo "[INFO] Run Neovim with: nvim"
else
    # Check if we installed to a custom location
    if [[ -f "/opt/nvim/bin/nvim" ]]; then
        echo "[INFO] Neovim installed to /opt/nvim/bin/nvim"
        echo "[INFO] You can run it with: /opt/nvim/bin/nvim"
        echo "[INFO] Or add /opt/nvim/bin to your PATH"
    elif [[ -f "$HOME/nvim/bin/nvim" ]]; then
        echo "[INFO] Neovim installed to $HOME/nvim/bin/nvim"
        echo "[INFO] You can run it with: $HOME/nvim/bin/nvim"
        echo "[INFO] Or add $HOME/nvim/bin to your PATH"
    else
        echo "[WARN] Verification failed: 'nvim' command not found in PATH"
        echo "[INFO] You may need to restart your terminal or update your PATH"
    fi
fi

# Final instructions
cat << 'EOF'

--------------------------------------------------------------
INSTALLATION COMPLETE!
--------------------------------------------------------------

ASTRONVIM PYTHON IDE SETUP INSTRUCTIONS:
--------------------------------------------------------------
Your Neovim is now configured with AstroNvim as a Python IDE with the following features:

1. Python Development:
   - Formatting with black and isort
   - Linting with pylint and flake8
   - Code completion and navigation
   - Automatic virtual environment detection
   - Support for community plugins through AstroCommunity

2. Virtual Environment Management:
   - Built-in virtual environment at ~/.config/nvim/venv for Python tools
   - Automatic detection of project .venv or venv directories
   - Use <Space>cv to select a different virtual environment
   - Use <Space>cs to use the last selected environment

3. Automatic Whitespace Handling:
   - Trailing whitespace removal on save
   - Proper indentation for different languages
   - Tab/space settings configured by filetype

4. Support for Multiple Languages:
   - Python, JavaScript, TypeScript
   - HTML, CSS, SCSS
   - JSON, Markdown

5. LSP Integration:
   - Pyright for Python intelligence
   - TypeScript language server
   - And more based on installed languages

6. Code Navigation:
   - Symbol browser with quick navigation
   - Jump to definition and references
   - Outline view for file structure

7. Nerd Fonts:
   - Installed AdwaitaMono and AnonymousPro Nerd Fonts
   - Configure your terminal to use these fonts for proper symbol display

8. Custom Keybindings:
   - Modified behavior for :q and ZZ to close only current tab, not all tabs
   - <C-s> for quick saving
   - <C-h/j/k/l> for pane navigation
   - <C-Insert> and <S-Insert> for clipboard operations

CUSTOMIZATION:
--------------------------------------------------------------
AstroNvim is highly customizable. Main configuration files are located at:

1. ~/.config/nvim/lua/user/init.lua - Core user settings
2. ~/.config/nvim/lua/plugins/ - Plugin configurations

IMPORTANT FIRST-TIME STARTUP INSTRUCTIONS:
--------------------------------------------------------------
1. When starting Neovim for the first time, run:
   $ nvim

2. After AstroNvim finishes initializing, install all required packages with:
   :Mason

   In the Mason interface, use these keys:
   - 'i' to install a package
   - 'X' to remove a package
   - 'U' to update all packages

   Make sure these are installed:
   - pyright (for Python)
   - typescript-language-server (for TypeScript/JavaScript)
   - black, isort (formatters for Python)
   - flake8, pylint (linters for Python)
   - prettier (formatter for JavaScript/TypeScript)

3. Install all plugins with:
   :Lazy sync

4. Restart Neovim after installation.

USEFUL COMMANDS:
--------------------------------------------------------------
1. :AstroUpdate - Update AstroNvim
2. :checkhealth - Check for issues with your configuration
3. :Mason - Open Mason package manager
4. :VenvSelect - Select a Python virtual environment
5. :Lazy - Manage plugins
6. <Space> - Open command menu

TROUBLESHOOTING:
--------------------------------------------------------------
If you experience any issues:

1. Run diagnostics:
   $ nvim -u ~/.config/nvim/troubleshoot.lua

2. Common issues can be resolved by:
   - Installing Python and Node.js
   - Installing clipboard support: xclip or wl-clipboard for Linux
   - Using a Nerd Font
   - Installing missing tools:
     $ ~/.config/nvim/venv/bin/pip install pynvim black isort

3. Check for missing dependencies with :checkhealth

4. If you see errors with AstroCommunity modules:
   - Start Neovim with: nvim
   - Run :Lazy sync to update plugins
   - Restart Neovim

5. If you see plugin errors on first launch:
   - Wait for all plugins to finish installing
   - Close the editor (if you see many errors)
   - Start again

IMPORTANT NOTES:
--------------------------------------------------------------
1. In your Debian/Ubuntu system, we've created a dedicated
   virtual environment at ~/.config/nvim/venv to avoid system Python
   package restrictions (PEP 668).

2. The script ~/.config/nvim/env_setup.sh can be added to your shell
   configuration for access to Python tools:

   echo 'source ~/.config/nvim/env_setup.sh' >> ~/.bashrc

   This is optional as Neovim will use the venv automatically.

Enjoy your new AstroNvim setup!
--------------------------------------------------------------
EOF

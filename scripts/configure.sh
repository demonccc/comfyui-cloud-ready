#!/bin/bash

(
set -e

# --- CONFIGURATION ---
COMFYUI_DIR="/workspace/ComfyUI"
VENV_DIR="/venv/main"
PYTHON_BIN="${PYTHON_BIN:-${VENV_DIR}/bin/python}"
[ -x "$PYTHON_BIN" ] || PYTHON_BIN="$(command -v python3 || echo "${VENV_DIR}/bin/python")"

update_comfyui() {
    echo "🔄 Updating ComfyUI core to latest version..."
    if [ -d "${COMFYUI_DIR}/.git" ]; then
        git -C "${COMFYUI_DIR}" fetch origin || true
        git -C "${COMFYUI_DIR}" checkout master 2>/dev/null || git -C "${COMFYUI_DIR}" checkout main 2>/dev/null || true
        git -C "${COMFYUI_DIR}" pull origin master 2>/dev/null || git -C "${COMFYUI_DIR}" pull 2>/dev/null || true

        if [ -f "${COMFYUI_DIR}/requirements.txt" ]; then
            echo "📦 Updating ComfyUI dependencies..."
            "$PYTHON_BIN" -m pip install --no-cache-dir -r "${COMFYUI_DIR}/requirements.txt" || true
        fi
    else
        echo "⚠️ ComfyUI directory (${COMFYUI_DIR}) is not a git repository."
    fi
}

sync_nodes() {
    echo "🔄 Updating Custom Nodes (Runtime)..."
    $PYTHON_BIN /workspace/scripts/build_nodes.py runtime
}

install_models() {
    echo "🔄 Running Model Installer (Runtime)..."
    /workspace/scripts/install_models.sh /workspace/data/models.csv
}

install_llama_cpp() {
    local LLAMA_CPP_WHEEL="https://github.com/JamePeng/llama-cpp-python/releases/download/v0.3.43-cu131-linux-20260718/llama_cpp_python-0.3.43+cu131-cp312-cp312-linux_x86_64.whl"
    local REQUIRED_VERSION="0.3.43"

    echo "🔍 Checking llama-cpp-python version (required >= ${REQUIRED_VERSION})..."

    if "$PYTHON_BIN" -c "
import sys
from importlib.metadata import version

req = sys.argv[1]
try:
    v = version('llama-cpp-python').split('+')[0]
    v_parts = [int(x) for x in v.split('.') if x.isdigit()]
    req_parts = [int(x) for x in req.split('.') if x.isdigit()]
    if v_parts >= req_parts:
        print(f'✅ llama-cpp-python is already installed and up to date: {v}')
        sys.exit(0)
    print(f'⚠️ llama-cpp-python version {v} is lower than required {req}')
    sys.exit(1)
except Exception:
    sys.exit(1)
" "$REQUIRED_VERSION"; then
        return 0
    fi

    echo "📦 Installing llama-cpp-python (>= ${REQUIRED_VERSION})..."

    "$PYTHON_BIN" -m pip install \
        --upgrade \
        --force-reinstall \
        --no-cache-dir \
        "$LLAMA_CPP_WHEEL"

    # Verificación posterior
    if "$PYTHON_BIN" -c "import llama_cpp" >/dev/null 2>&1; then
        local installed_version
        installed_version=$(
            "$PYTHON_BIN" -c \
                "from importlib.metadata import version; print(version('llama-cpp-python'))" \
                2>/dev/null || echo "unknown"
        )

        echo "✅ llama-cpp-python installed successfully: ${installed_version}"
    else
        echo "❌ llama-cpp-python was installed but cannot be imported"
        return 1
    fi
}

install_transformers() {
    echo "🔍 Checking transformers package..."
    if ! "$PYTHON_BIN" -c "import transformers" >/dev/null 2>&1; then
        echo "📦 Installing transformers..."
        "$PYTHON_BIN" -m pip install --no-cache-dir transformers
    else
        echo "✅ transformers is already installed."
    fi
}

# --- EXECUTION ---
if [ "${1:-}" == "build" ]; then
    echo "🏗️ Running Build-time configuration..."
    update_comfyui
    install_llama_cpp
    install_transformers
    exit 0
fi

# Move staged files into the persistent workspace
mkdir -p "${COMFYUI_DIR}/custom_nodes" "${COMFYUI_DIR}/user/default/workflows"
mv /workspace/staging/ComfyUI/custom_nodes/* "${COMFYUI_DIR}/custom_nodes/" 2>/dev/null || true
mv /workspace/staging/ComfyUI/user/default/workflows/* "${COMFYUI_DIR}/user/default/workflows/" 2>/dev/null || true
rm -rf /workspace/staging

update_comfyui
sync_nodes
install_llama_cpp
install_transformers
install_models
)

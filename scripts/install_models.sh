#!/bin/bash

(
set -e

# --- CONFIGURATION ---
COMFYUI_DIR="${COMFYUI_DIR:-/workspace/ComfyUI}"
BASE_MODELS_DIR="${COMFYUI_DIR}/models"
CSV_FILE="${1:-/workspace/data/models.csv}"
PYTHON_BIN="${PYTHON_BIN:-/venv/main/bin/python}"
[ -x "$PYTHON_BIN" ] || PYTHON_BIN="$(command -v python3 || echo "${PYTHON_BIN}")"

# Helper to run hf CLI (huggingface_hub)
run_hf() {
    local hf_cmd=""
    if command -v hf >/dev/null 2>&1; then
        hf_cmd="hf"
    elif command -v huggingface-cli >/dev/null 2>&1; then
        hf_cmd="huggingface-cli"
    elif [ -x "/venv/main/bin/hf" ]; then
        hf_cmd="/venv/main/bin/hf"
    elif [ -x "/venv/main/bin/huggingface-cli" ]; then
        hf_cmd="/venv/main/bin/huggingface-cli"
    else
        echo "📦 Installing huggingface_hub[cli]..."
        "$PYTHON_BIN" -m pip install -U "huggingface_hub[cli]" >/dev/null 2>&1 || true
        if command -v hf >/dev/null 2>&1; then
            hf_cmd="hf"
        elif [ -x "/venv/main/bin/hf" ]; then
            hf_cmd="/venv/main/bin/hf"
        else
            hf_cmd="$PYTHON_BIN -m huggingface_hub.cli.hf_cli"
        fi
    fi

    local -a extra_args=()
    if [ -n "${HF_TOKEN:-}" ]; then
        extra_args=(--token "${HF_TOKEN}")
    fi

    $hf_cmd "$@" "${extra_args[@]}"
}

# --- HF_MAIN_REPO DOWNLOAD ---
if [ -n "${HF_MAIN_REPO:-}" ]; then
    echo "📦 Downloading HF_MAIN_REPO (${HF_MAIN_REPO}) to ${BASE_MODELS_DIR}..."
    mkdir -p "${BASE_MODELS_DIR}"
    run_hf download --local-dir "${BASE_MODELS_DIR}" "${HF_MAIN_REPO}"
fi

# Helper to resolve filename automatically from Civitai API, HTTP headers, or URL
resolve_filename() {
    local url="$1"
    local filename=""

    local script_dir
    script_dir="$(dirname "${BASH_SOURCE[0]}")"

    filename=$("$PYTHON_BIN" "${script_dir}/resolve_model_filename.py" "$url" 2>/dev/null || true)

    if [ -z "$filename" ]; then
        local clean_url="${url%%\?*}"
        filename=$(basename "$clean_url")
    fi

    echo "$filename"
}

# Helper to download a single HTTP model
download_http_model() {
    local url="$1"
    local folder="$2"

    local dest_dir="${BASE_MODELS_DIR}/${folder}"
    mkdir -p "$dest_dir"

    local FINAL_URL="$url"
    local -a ARIA_AUTH_ARGS=()
    local -a WGET_AUTH_ARGS=()

    # --- CIVITAI AUTHENTICATION ---
    if [[ "$url" == *"civitai."* && -n "${CIVITAI_TOKEN:-}" ]]; then
        if [[ "$url" == *"?"* ]]; then
            FINAL_URL="${url}&token=${CIVITAI_TOKEN}"
        else
            FINAL_URL="${url}?token=${CIVITAI_TOKEN}"
        fi
        echo "    🔐 Using CIVITAI_TOKEN"
    fi

    # --- HUGGING FACE AUTHENTICATION ---
    if [[ "$url" == *"huggingface.co"* || "$url" == *"hf.co"* ]]; then
        if [[ -n "${HF_TOKEN:-}" ]]; then
            ARIA_AUTH_ARGS=(--header="Authorization: Bearer ${HF_TOKEN}")
            WGET_AUTH_ARGS=(--header="Authorization: Bearer ${HF_TOKEN}")
            echo "    🔐 Using HF_TOKEN"
        else
            echo "    ⚠️ Hugging Face URL detected, but HF_TOKEN is not defined"
        fi
    fi

    local filename
    filename=$(resolve_filename "$FINAL_URL")
    local target_path="${dest_dir}/${filename}"

    if [ -f "$target_path" ] && [ -s "$target_path" ]; then
        echo "  ✅ Already exists: ${filename} in ${folder}"
        return 0
    fi

    echo "  >> Downloading: ${filename} -> ${folder}"

    local CONNS=16
    [[ "$url" == *"civitai."* ]] && CONNS=4

    aria2c \
        -x "$CONNS" \
        -s "$CONNS" \
        -k 1M \
        --continue=true \
        --auto-file-renaming=false \
        --allow-overwrite=true \
        --console-log-level=error \
        --summary-interval=0 \
        --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        "${ARIA_AUTH_ARGS[@]}" \
        -d "$dest_dir" \
        -o "$filename" \
        "$FINAL_URL" || true

    # Verification
    if [ -f "$target_path" ]; then
        if file "$target_path" | grep -Eiq "HTML document|JSON data|ASCII text|Unicode text"; then
            echo "    ⚠️ Invalid response downloaded with Aria2c. Retrying with Wget..."
            rm -f "$target_path"
        elif [ ! -s "$target_path" ]; then
            echo "    ⚠️ Empty file downloaded with Aria2c. Retrying with Wget..."
            rm -f "$target_path"
        fi
    fi

    # Rescue with Wget
    if [ ! -f "$target_path" ]; then
        echo "    🚀 Retrying with Wget..."
        if wget \
            --show-progress \
            --continue \
            --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
            --no-check-certificate \
            --content-disposition \
            "${WGET_AUTH_ARGS[@]}" \
            "$FINAL_URL" \
            -O "$target_path"; then
            if file "$target_path" | grep -Eiq "HTML document|JSON data|ASCII text|Unicode text"; then
                echo "    ❌ Invalid response downloaded with Wget"
                rm -f "$target_path"
            elif [ ! -s "$target_path" ]; then
                echo "    ❌ Empty file downloaded with Wget"
                rm -f "$target_path"
            else
                echo "    ✅ Rescue successful"
            fi
        else
            echo "    ❌ Error downloading $url"
            rm -f "$target_path"
        fi
    else
        echo "    ✅ Successful download: ${filename}"
    fi
}

# Helper to download hf:// models
download_hf_model() {
    local raw_url="$1"
    local folder="$2"

    local dest_dir
    if [ -n "$folder" ]; then
        dest_dir="${BASE_MODELS_DIR}/${folder}"
    else
        # Empty folder means "use the ComfyUI models root".
        # For a full HF repository, hf download preserves the repository
        # directory structure under --local-dir.
        dest_dir="${BASE_MODELS_DIR}"
    fi
    mkdir -p "$dest_dir"

    local hf_path="${raw_url#hf://}"
    
    # Count slashes to determine if it's user/repo/file or user/repo
    local slash_count
    slash_count=$(echo "$hf_path" | tr -cd '/' | wc -c)

    if [ "$slash_count" -ge 2 ]; then
        # user/repo/file
        local user
        local repo_name
        local file_path
        user=$(echo "$hf_path" | cut -d'/' -f1)
        repo_name=$(echo "$hf_path" | cut -d'/' -f2)
        file_path=$(echo "$hf_path" | cut -d'/' -f3-)

        local repo="${user}/${repo_name}"
        echo "  >> HF File download: ${file_path} from ${repo} -> ${folder}"
        run_hf download --local-dir "$dest_dir" "$repo" "$file_path"
    else
        # user/repo
        local repo="$hf_path"
        if [ -n "$folder" ]; then
            echo "  >> HF Repo download: ${repo} -> ${folder}"
        else
            echo "  >> HF Repo sync: ${repo} -> ComfyUI/models (preserving repository folders)"
        fi
        run_hf download --local-dir "$dest_dir" "$repo"
    fi
}

# --- CSV MODEL SYNCHRONIZATION ---
if [ -f "$CSV_FILE" ]; then
    echo "🔄 Synchronizing Models from CSV (${CSV_FILE})..."
    sed 1d "$CSV_FILE" | tr -d '\r' | while IFS=, read -r url folder || [ -n "$url" ]; do
        # Trim leading/trailing whitespace
        url=$(echo "$url" | xargs)
        folder=$(echo "$folder" | xargs)

        [[ -z "$url" || "$url" == \#* ]] && continue

        if [[ "$url" == hf://* ]]; then
            download_hf_model "$url" "$folder"
        else
            download_http_model "$url" "$folder"
        fi
    done
else
    echo "ℹ️ CSV file not found: ${CSV_FILE}"
fi
)

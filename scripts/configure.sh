#!/bin/bash

(
set -e

# --- CONFIGURATION ---
COMFYUI_DIR="/workspace/ComfyUI"
CSV_NODES="/workspace/data/nodes.csv"
CSV_MODELS="/workspace/data/models.csv"
BASE_MODELS_DIR="${COMFYUI_DIR}/models"
WORKFLOWS_TARGET="${COMFYUI_DIR}/user/default/workflows"
WORKFLOWS_SOURCE="/workspace/workflows"
VENV_DIR="/venv/main"
PIP_BIN="${VENV_DIR}/bin/pip"
PYTHON_BIN="${VENV_DIR}/bin/python"

sync_nodes() {
    echo "🔄 Updating Custom Nodes (Runtime)..."
    $PYTHON_BIN /workspace/scripts/build_nodes.py runtime
}

# Helper to download a single model
download_model() {
    local url="$1"
    local filename="$2"
    local subdir_type="$3"
    
    local dest_dir="$BASE_MODELS_DIR/$subdir_type"
    mkdir -p "$dest_dir"
    local target_path="$dest_dir/$filename"

    if [ ! -f "$target_path" ]; then
        echo "  >> Processing: $filename"
        
        # --- URL CONSTRUCTION WITH TOKEN ---
        local FINAL_URL="${url}"
        if [[ "$url" == *"civitai."* && -n "$CIVITAI_TOKEN" ]]; then
            # If the URL already has '?', we append with '&', otherwise, we start with '?'
            [[ "$url" == *"?"* ]] && FINAL_URL="${url}&token=${CIVITAI_TOKEN}" || FINAL_URL="${url}?token=${CIVITAI_TOKEN}"
        fi

        # --- STEP 1: Aria2c ---
        # Lowering connections to 4 for Civitai to avoid 429/400
        local CONNS=16
        [[ "$url" == *"civitai."* ]] && CONNS=4

        aria2c -x "$CONNS" -s "$CONNS" -k 1M --console-log-level=error --summary-interval=0 \
               --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
               -d "$dest_dir" -o "$filename" "${FINAL_URL}" || true

        # --- STEP 2: Verification with 'file' ---
        if [ -f "$target_path" ]; then
            if file "$target_path" | grep -iq "HTML document"; then
                echo "    ⚠️ Corrupt file (HTML). Deleting for rescue..."
                rm -f "$target_path"
            fi
        fi

        # --- STEP 3: Rescue with Wget (Direct URL Token) ---
        if [ ! -f "$target_path" ]; then
            echo "    🚀 Retrying rescue with Wget (Direct URL Token)..."
            
            # Using the same FINAL_URL that already has the token included
            if ! wget -q --show-progress \
                      --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
                      --no-check-certificate \
                      --content-disposition "${FINAL_URL}" -O "$target_path"; then
                echo "    ❌ Final error in $filename"
                rm -f "$target_path"
            else
                # Final verification
                if file "$target_path" | grep -iq "HTML document"; then
                    echo "    ❌ Error: Even with token in URL it downloaded an HTML."
                    rm -f "$target_path"
                else
                    echo "    ✅ Rescue successful."
                fi
            fi
        else
            echo "    ✅ Successful download with Aria2c."
        fi
    fi
}

# --- MODEL SYNCHRONIZATION FROM CSV ---
sync_models_csv() {
    echo "🔄 Synchronizing Models from CSV..."
    if [ ! -f "$CSV_MODELS" ]; then echo "⚠️ Models CSV not found"; return; fi

    sed 1d "$CSV_MODELS" | tr -d '\r' | while IFS=, read -r url filename subdir_type; do
        [[ -z "$url" || "$url" == \#* ]] && continue
        download_model "$url" "$filename" "$subdir_type"
    done
}

# --- MODEL SYNCHRONIZATION FROM ENV VARS ---
sync_models_env() {
    echo "🔄 Synchronizing Models from EXTRA_ Environment Variables..."
    
    # compgen -v lists all variables, we grep for EXTRA_
    for var in $(compgen -v | grep '^EXTRA_'); do
        local val="${!var}"
        
        # Strip EXTRA_ and replace first underscore with slash
        local remainder="${var#EXTRA_}"
        remainder="${remainder/_//}"
        # Lowercase the result
        local subdir_type=$(echo "$remainder" | tr '[:upper:]' '[:lower:]')
        
        echo "📂 Processing env $var -> dir $subdir_type"
        
        # Elements separated by ;
        IFS=';' read -ra ELEMENTS <<< "$val"
        for element in "${ELEMENTS[@]}"; do
            [[ -z "$element" ]] && continue
            
            local url="${element%%,*}"
            local filename="${element#*,}"
            
            # If no comma was present, filename == url
            if [ "$url" == "$filename" ]; then
                local clean_url="${url%%\?*}"
                filename=$(basename "$clean_url")
            fi
            
            download_model "$url" "$filename" "$subdir_type"
        done
    done
}

# --- EXECUTION ---
sync_nodes
sync_models_csv
sync_models_env
)

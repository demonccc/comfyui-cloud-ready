# ComfyUI Cloud Ready

This repository contains a cloud-ready Docker environment for [ComfyUI](https://github.com/comfyanonymous/ComfyUI), specifically optimized for cloud providers.

## Features
- **Dynamic Node Loading**: Automatically install custom nodes during the Docker build phase or at runtime via `data/nodes.yaml`.
- **Automated Model Loading**: Download custom models (LoRAs, Checkpoints, etc.) at boot via `data/models.csv`, Hugging Face (`hf://`) protocol, or full repository sync (`HF_MAIN_REPO`).
- **Automated CI/CD**: Fully linted shell, python, and yaml configurations that automatically build and publish to Docker Hub upon PR merge.

## Docker Usage

### 1. Custom Nodes (`data/nodes.yaml`)
You can manage your custom nodes in `data/nodes.yaml`. 
For each node, specify whether you want it installed during `build` (baked into the image to save time) or at `runtime` (cloned every time the container boots).

```yaml
nodes:
  - url: https://github.com/ltdrdata/ComfyUI-Manager.git
    install_phase: build
  - url: https://github.com/cubiq/ComfyUI_IPAdapter_plus.git
    install_phase: runtime
```

### 2. Model Installation (`data/models.csv` & Environment Variables)

#### CSV File (`data/models.csv`)
Models to download are configured in `data/models.csv` using 2 columns: `url,folder`. Filenames are resolved automatically via HTTP response headers (`Content-Disposition`) or URL path. Lines starting with `#` are ignored as comments.

```csv
url,folder
# Checkpoints
https://civitai.com/api/download/models/12345,checkpoints
# Hugging Face models
hf://user/repo/model.safetensors,loras
hf://user/repo,checkpoints
```

**`hf://` URL Format:**
- Single File: `hf://user/repo/path/to/file.safetensors,folder`
- Full Repo / Dir: `hf://user/repo,folder`

#### Hugging Face Main Repository (`HF_MAIN_REPO`)
Set the environment variable `HF_MAIN_REPO="user/repository"` to automatically sync an entire Hugging Face repository into `/workspace/ComfyUI/models`.

#### Authentication Tokens
- `HF_TOKEN`: Used automatically for authenticated Hugging Face downloads (`hf://` and `HF_MAIN_REPO`).
- `CIVITAI_TOKEN`: Used automatically for authenticated Civitai model downloads.

#### Manual Script Execution
You can also run the installer script directly:
```bash
/workspace/scripts/install_models.sh /workspace/data/models.csv
```

### 3. Workflows
Drop any default `.json` workflow files into the `workflows/` directory. They will be automatically copied into `/workspace/ComfyUI/user/default/workflows` during the Docker build so they are ready to use.

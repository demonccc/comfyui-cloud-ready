# ComfyUI Cloud Ready

This repository contains a cloud-ready Docker environment for [ComfyUI](https://github.com/comfyanonymous/ComfyUI), specifically optimized for Vast.ai and RunPod.

## Features
- **Dynamic Node Loading**: Automatically install custom nodes during the Docker build phase or at runtime via `data/nodes.yaml`.
- **Dynamic Model Loading**: Inject custom models (LoRAs, Checkpoints, etc.) instantly at boot using environment variables without baking them into the image.
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

### 2. Custom Models via Environment Variables
Instead of creating a giant Docker image with all your models, you can dynamically download models at startup using `EXTRA_` environment variables.

The format is `EXTRA_<MAIN_FOLDER>_<SUBFOLDER>=<URL>,<OPTIONAL_FILENAME>;<URL>`

**Examples:**
- `EXTRA_LORAS_PHOTO_ENHANCERS="http://url.com/model1.safetensors;http://url.com/model2.safetensors,renamed_model2.safetensors"`
- `EXTRA_CHECKPOINTS="http://url.com/my_checkpoint.safetensors"`

These variables automatically resolve and place the files exactly where ComfyUI expects them:
`/workspace/ComfyUI/models/loras/photo_enhancers/model1.safetensors`

### 3. Workflows
Drop any default `.json` workflow files into the `workflows/` directory. They will be automatically copied into `/workspace/ComfyUI/user/default/workflows` during the Docker build so they are ready to use.

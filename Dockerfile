FROM vastai/comfy:latest

# Configure ComfyUI environment variables
ENV COMFY_ARGS="--listen 0.0.0.0 --port 8188 --disable-auto-launch --enable-cors-header --fast fp16_accumulation --reserve-vram 2 --cuda-malloc --async-offload"

# Install dependencies
RUN apt-get update && apt-get install -y \
    aria2 \
    psmisc \
    vim \
    file \
    imagemagick \
    && rm -rf /var/lib/apt/lists/*

# Copy directories into the workspace
COPY data /workspace/data
COPY scripts /workspace/scripts

# Pre-bake heavy nodes by parsing nodes.yaml
RUN /venv/main/bin/pip install pyyaml && \
    /venv/main/bin/python /workspace/scripts/build_nodes.py build

# Copy workflows content into the specified directory
COPY workflows /workspace/ComfyUI/user/default/workflows

# Make sure the configure script is executable
RUN chmod +x /workspace/scripts/configure.sh

# Create a Vast.ai boot script to run the configuration during the provisioning phase.
# The configure.sh script is wrapped in a subshell to prevent `set -e` from leaking
# into the base image's boot_default.sh which sources these files.
COPY scripts/configure.sh /etc/vast_boot.d/80-configure.sh
RUN chmod +x /etc/vast_boot.d/80-configure.sh


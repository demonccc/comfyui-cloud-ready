import os
import sys
import subprocess
import yaml

YAML_PATH = "/workspace/data/nodes.yaml"
CUSTOM_NODES_DIR = "/workspace/ComfyUI/custom_nodes"
PIP_BIN = "/venv/main/bin/pip"

def main():
    if len(sys.argv) < 2:
        print("Usage: python build_nodes.py [build|runtime]")
        sys.exit(1)
        
    mode = sys.argv[1]
    if mode not in ("build", "runtime"):
        print(f"Error: Unknown mode '{mode}'. Use 'build' or 'runtime'.")
        sys.exit(1)

    if not os.path.exists(YAML_PATH):
        print(f"Error: {YAML_PATH} not found.")
        sys.exit(1)

    with open(YAML_PATH, "r") as f:
        data = yaml.safe_load(f)

    nodes = data.get("nodes", [])

    # Ensure custom_nodes dir exists
    os.makedirs(CUSTOM_NODES_DIR, exist_ok=True)

    for node in nodes:
        url = node.get("url")
        phase = node.get("install_phase", "none")

        if not url or phase == "none":
            continue

        if phase == mode:
            print(f"📦 Processing node [{mode}]: {url}")
            repo_name = url.rstrip('/').split('/')[-1]
            if repo_name.endswith(".git"):
                repo_name = repo_name[:-4]
            
            target_dir = os.path.join(CUSTOM_NODES_DIR, repo_name)
            
            # Clone if not exists or pull if exists
            if not os.path.exists(target_dir):
                subprocess.run(["git", "clone", "--depth", "1", url, target_dir], check=False)
            else:
                subprocess.run(["git", "-C", target_dir, "pull"], check=False)
            
            # Install requirements if they exist
            req_file = os.path.join(target_dir, "requirements.txt")
            if os.path.exists(req_file):
                print(f"  >> Installing dependencies for {repo_name}...")
                subprocess.run([PIP_BIN, "install", "--no-cache-dir", "-r", req_file], check=False)

if __name__ == "__main__":
    main()

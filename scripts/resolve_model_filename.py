#!/usr/bin/env python3
import json
import os
import re
import sys
import urllib.request


def resolve_filename(url):
    civitai_token = os.environ.get("CIVITAI_TOKEN", "")
    hf_token = os.environ.get("HF_TOKEN", "")

    # 1. Civitai API resolution (search for model version file name)
    if "civitai.com" in url:
        m = (
            re.search(r"/api/download/models/(\d+)", url)
            or re.search(r"modelVersionId=(\d+)", url)
            or re.search(r"/model-versions/(\d+)", url)
        )
        if m:
            vid = m.group(1)
            api_url = f"https://civitai.com/api/v1/model-versions/{vid}"
            if civitai_token:
                api_url += f"?token={civitai_token}"
            try:
                req = urllib.request.Request(
                    api_url, headers={"User-Agent": "Mozilla/5.0"}
                )
                with urllib.request.urlopen(req, timeout=10) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                    files = data.get("files", [])
                    for f in files:
                        if f.get("isPrimary") and f.get("name"):
                            return f.get("name")
                    if files and files[0].get("name"):
                        return files[0].get("name")
            except Exception:
                pass

        m_model = re.search(r"/models/(\d+)", url)
        if m_model:
            model_id = m_model.group(1)
            api_url = f"https://civitai.com/api/v1/models/{model_id}"
            if civitai_token:
                api_url += f"?token={civitai_token}"
            try:
                req = urllib.request.Request(
                    api_url, headers={"User-Agent": "Mozilla/5.0"}
                )
                with urllib.request.urlopen(req, timeout=10) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                    versions = data.get("modelVersions", [])
                    if versions and versions[0].get("files"):
                        files = versions[0]["files"]
                        for f in files:
                            if f.get("isPrimary") and f.get("name"):
                                return f.get("name")
                        if files[0].get("name"):
                            return files[0].get("name")
            except Exception:
                pass

    # 2. HTTP header / redirect URL resolution
    req_headers = {"User-Agent": "Mozilla/5.0"}
    if ("huggingface.co" in url or "hf.co" in url) and hf_token:
        req_headers["Authorization"] = f"Bearer {hf_token}"

    fetch_url = url
    if (
        "civitai.com" in fetch_url
        and civitai_token
        and "token=" not in fetch_url
    ):
        sep = "&" if "?" in fetch_url else "?"
        fetch_url = f"{fetch_url}{sep}token={civitai_token}"

    try:
        req = urllib.request.Request(
            fetch_url, headers=req_headers, method="GET"
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            cd = resp.headers.get("Content-Disposition", "")
            if cd:
                m_fn = re.search(
                    r"filename\*?=(?:UTF-8'')?\"?([^\";\r\n]+)\"?",
                    cd,
                    re.IGNORECASE,
                )
                if m_fn:
                    fn = m_fn.group(1).strip()
                    if fn and fn != "download":
                        return fn

            effective_url = resp.geturl()
            clean_url = effective_url.split("?")[0].split("#")[0]
            basename = os.path.basename(clean_url)
            if (
                basename
                and basename not in ("download", "models", "")
                and "." in basename
            ):
                return basename
    except Exception:
        pass

    # Fallback to initial URL basename
    clean_url = url.split("?")[0].split("#")[0]
    return os.path.basename(clean_url)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1]:
        print(resolve_filename(sys.argv[1]))

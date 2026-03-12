import os
import sys
import tarfile
from huggingface_hub import HfApi, hf_hub_download
from datetime import datetime, timedelta

api = HfApi()
repo_id = os.getenv("HF_DATASET")
token = os.getenv("HF_TOKEN")

def restore():
    try:
        print(f"--- [SYNC] 启动恢复流程, 目标仓库: {repo_id} ---")
        if not repo_id or not token:
            print("--- [SYNC] 跳过恢复: 未配置 HF_DATASET 或 HF_TOKEN ---")
            return False
        files = api.list_repo_files(repo_id=repo_id, repo_type="dataset", token=token)
        now = datetime.now()
        for i in range(5):
            day = (now - timedelta(days=i)).strftime("%Y-%m-%d")
            name = f"backup_{day}.tar.gz"
            if name in files:
                print(f"--- [SYNC] 发现备份文件: {name}, 正在下载... ---")
                path = hf_hub_download(repo_id=repo_id, filename=name, repo_type="dataset", token=token)
                with tarfile.open(path, "r:gz") as tar: tar.extractall(path="/root/.openclaw/")
                print(f"--- [SYNC] 恢复成功! 数据已覆盖至 /root/.openclaw/ ---")
                return True
        print("--- [SYNC] 未找到最近 5 天的备份包 ---")
    except Exception as e:
        print(f"--- [SYNC] 恢复异常: {e} ---")

def backup():
    try:
        day = datetime.now().strftime("%Y-%m-%d")
        name = f"backup_{day}.tar.gz"
        print(f"--- [SYNC] 正在执行全量备份: {name} ---")
        with tarfile.open(name, "w:gz") as tar:
            for target in ["sessions", "workspace", "agents", "memory", "openclaw.json"]:
                full_path = f"/root/.openclaw/{target}"
                if os.path.exists(full_path):
                    tar.add(full_path, arcname=target)
        api.upload_file(path_or_fileobj=name, path_in_repo=name, repo_id=repo_id, repo_type="dataset", token=token)
        print(f"--- [SYNC] 备份上传成功! ---")
    except Exception as e:
        print(f"--- [SYNC] 备份失败: {e} ---")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "backup":
        backup()
    else:
        restore()

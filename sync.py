#!/usr/bin/env python3
"""HuggingFace Dataset 数据同步脚本"""

import os
import sys
import tarfile
from datetime import datetime, timedelta
from huggingface_hub import HfApi, hf_hub_download


class DataSync:
    """数据同步管理器"""

    def __init__(self):
        self.api = HfApi()
        self.repo_id = os.getenv("HF_DATASET")
        self.token = os.getenv("HF_TOKEN")

    def restore(self):
        """从 HuggingFace Dataset 恢复数据"""
        try:
            print(f"--- [SYNC] 启动恢复流程, 目标仓库: {self.repo_id} ---")
            if not self.repo_id or not self.token:
                print("--- [SYNC] 跳过恢复: 未配置 HF_DATASET 或 HF_TOKEN ---")
                return False

            files = self.api.list_repo_files(
                repo_id=self.repo_id,
                repo_type="dataset",
                token=self.token
            )

            now = datetime.now()
            for i in range(5):
                day = (now - timedelta(days=i)).strftime("%Y-%m-%d")
                name = f"backup_{day}.tar.gz"
                if name in files:
                    print(f"--- [SYNC] 发现备份文件: {name}, 正在下载... ---")
                    path = hf_hub_download(
                        repo_id=self.repo_id,
                        filename=name,
                        repo_type="dataset",
                        token=self.token
                    )
                    with tarfile.open(path, "r:gz") as tar:
                        tar.extractall(path="/root/.openclaw/")
                    print(f"--- [SYNC] 恢复成功! 数据已覆盖至 /root/.openclaw/ ---")
                    return True

            print("--- [SYNC] 未找到最近 5 天的备份包 ---")
            return False

        except Exception as e:
            print(f"--- [SYNC] 恢复异常: {e} ---")
            return False

    def backup(self):
        """备份数据到 HuggingFace Dataset"""
        try:
            day = datetime.now().strftime("%Y-%m-%d")
            name = f"backup_{day}.tar.gz"
            print(f"--- [SYNC] 正在执行全量备份: {name} ---")

            with tarfile.open(name, "w:gz") as tar:
                targets = ["sessions", "workspace", "agents", "memory", "openclaw.json"]
                for target in targets:
                    full_path = f"/root/.openclaw/{target}"
                    if os.path.exists(full_path):
                        tar.add(full_path, arcname=target)

            self.api.upload_file(
                path_or_fileobj=name,
                path_in_repo=name,
                repo_id=self.repo_id,
                repo_type="dataset",
                token=self.token
            )
            print(f"--- [SYNC] 备份上传成功! ---")
            os.remove(name)  # 清理临时文件
            return True

        except Exception as e:
            print(f"--- [SYNC] 备份失败: {e} ---")
            return False


if __name__ == "__main__":
    sync = DataSync()
    if len(sys.argv) > 1 and sys.argv[1] == "backup":
        sync.backup()
    else:
        sync.restore()

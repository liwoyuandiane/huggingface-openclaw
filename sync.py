#!/usr/bin/env python3
"""HuggingFace Dataset 数据同步脚本
支持全量备份和差异备份
"""

import os
import sys
import tarfile
import time
import json
import hashlib
import functools
from datetime import datetime, timedelta
from huggingface_hub import HfApi, hf_hub_download, create_repo


# ============================================================
# 常量配置
# ============================================================
# 支持动态数据目录（优先使用 HF Spaces 的 /data 持久存储）
OPENCLAW_DATA_DIR = os.getenv("OPENCLAW_DATA_DIR", "/root/.openclaw")
BACKUP_TARGETS = ["sessions", "workspace", "agents", "memory", "openclaw.json", "last_backup.json"]
BACKUP_RETENTION_DAYS = 30  # 备份保留天数
RESTORE_SEARCH_DAYS = 5     # 恢复时搜索最近几天的备份
FULL_BACKUP_INTERVAL_DAYS = 7  # 全量备份间隔天数
LAST_BACKUP_FILE = "last_backup.json"


def retry(max_retries=3, delay=5, exceptions=(Exception,)):
    """重试装饰器"""
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            last_error = None
            for attempt in range(max_retries):
                try:
                    return func(*args, **kwargs)
                except exceptions as e:
                    last_error = e
                    if attempt < max_retries - 1:
                        print(f"--- [SYNC] 第 {attempt + 1} 次尝试失败: {e}, {delay}秒后重试... ---")
                        time.sleep(delay)
                    else:
                        print(f"--- [SYNC] 已达到最大重试次数 ({max_retries}), 放弃操作 ---")
            raise last_error
        return wrapper
    return decorator


def get_file_hash(file_path):
    """计算文件的 MD5 哈希"""
    try:
        with open(file_path, 'rb') as f:
            return hashlib.md5(f.read()).hexdigest()
    except Exception:
        return None


def scan_files(data_dir, targets):
    """扫描目标目录，返回文件路径和哈希的字典"""
    files = {}
    for target in targets:
        full_path = os.path.join(data_dir, target)
        if os.path.isfile(full_path):
            files[target] = get_file_hash(full_path)
        elif os.path.isdir(full_path):
            for root, _, filenames in os.walk(full_path):
                for filename in filenames:
                    rel_path = os.path.relpath(os.path.join(root, filename), data_dir)
                    files[rel_path] = get_file_hash(os.path.join(root, filename))
    return files


def safe_extract(tar, path):
    """安全解压 tar 文件，防止路径遍历攻击"""
    safe_members = []
    for member in tar.getmembers():
        # 检查路径是否包含危险的相对路径
        member_path = os.path.join(path, member.name)
        # 规范化路径并检查是否在目标目录内
        if not os.path.abspath(member_path).startswith(os.path.abspath(path)):
            print(f"--- [SYNC] 警告: 跳过不安全路径: {member.name} ---")
            continue
        # 跳过危险的设备文件和符号链接
        if member.isdev() or member.issym():
            print(f"--- [SYNC] 跳过危险文件: {member.name} ---")
            continue
        safe_members.append(member)
    
    # 逐个解压安全文件
    for member in safe_members:
        tar.extract(member, path=path)


class DataSync:
    """数据同步管理器"""

    def __init__(self):
        self.api = HfApi()
        self.token = os.getenv("HF_TOKEN")
        self.space_name = os.getenv("HF_SPACE_DOMAIN", "")
        self.data_dir = OPENCLAW_DATA_DIR
        self.last_backup_file = os.path.join(self.data_dir, LAST_BACKUP_FILE)
        self._init_dataset_repo()

    def _init_dataset_repo(self):
        """初始化 Dataset 仓库（支持自动创建）"""
        # 调试：显示读取到的环境变量
        auto_create_str = os.getenv("AUTO_CREATE_DATASET", "false")
        auto_create = auto_create_str.lower() == "true"
        
        # 调试信息
        print(f"--- [SYNC] 调试: AUTO_CREATE_DATASET={auto_create_str} (auto_create={auto_create}) ---")
        
        custom_repo = os.getenv("OPENCLAW_DATASET_REPO", "")
        
        # 如果已指定自定义仓库，直接使用
        if custom_repo:
            self.repo_id = custom_repo
            print(f"--- [SYNC] 使用自定义 Dataset: {self.repo_id} ---")
            return
        
        # 根据 Space 名称生成默认 Dataset 名称
        if self.space_name:
            # 从 Space 名称提取用户名（如果是 username/spacename 格式）
            if "/" in self.space_name:
                username, space = self.space_name.split("/", 1)
                default_repo = f"{username}/{space}-data"
            else:
                # 需要从 HF_TOKEN 获取用户名
                default_repo = f"{self.space_name}-data"
        else:
            default_repo = None
        
        # 检查环境变量中是否已有 HF_DATASET（向后兼容）
        existing_repo = os.getenv("HF_DATASET", "")
        if existing_repo:
            self.repo_id = existing_repo
            print(f"--- [SYNC] 使用已配置的 Dataset: {self.repo_id} ---")
            return
        
        # 自动创建模式
        if auto_create and self.token and default_repo:
            self.repo_id = self._create_dataset_repo(default_repo)
        elif default_repo:
            # 非自动创建模式，尝试使用默认名称
            self.repo_id = default_repo
            print(f"--- [SYNC] 使用默认 Dataset 名称: {self.repo_id} ---")
            print(f"--- [SYNC] 提示: 设置 AUTO_CREATE_DATASET=true 可自动创建 ---")
        else:
            self.repo_id = None
            print("--- [SYNC] 警告: 未配置 Dataset 仓库，备份功能将被禁用 ---")

    def _create_dataset_repo(self, repo_name):
        """创建私有 Dataset 仓库"""
        try:
            # 获取当前用户信息
            user_info = self.api.whoami(token=self.token)
            username = user_info.get("name", "")
            
            if not username:
                print("--- [SYNC] 无法获取用户名，跳过自动创建 ---")
                return repo_name
            
            full_repo_id = f"{username}/{repo_name}" if "/" not in repo_name else repo_name
            
            # 尝试创建仓库
            try:
                create_repo(
                    repo_id=full_repo_id,
                    repo_type="dataset",
                    private=True,
                    token=self.token,
                    exist_ok=True  # 如果已存在则不报错
                )
                print(f"--- [SYNC] 自动创建 Dataset 成功: {full_repo_id} (私有) ---")
                return full_repo_id
            except Exception as e:
                print(f"--- [SYNC] 创建 Dataset 失败: {e}，将尝试使用现有仓库 ---")
                return full_repo_id
                
        except Exception as e:
            print(f"--- [SYNC] 自动创建 Dataset 异常: {e} ---")
            return repo_name

    def _check_repo_exists(self):
        """检查仓库是否存在且可访问"""
        if not self.repo_id or not self.token:
            return False
        try:
            self.api.list_repo_files(
                repo_id=self.repo_id,
                repo_type="dataset",
                token=self.token
            )
            return True
        except Exception:
            return False

    def _load_last_backup(self):
        """加载上次备份信息"""
        if os.path.exists(self.last_backup_file):
            try:
                with open(self.last_backup_file, 'r') as f:
                    return json.load(f)
            except Exception:
                return None
        return None

    def _save_last_backup(self, backup_info):
        """保存备份信息"""
        try:
            with open(self.last_backup_file, 'w') as f:
                json.dump(backup_info, f, indent=2)
        except Exception as e:
            print(f"--- [SYNC] 保存备份信息失败: {e} ---")

    def _need_full_backup(self):
        """判断是否需要全量备份"""
        last_backup = self._load_last_backup()
        if not last_backup:
            return True  # 没有备份记录，需要全量备份
        
        last_backup_date = last_backup.get("date")
        if not last_backup_date:
            return True
        
        try:
            last_date = datetime.strptime(last_backup_date, "%Y-%m-%d")
            days_since = (datetime.now() - last_date).days
            return days_since >= FULL_BACKUP_INTERVAL_DAYS
        except Exception:
            return True

    def _get_changed_files(self):
        """获取变化的文件列表"""
        current_files = scan_files(self.data_dir, BACKUP_TARGETS)
        last_backup = self._load_last_backup()
        
        if not last_backup:
            return current_files, "full"  # 首次备份
        
        last_files = last_backup.get("files", {})
        changed_files = {}
        
        # 找出新增或修改的文件
        for file_path, file_hash in current_files.items():
            if file_path not in last_files or last_files[file_path] != file_hash:
                changed_files[file_path] = file_hash
        
        # 检查是否有删除的文件（如果删除文件太多，需要全量备份）
        deleted_count = len(last_files) - len(set(current_files.keys()) & set(last_files.keys()))
        
        # 如果删除文件超过 10%，进行全量备份
        if deleted_count > 10 or len(changed_files) > len(current_files) * 0.5:
            return current_files, "full"
        
        return changed_files, "incremental"

    @retry(max_retries=3, delay=10, exceptions=(ConnectionError, TimeoutError, Exception))
    def restore(self):
        """从 HuggingFace Dataset 恢复数据"""
        try:
            print(f"--- [SYNC] 启动恢复流程, 目标仓库: {self.repo_id} ---")
            if not self.repo_id or not self.token:
                print("--- [SYNC] 跳过恢复: 未配置 Dataset 仓库或 HF_TOKEN ---")
                return False

            if not self._check_repo_exists():
                print(f"--- [SYNC] Dataset 仓库不存在或无访问权限: {self.repo_id} ---")
                return False

            files = self.api.list_repo_files(
                repo_id=self.repo_id,
                repo_type="dataset",
                token=self.token
            )

            # 优先尝试恢复最新备份
            # 1. 先尝试差异备份
            incremental_files = [f for f in files if f.startswith("incremental_")]
            if incremental_files:
                # 按日期排序，找到最新的差异备份
                incremental_files.sort(reverse=True)
                latest_incremental = incremental_files[0]
                print(f"--- [SYNC] 发现差异备份: {latest_incremental}, 正在下载... ---")
                try:
                    path = hf_hub_download(
                        repo_id=self.repo_id,
                        filename=latest_incremental,
                        repo_type="dataset",
                        token=self.token
                    )
                    with tarfile.open(path, "r:gz") as tar:
                        safe_extract(tar, path=self.data_dir)
                    print(f"--- [SYNC] 差异备份恢复成功! ---")
                    
                    # 删除临时文件
                    if os.path.exists(path):
                        os.remove(path)
                except Exception as e:
                    print(f"--- [SYNC] 差异备份恢复失败: {e}，尝试全量备份 ---")

            # 2. 尝试全量备份
            now = datetime.now()
            for i in range(RESTORE_SEARCH_DAYS):
                day = (now - timedelta(days=i)).strftime("%Y-%m-%d")
                name = f"backup_{day}.tar.gz"
                if name in files:
                    print(f"--- [SYNC] 发现全量备份文件: {name}, 正在下载... ---")
                    path = hf_hub_download(
                        repo_id=self.repo_id,
                        filename=name,
                        repo_type="dataset",
                        token=self.token
                    )
                    with tarfile.open(path, "r:gz") as tar:
                        safe_extract(tar, path=self.data_dir)
                    print(f"--- [SYNC] 全量备份恢复成功! 数据已覆盖至 {self.data_dir} ---")
                    return True

            print("--- [SYNC] 未找到最近 {0} 天的备份包 ---".format(RESTORE_SEARCH_DAYS))
            return False

        except Exception as e:
            print(f"--- [SYNC] 恢复异常: {e} ---")
            return False

    @retry(max_retries=3, delay=10, exceptions=(ConnectionError, TimeoutError, Exception))
    def backup(self):
        """备份数据到 HuggingFace Dataset（支持全量和差异备份）"""
        temp_file = None
        try:
            if not self.repo_id or not self.token:
                print("--- [SYNC] 跳过备份: 未配置 Dataset 仓库或 HF_TOKEN ---")
                return False

            # 获取变化的文件
            changed_files, backup_type = self._get_changed_files()
            
            day = datetime.now().strftime("%Y-%m-%d")
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

            # 判断是否需要全量备份
            need_full = self._need_full_backup() or backup_type == "full"
            
            if need_full:
                # 全量备份
                name = f"backup_{day}.tar.gz"
                print(f"--- [SYNC] 正在执行全量备份: {name} ---")
                
                # 创建临时备份文件
                with tarfile.open(name, "w:gz") as tar:
                    for target in BACKUP_TARGETS:
                        full_path = os.path.join(self.data_dir, target)
                        if os.path.exists(full_path):
                            tar.add(full_path, arcname=target)
                
                temp_file = name
                backup_mode = "full"
            else:
                # 差异备份
                name = f"incremental_{day}_{timestamp}.tar.gz"
                print(f"--- [SYNC] 正在执行差异备份: {name} ({len(changed_files)} 个文件) ---")
                
                if not changed_files:
                    print("--- [SYNC] 没有变化的文件，跳过备份 ---")
                    return True
                
                # 只备份变化的文件
                with tarfile.open(name, "w:gz") as tar:
                    for target in BACKUP_TARGETS:
                        full_path = os.path.join(self.data_dir, target)
                        if os.path.isfile(full_path) and target in changed_files:
                            tar.add(full_path, arcname=target)
                        elif os.path.isdir(full_path):
                            for root, _, filenames in os.walk(full_path):
                                for filename in filenames:
                                    rel_path = os.path.relpath(os.path.join(root, filename), self.data_dir)
                                    if rel_path in changed_files:
                                        tar.add(os.path.join(root, filename), arcname=rel_path)
                
                temp_file = name
                backup_mode = "incremental"

            # 上传备份文件
            self.api.upload_file(
                path_or_fileobj=temp_file,
                path_in_repo=temp_file,
                repo_id=self.repo_id,
                repo_type="dataset",
                token=self.token,
                commit_message=f"{backup_mode} backup {day}"
            )
            
            # 更新备份记录
            current_files = scan_files(self.data_dir, BACKUP_TARGETS)
            self._save_last_backup({
                "date": day,
                "timestamp": timestamp,
                "mode": backup_mode,
                "files": current_files
            })
            
            print(f"--- [SYNC] {backup_mode.capitalize()} 备份上传成功! ---")
            return True

        except Exception as e:
            print(f"--- [SYNC] 备份失败: {e} ---")
            return False

        finally:
            # 确保临时文件被清理
            if temp_file and os.path.exists(temp_file):
                os.remove(temp_file)
                print(f"--- [SYNC] 已清理临时文件: {temp_file} ---")

    def cleanup_old_backups(self):
        """清理超过保留天数的旧备份"""
        try:
            if not self.repo_id or not self.token:
                return False

            print(f"--- [SYNC] 开始清理超过 {BACKUP_RETENTION_DAYS} 天的旧备份 ---")

            files = self.api.list_repo_files(
                repo_id=self.repo_id,
                repo_type="dataset",
                token=self.token
            )

            cutoff_date = datetime.now() - timedelta(days=BACKUP_RETENTION_DAYS)
            deleted_count = 0

            for file in files:
                if file.startswith("backup_") and file.endswith(".tar.gz"):
                    try:
                        # 从文件名提取日期: backup_YYYY-MM-DD.tar.gz
                        date_str = file.replace("backup_", "").replace(".tar.gz", "")
                        file_date = datetime.strptime(date_str, "%Y-%m-%d")

                        if file_date < cutoff_date:
                            print(f"--- [SYNC] 删除旧全量备份: {file} ---")
                            self.api.delete_file(
                                path_in_repo=file,
                                repo_id=self.repo_id,
                                repo_type="dataset",
                                token=self.token
                            )
                            deleted_count += 1
                    except ValueError:
                        # 文件名格式不正确，跳过
                        continue
                
                # 清理旧的差异备份（保留最近2天的）
                if file.startswith("incremental_"):
                    try:
                        # 格式: incremental_YYYY-MM-DD_HHMMSS.tar.gz
                        date_part = file.replace("incremental_", "").replace(".tar.gz", "").split("_")[0]
                        file_date = datetime.strptime(date_part, "%Y-%m-%d")
                        
                        if file_date < cutoff_date:
                            print(f"--- [SYNC] 删除旧差异备份: {file} ---")
                            self.api.delete_file(
                                path_in_repo=file,
                                repo_id=self.repo_id,
                                repo_type="dataset",
                                token=self.token
                            )
                            deleted_count += 1
                    except Exception:
                        continue

            if deleted_count > 0:
                print(f"--- [SYNC] 已清理 {deleted_count} 个旧备份文件 ---")
            else:
                print("--- [SYNC] 没有需要清理的旧备份 ---")

            return True

        except Exception as e:
            print(f"--- [SYNC] 清理旧备份异常: {e} ---")
            return False


if __name__ == "__main__":
    sync = DataSync()
    if len(sys.argv) > 1:
        if sys.argv[1] == "backup":
            sync.backup()
            sync.cleanup_old_backups()  # 备份后自动清理
        elif sys.argv[1] == "restore":
            sync.restore()
        elif sys.argv[1] == "cleanup":
            sync.cleanup_old_backups()
        else:
            print("用法: sync.py [backup|restore|cleanup]")
    else:
        sync.restore()

# OpenClaw HuggingFace 部署项目

## 项目概述

本项目用于将 OpenClaw AI Gateway 部署到 HuggingFace Spaces，支持飞书、钉钉、ModelScope 免费 API，并实现数据自动备份到 HuggingFace Dataset。

### 核心技术

- **基础镜像**: `ghcr.io/openclaw/openclaw:latest`
- **部署平台**: HuggingFace Spaces (Docker SDK)
- **数据存储**: HuggingFace Dataset
- **编程语言**: Python (同步脚本)、Bash (启动脚本)
- **通知渠道**: 飞书、钉钉
- **免费 API**: ModelScope（每日 2000 次免费调用）

---

## 目录结构

```
openclaw-huggingface/
├── Dockerfile           # Docker 构建文件
├── sync.py              # HuggingFace 数据同步脚本（备份/恢复）
├── start-openclaw.sh    # 容器启动脚本（动态生成配置）
├── .env                 # 环境变量配置示例
├── .gitignore           # Git 忽略文件
└── README.md            # 项目文档
```

---

## 核心文件说明

### 1. Dockerfile

- 基于 `ghcr.io/openclaw/openclaw:latest` 构建
- 安装 Python3、pip、HuggingFace CLI
- 安装飞书、钉钉通知渠道插件
- 暴露 7860 端口
- 包含健康检查 (HEALTHCHECK)

### 2. sync.py

数据同步脚本，支持：
- **自动创建 Dataset**: 设置 `AUTO_CREATE_DATASET=true` 自动创建私有 Dataset
- **备份**: 定时打包并上传到 HuggingFace Dataset
- **恢复**: 启动时自动从 Dataset 恢复最近 5 天的数据
- **清理**: 自动删除超过 30 天的旧备份
- 备份内容包括: sessions、workspace、agents、memory、openclaw.json

### 3. start-openclaw.sh

容器启动入口脚本，功能：
- 从环境变量动态生成 OpenClaw 配置文件 (openclaw.json)
- 支持配置主模型、备用模型（多个）、视觉模型
- 支持飞书、钉钉等通知渠道
- DNS-over-HTTPS 支持（解决 HF Spaces DNS 屏蔽问题）
- PID 管理和信号处理（优雅停止）
- 定时备份任务（间隔可配置）

---

## 环境变量配置

### 必需变量（根据使用方案选择）

**方案一：ModelScope（推荐 - 免费）**

| 变量名 | 说明 | 示例 |
|--------|------|------|
| `HF_TOKEN` | HuggingFace Token（需 Write 权限） | `hf_xxxx` |
| `HF_SPACE_DOMAIN` | HuggingFace Space 名称 | `my-openclaw` |
| `MODELSCOPE_API_KEY` | ModelScope Token | 在 modelscope.cn 获取 |
| `MODELSCOPE_MODEL` | ModelScope 模型 | `moonshotai/Kimi-K2.5` |
| `OPENCLAW_GATEWAY_PASSWORD` | 网关访问密码 | `admin123` |

**方案二：自定义 API**

| 变量名 | 说明 | 示例 |
|--------|------|------|
| `HF_TOKEN` | HuggingFace Token（需 Write 权限） | `hf_xxxx` |
| `HF_SPACE_DOMAIN` | HuggingFace Space 名称 | `my-openclaw` |
| `OPENAI_API_KEY` | 主模型 API Key | `sk-xxx` |
| `OPENAI_API_BASE` | 主模型 API 地址 | `https://api.example.com/v1` |
| `MODEL` | 主模型名称 | `nvidia/nemotron-3-super-120b-a12b` |
| `OPENCLAW_GATEWAY_PASSWORD` | 网关访问密码 | `admin123` |

### 可选变量 - 数据同步

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `AUTO_CREATE_DATASET` | 自动创建私有 Dataset | `false` |
| `OPENCLAW_DATASET_REPO` | 自定义 Dataset 名称 | `{Space名称}-data` |
| `HF_DATASET` | 手动指定 Dataset ID（向后兼容） | - |
| `SYNC_INTERVAL` | 备份间隔（秒） | `60`（1分钟） |

### 可选变量 - 模型配置

| 变量名 | 说明 | 示例 |
|--------|------|------|
| `FALLBACK_MODEL` | 备用模型（逗号分隔多个） | `moonshotai/kimi-k2.5,qwen/qwen3.5` |
| `FALLBACK_OPENAI_API_KEY` | 备用模型 API Key | `sk-xxx` |
| `FALLBACK_OPENAI_API_BASE` | 备用模型 API 地址 | `https://api2.com/v1` |
| `VISION_MODEL` | 视觉模型 | `moonshotai/Kimi-K2.5` |
| `VISION_API_KEY` | 视觉模型 API Key | `ms-xxx` |
| `VISION_API_BASE` | 视觉模型 API 地址 | `https://api-inference.modelscope.cn/v1` |

### 可选变量 - 通知渠道

#### 飞书配置

| 变量名 | 说明 |
|--------|------|
| `FEISHU_ENABLED` | 启用飞书 (`true`/`false`) |
| `FEISHU_APP_ID` | 飞书应用 ID |
| `FEISHU_APP_SECRET` | 飞书应用密钥 |

#### 钉钉配置

| 变量名 | 说明 |
|--------|------|
| `DINGTALK_ENABLED` | 启用钉钉 (`true`/`false`) |
| `DINGTALK_CLIENT_ID` | 钉钉 Client ID |
| `DINGTALK_CLIENT_SECRET` | 钉钉 Client Secret |
| `DINGTALK_ROBOT_CODE` | 钉钉机器人 Code |
| `DINGTALK_CORP_ID` | 钉钉企业 ID |

### 可选变量 - 网络

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `DOH_ENABLED` | 启用 DNS-over-HTTPS（解决 DNS 屏蔽） | `true` |

---

## 快速部署

### 最简部署（推荐）

只需设置以下环境变量即可：

```bash
HF_TOKEN=hf_xxxx
AUTO_CREATE_DATASET=true
OPENAI_API_KEY=sk-xxx
OPENAI_API_BASE=https://api.example.com/v1
MODEL=model-name
HF_SPACE_DOMAIN=my-space
OPENCLAW_GATEWAY_PASSWORD=admin123
```

系统会自动创建私有 Dataset，无需手动配置！

### 本地 Docker 部署

```bash
# 构建镜像
docker build -t openclaw-hf .

# 运行容器
docker run -d --name openclaw \
  -p 7860:7860 \
  -e HF_TOKEN=hf_xxxx \
  -e AUTO_CREATE_DATASET=true \
  -e HF_SPACE_DOMAIN=my-space \
  -e OPENAI_API_KEY=sk-xxx \
  -e OPENAI_API_BASE=https://api.example.com/v1 \
  -e MODEL=model-name \
  -e OPENCLAW_GATEWAY_PASSWORD=admin123 \
  openclaw-hf

# 访问网关
# http://localhost:7860/#token=admin123
```

### HuggingFace Space 部署

1. 创建 HuggingFace Space（选择 Docker SDK）
2. 上传所有文件
3. 在 Space Settings → Repository secrets 中配置环境变量
4. 等待构建完成后访问

---

## 数据同步机制

### 自动备份
- 默认每 20 分钟执行一次备份（可通过 `SYNC_INTERVAL` 配置）
- 备份格式: `backup_YYYY-MM-DD.tar.gz`
- 自动恢复最近 5 天的备份数据
- 自动清理超过 30 天的旧备份

### 手动命令

```bash
# 手动备份
docker exec <container> python3 /usr/local/bin/sync.py backup

# 手动恢复
docker exec <container> python3 /usr/local/bin/sync.py restore

# 手动清理旧备份
docker exec <container> python3 /usr/local/bin/sync.py cleanup
```

---

## 开发注意事项

1. **HF_SPACE_DOMAIN 配置**: 只填写 Space 名称，不要包含 `https://`、`.hf.space` 等后缀
2. **视觉模型**: 需要在模型配置中添加 `"input": ["text", "image"]` 字段才能识别图片
3. **数据持久化**: 免费版 HuggingFace Space 重启会丢失数据，必须依赖 Dataset 备份恢复
4. **DNS 屏蔽**: HF Spaces 可能屏蔽某些域名（如 Telegram），已内置 DNS-over-HTTPS 解决方案
5. **安全提示**: 
   - `.env` 文件包含敏感信息，已加入 `.gitignore`
   - 不要将 Token、API Key 等提交到版本控制

---

## 相关链接

- [OpenClaw 官方文档](https://docs.openclaw.ai/)
- [飞书开放平台](https://open.feishu.cn/)
- [钉钉开放��台](https://open.dingtalk.com/)
- [HuggingFace](https://huggingface.co/)
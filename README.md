# OpenClaw HuggingFace 部署指南

> OpenClaw AI Gateway 官方镜像部署到 HuggingFace Spaces，支持飞书、钉钉、ModelScope 免费 API 和数据自动同步。

---

## 快速部署

### 方案一：使用 ModelScope（推荐 - 免费）

ModelScope（魔搭）每日提供 **2000 次免费 API 调用**，无需付费即可使用强力模型：

```bash
HF_TOKEN=hf_xxxx                    # HuggingFace Token（需 Write 权限）
AUTO_CREATE_DATASET=true            # 自动创建 Dataset
HF_SPACE_DOMAIN=my-space            # Space 名称
MODELSCOPE_API_KEY=xxx              # ModelScope Token（在 modelscope.cn 获取）
MODELSCOPE_MODEL=moonshotai/Kimi-K2.5  # 模型（默认 Kimi-K2.5，可更改）
OPENCLAW_GATEWAY_PASSWORD=admin123  # 网关密码
```

### 方案二：使用自定义 API

如果需要使用其他 API 服务商（如 OpenAI、SiliconFlow）：

```bash
HF_TOKEN=hf_xxxx                    # HuggingFace Token（需 Write 权限）
AUTO_CREATE_DATASET=true            # 自动创建 Dataset
HF_SPACE_DOMAIN=my-space            # Space 名称
OPENAI_API_KEY=sk-xxx              # API Key
OPENAI_API_BASE=https://api.xxx/v1  # API 地址
MODEL=model-name                    # 模型名称
OPENCLAW_GATEWAY_PASSWORD=admin123  # 网关密码
```

---

## 部署步骤

### 1. 准备 HuggingFace Token

1. 访问 [HuggingFace Settings](https://huggingface.co/settings/tokens)
2. 创建新的 Token（选择 "Write" 权限）
3. 保存 Token，格式如：`hf_xxxxxxxxxxxx`

### 2. 创建 HuggingFace Space

1. 访问 [New Space](https://huggingface.co/new-space)
2. **选择 Docker** 作为 SDK
3. **选择 Static** 作为 Space 配置
4. 设置 Space 名称（用于 `HF_SPACE_DOMAIN`）

### 3. 配置环境变量

在 Space 的 **Settings > Variables and secrets** 中添加环境变量：

#### 必需变量（根据使用方案选择）

**方案一：ModelScope（推荐）**

| 变量名 | 说明 | 示例值 |
|--------|------|--------|
| `HF_TOKEN` | HuggingFace Token（需 Write 权限） | `hf_xxxxxxxxxxxx` |
| `HF_SPACE_DOMAIN` | HuggingFace Space 名称 | `my-openclaw` |
| `MODELSCOPE_API_KEY` | ModelScope Token | 在 modelscope.cn 获取 |
| `MODELSCOPE_MODEL` | ModelScope 模型 | `moonshotai/Kimi-K2.5` |
| `OPENCLAW_GATEWAY_PASSWORD` | 网关登录密码 | `your_password` |

**方案二：自定义 API**

| 变量名 | 说明 | 示例值 |
|--------|------|--------|
| `HF_TOKEN` | HuggingFace Token（需 Write 权限） | `hf_xxxxxxxxxxxx` |
| `HF_SPACE_DOMAIN` | HuggingFace Space 名称 | `my-openclaw` |
| `OPENAI_API_KEY` | 主 API Key | `sk-xxx` |
| `OPENAI_API_BASE` | 主 API 地址 | `https://api.siliconflow.cn/v1` |
| `MODEL` | 主模型 | `nvidia/nemotron-3-super-120b-a12b` |
| `OPENCLAW_GATEWAY_PASSWORD` | 网关登录密码 | `your_password` |

#### 可选变量 - 数据同步

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `AUTO_CREATE_DATASET` | 自动创建私有 Dataset | `false` |
| `OPENCLAW_DATASET_REPO` | 自定义 Dataset 名称 | `{Space名称}-data` |
| `HF_DATASET` | 手动指定 Dataset ID（向后兼容） | - |
| `SYNC_INTERVAL` | 备份间隔（秒） | `60`（1分钟） |

#### 可选变量 - 模型配置

| 变量名 | 说明 | 示例值 |
|--------|------|--------|
| `FALLBACK_MODEL` | 备用模型（逗号分隔多个） | `moonshotai/kimi-k2.5,qwen/qwen3.5` |
| `FALLBACK_OPENAI_API_KEY` | 备用模型 API Key | `sk-xxx` |
| `FALLBACK_OPENAI_API_BASE` | 备用模型 API 地址 | `https://api2.com/v1` |
| `VISION_MODEL` | 视觉模型 | `moonshotai/Kimi-K2.5` |
| `VISION_API_BASE` | 视觉模型 API 地址 | `https://api-inference.modelscope.cn/v1` |
| `VISION_API_KEY` | 视觉模型 API Key | `ms-xxx` |

#### 可选变量 - 飞书配置

> ⚠️ 注意：飞书插件已集成到镜像中，配置即可使用。

| 变量名 | 说明 |
|--------|------|
| `FEISHU_ENABLED` | 启用飞书频道 (`true`/`false`) |
| `FEISHU_APP_ID` | 飞书应用 ID |
| `FEISHU_APP_SECRET` | 飞书应用密钥 |

#### 可选变量 - 钉钉配置

| 变量名 | 说明 |
|--------|------|
| `DINGTALK_ENABLED` | 启用钉钉 (`true`/`false`) |
| `DINGTALK_CLIENT_ID` | 钉钉 Client ID |
| `DINGTALK_CLIENT_SECRET` | 钉钉 Client Secret |
| `DINGTALK_ROBOT_CODE` | 钉钉机器人 Code |
| `DINGTALK_CORP_ID` | 钉钉企业 ID |

#### 可选变量 - 网络

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `DOH_ENABLED` | 启用 DNS-over-HTTPS（解决 DNS 屏蔽问题） | `true` |

---

## 飞书配置

### 1. 创建飞书应用

1. 访问 [飞书开放平台](https://open.feishu.cn/)
2. 点击 **「创建企业应用」** 按钮
3. 填写应用信息：
   - 应用名称：OpenClaw AI 助手
   - 应用描述：基于 OpenClaw 的 AI 助手
   - 上传应用图标（建议 1024x1024）

### 2. 获取应用凭证

应用创建成功后，在左侧菜单点击 **「凭证与基础信息」**：

| 字段 | 说明 | 示例值 |
|------|------|--------|
| `App ID` | 应用唯一标识 | `cli_xxxxxxxxxxxxxxxx` |
| `App Secret` | 应用密钥（只显示一次，立即保存） | `xxxxxxxxxxxxxxxx` |

> ⚠️ **重要提示**：
> - App Secret 只显示一次，请立即复制保存到安全的地方
> - 不要将 App Secret 泄露给他人
> - 如果泄露，需要在飞书开放平台重置

### 3. 配置权限

1. 点击左侧菜单 **「权限」**
2. 点击 **「批量导入」**，粘贴以下 JSON：

```json
{
  "scopes": {
    "tenant": [
      "im:message",
      "im:message:send_as_bot",
      "im:message:readonly",
      "im:resource",
      "im:chat.members:bot_access"
    ]
  }
}
```

3. 点击 **「批量添加」**

**关键权限说明**：
- `im:message` - 接收消息
- `im:message:send_as_bot` - 以机器人身份发送消息
- `im:resource` - 上传下载文件

### 4. 开启机器人能力

1. 点击左侧菜单 **「应用能力」** → **「机器人」**
2. 点击 **「开启机器人能力」** 开关
3. 设置机器人名称（用户在飞书中看到的名字）

### 5. 配置事件订阅

1. 点击左侧菜单 **「事件订阅」**
2. 在 **「接收消息」** 部分，选择 **「使用长连接接收事件」**（WebSocket 方式）
3. 点击 **「添加事件」**，搜索并添加以下事件：

| 事件名称 | 说明 | 是否必选 |
|----------|------|----------|
| `im.message.receive_v1` | 接收消息 | ✅ 必选 |
| `im.chat.access_event.bot_p2p_chat` | 用户开始私聊机器人 | 推荐 |
| `im.chat.access_event.bot_added_to_chat` | 机器人被添加到群聊 | 推荐 |

### 6. 发布应用

1. 点击左侧菜单 **「版本管理与发布」**
2. 点击 **「创建新版本」**
3. 填写版本号（如 `1.0.0`）和更新说明
4. 点击 **「提交发布」**

---

## 使用方法

### 部署到 Docker

1. 克隆项目
   ```bash
   git clone <your-repo>
   cd <your-repo>
   ```

2. 构建镜像
   ```bash
   docker build -t openclaw-hf .
   ```

3. 运行容器（最简配置）
   ```bash
   docker run -d --name openclaw \
     -p 7860:7860 \
     -e HF_TOKEN=hf_xxxx \
     -e AUTO_CREATE_DATASET=true \
     -e HF_SPACE_DOMAIN=ceshi001awdhg-ceshi-claw \
     -e OPENAI_API_KEY=sk-xxx \
     -e OPENAI_API_BASE=https://api.example.com/v1 \
     -e MODEL=model-name \
     -e OPENCLAW_GATEWAY_PASSWORD=admin123 \
     openclaw-hf
   ```

4. 访问网关：`http://localhost:7860/#token=admin123`

### 部署到 HuggingFace Space

1. 访问 [New Space](https://huggingface.co/new-space)
2. 选择 **Docker** SDK
3. 上传所有文件（Dockerfile、sync.py、start-openclaw.sh）
4. 在 Settings > Variables and secrets 配置环境变量
5. 等待 Space 构建完成
6. 访问：`https://<your-space>.hf.space/#token=<password>`

---

## 数据同步

### 自动备份

- 默认每 20 分钟自动备份到 HuggingFace Dataset（可通过 `SYNC_INTERVAL` 配置）
- 自动恢复最近 5 天的备份数据
- 自动清理超过 30 天的旧备份

### 手动命令

```bash
# 进入容器
docker exec -it <container> bash

# 手动备份
python3 /usr/local/bin/sync.py backup

# 手动恢复
python3 /usr/local/bin/sync.py restore

# 手动清理旧备份
python3 /usr/local/bin/sync.py cleanup
```

---

## 故障排查

### 构建失败

- 检查 Dockerfile 语法
- 确保 `sync.py` 和 `start-openclaw.sh` 文件已上传

### 网关无法访问

- 检查环境变量是否正确
- 查看 Space 日志

### ❌ Origin not allowed 错误

**问题**：访问时提示 `origin not allowed`

**原因**：`HF_SPACE_DOMAIN` 环境变量配置错误

**正确配置**：只填写 Space 名称，不要包含 `https://`、`/` 或 `.hf.space`

### 飞书无法连接

- 检查 App ID/Secret 是否正确
- 确认事件订阅配置

### 钉钉无法连接

- 检查 Client ID/Secret 是否正确
- 确认机器人配置

### ❌ 模型不支持图像错误

**问题**：日志显示 `Model does not support images`

**原因**：视觉模型配置缺少 `input` 字段声明

**解决方案**：确保 `VISION_MODEL` 和 `VISION_API_BASE` 正确配置

### DNS 解析失败

**问题**：某些域名（如 Telegram）无法访问

**解决方案**：确保 `DOH_ENABLED=true`（默认启用）

---

## 参考资料

- [OpenClaw 官方文档](https://docs.openclaw.ai/)
- [飞书开放平台](https://open.feishu.cn/)
- [钉钉开放平台](https://open.dingtalk.com/)
- [HuggingFace Spaces](https://huggingface.co/spaces)
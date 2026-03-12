# OpenClaw HuggingFace 部署指南

> OpenClaw AI Gateway 官方镜像部署到 HuggingFace Spaces，支持飞书和数据同步。

---

## 部署步骤

### 1. 准备 HuggingFace Token

1. 访问 [HuggingFace Settings](https://huggingface.co/settings/tokens)
2. 创建新的 Token（选择 "Write" 权限）
3. 保存 Token，格式如：`hf_xxxxxxxxxxxx`

### 2. 创建 HuggingFace Dataset

1. 访问 [New Dataset](https://huggingface.co/new-dataset)
2. 创建 Dataset（用于存储 OpenClaw 数据备份）
3. 记录 Dataset ID，格式如：`your-username/your-dataset`

### 3. 创建 HuggingFace Space

1. 访问 [New Space](https://huggingface.co/new-space)
2. **选择 Docker** 作为 SDK
3. **选择 Static** 作为 Space 配置
4. 设置 Space 名称（用于 `HF_SPACE_DOMAIN`）

### 4. 配置环境变量

在 Space 的 **Settings > Variables and secrets** 中添加以下环境变量：

#### 必需变量

| 变量名 | 说明 | 示例值 |
|--------|------|--------|
| `HF_TOKEN` | HuggingFace Token | `hf_xxxxxxxxxxxx` |
| `HF_DATASET` | 备份数据集 ID | `your-username/your-dataset` |
| `HF_SPACE_DOMAIN` | HuggingFace Space 名称（格式：用户名-项目名） | `ceshi001awdhg-ceshi-claw` |
| `OPENAI_API_KEY` | OpenAI API 密钥 | `sk-xxxxxxxx` |
| `OPENAI_API_BASE` | API 地址（去掉 /v1） | `https://api.siliconflow.cn` |
| `MODEL` | 模型 ID | `moonshotai/kimi-k2-instruct-0905` |
| `OPENCLAW_GATEWAY_PASSWORD` | 网关登录密码 | `your_password` |
#### 飞书（可选）

| 变量名 | 说明 |
|--------|------|
| `FEISHU_ENABLED` | `true` 或 `false` |
| `FEISHU_APP_ID` | 飞书应用 App ID |
| `FEISHU_APP_SECRET` | 飞书应用 App Secret |
| 变量名 | 说明 |
|--------|------|
| `DINGTALK_ENABLED` | `true` 或 `false` |
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

### 7. 配置环境变量

| 变量名 | 说明 | 示例值 |
|--------|------|--------|
| `FEISHU_ENABLED` | 启用飞书通道 | `true` |
| `FEISHU_APP_ID` | 飞书 App ID | `cli_xxxxxxxxxxxxxxxx` |
| `FEISHU_APP_SECRET` | 飞书 App Secret | `xxxxxxxxxxxxxxxx` |
---


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

3. 运行容器
   ```bash
   docker run -d --name openclaw \
     -p 7860:7860 \
     -e HF_TOKEN=hf_xxxx \
     -e HF_DATASET=your/dataset \
     -e HF_SPACE_DOMAIN=ceshi001awdhg-ceshi-claw \
     -e OPENAI_API_KEY=sk-xxx \
     -e OPENAI_API_BASE=https://api.example.com/v1 \
     -e MODEL=model-name \
     -e OPENCLAW_GATEWAY_PASSWORD=admin123 \
     -e FEISHU_ENABLED=true \
     -e FEISHU_APP_ID=xxx \
     -e FEISHU_APP_SECRET=xxx \
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

## 飞书使用

1. 在飞书中搜索机器人
2. 发送消息开始对话
3. 首次使用需要配对（pairing）

---

## 数据同步

### 自动备份

每 3 小时自动备份到 HuggingFace Dataset。

### 手动恢复

重启容器时自动从 Dataset 恢复数据。

### 手动备份/恢复

```bash
# 进入容器
docker exec -it <container> bash

# 手动备份
python3 /usr/local/bin/sync.py backup

# 手动恢复
python3 /usr/local/bin/sync.py restore
```

---

## 故障排查

### 构建失败

- 检查 Dockerfile 语法
- 确保 `sync.py` 文件已上传

### 网关无法访问

- 检查环境变量是否正确
- 查看 Space 日志

### ❌ Origin not allowed 错误

**问题**：访问时提示 `origin not allowed (open the Control UI from the gateway host or allow it in gateway.controlUi.allowedOrigins)`

**原因**：`HF_SPACE_DOMAIN` 环境变量配置错误

**正确配置**：
| 错误写法 | 正确写法 |
|----------|----------|
| `https://ceshi001awdhg-ceshi-claw.hf.space/` | `ceshi001awdhg-ceshi-claw` |
| `ceshi001awdhg-ceshi-claw.hf.space` | `ceshi001awdhg-ceshi-claw` |
| `/ceshi001awdhg-ceshi-claw` | `ceshi001awdhg-ceshi-claw` |

**注意**：`HF_SPACE_DOMAIN` 只需要 Space 名称，**不要包含** `https://`、`/` 或 `.hf.space`。

### 飞书无法连接

- 检查 App ID/Secret 是否正确
- 确认事件订阅配置
- 检查网络连通性

---

## 参考资料

- [OpenClaw 官方文档](https://docs.openclaw.ai/)
- [飞书开放平台](https://open.feishu.cn/)

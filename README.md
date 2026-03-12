# OpenClaw HuggingFace 部署指南

> OpenClaw AI Gateway 官方镜像部署到 HuggingFace Spaces，支持飞书、钉钉和数据同步。

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
| `HF_SPACE_DOMAIN` | HuggingFace Space 名称（不带 .hf.space） | `your-space-name` |
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

#### 钉钉（可选）

| 变量名 | 说明 |
|--------|------|
| `DINGTALK_ENABLED` | `true` 或 `false` |
| `DINGTALK_CLIENT_ID` | 钉钉 AppKey |
| `DINGTALK_CLIENT_SECRET` | 钉钉 AppSecret |
| `DINGTALK_ROBOT_CODE` | 钉钉机器人 Code |
| `DINGTALK_CORP_ID` | 钉钉企业 ID |

---

## 飞书配置

### 1. 创建飞书应用

1. 访问 [飞书开放平台](https://open.feishu.cn/)
2. 创建企业自建应用
3. 获取 `App ID` 和 `App Secret`

### 2. 配置事件订阅

1. 在应用设置中启用事件订阅
2. 订阅以下事件：
   - `im.message.receive_v1` (接收消息)
   - `im.chat.member.added_v1` (群成员添加)
3. 模式选择：**Stream 模式**

### 3. 配置机器人权限

1. 添加机器人能力
2. 获取机器人 Token（用于代码验证）

### 4. 配置环境变量

```
FEISHU_ENABLED=true
FEISHU_APP_ID=cli_xxxxxxxxxxxx
FEISHU_APP_SECRET=xxxxxxxxxxxx
```

---

## 钉钉配置

### 1. 创建钉钉应用

1. 访问 [钉钉开放平台](https://open.dingtalk.com/)
2. 创建**企业内部应用**
3. 获取 `AppKey` 和 `AppSecret`

### 2. 配置机器人

1. 添加机器人能力
2. 获取机器人 Code
3. 记录企业 ID（CorpID）

### 3. 配置环境变量

```
DINGTALK_ENABLED=true
DINGTALK_CLIENT_ID=dingxxxxxxxx
DINGTALK_CLIENT_SECRET=xxxxxxxxxxxx
DINGTALK_ROBOT_CODE=xxxxxxxx
DINGTALK_CORP_ID=xxxxxxxx
```

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
     -e HF_SPACE_DOMAIN=your-space \
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

## 飞书/钉钉使用

1. 在飞书/钉钉中搜索机器人
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

### 飞书/钉钉无法连接

- 检查 App ID/Secret 是否正确
- 确认事件订阅配置
- 检查网络连通性

---

## 参考资料

- [OpenClaw 官方文档](https://docs.openclaw.ai/)
- [飞书开放平台](https://open.feishu.cn/)
- [钉钉开放平台](https://open.dingtalk.com/)

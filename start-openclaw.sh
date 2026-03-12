#!/bin/bash
set -e

echo "=========================================="
echo "OpenClaw Gateway 启动中..."
echo "=========================================="

# 创建必要目录在根用户的主目录中 (OpenClaw 默认使用 $HOME/.openclaw)
mkdir -p /root/.openclaw/sessions
mkdir -p /root/.openclaw/workspace

# HuggingFace 数据恢复
echo "--- [INIT] 检查 HuggingFace 数据恢复 ---"
python3 /usr/local/bin/sync.py restore

# 检查是否有数据（如果没有则标记需要初始备份）
if [ ! -f /root/.openclaw/openclaw.json ]; then
    echo "--- [INIT] 无历史数据，需要初始备份 ---"
    NEED_INITIAL_UPLOAD=true
fi

# 清理 API Base 地址
CLEAN_BASE=$(echo "$OPENAI_API_BASE" | sed "s|/chat/completions||g" | sed "s|/v1/|/v1|g" | sed "s|/v1$|/v1|g")

# 生成 openclaw.json 配置文件
echo "--- [INIT] 生成配置文件 ---"

# HuggingFace Space 域名（必填，用户需要在 HuggingFace Space 设置中配置此环境变量）
HF_SPACE_DOMAIN="${HF_SPACE_DOMAIN:-}"

if [ -z "$HF_SPACE_DOMAIN" ]; then
    echo "ERROR: HF_SPACE_DOMAIN environment variable is required!"
    echo "Please set HF_SPACE_DOMAIN to your HuggingFace Space name (without .hf.space)"
    echo "Example: HF_SPACE_DOMAIN=your-space-name"
    exit 1
fi

# 根据是否启用钉钉生成不同的配置文件
if [ "${DINGTALK_ENABLED:-false}" = "true" ]; then
    cat > /root/.openclaw/openclaw.json <<EOF
{
  "models": {
    "providers": {
      "siliconflow": {
        "baseUrl": "$CLEAN_BASE",
        "apiKey": "$OPENAI_API_KEY",
        "api": "openai-completions",
        "models": [{ "id": "$MODEL", "name": "DeepSeek", "contextWindow": 128000 }]
      }
    }
  },
  "agents": { "defaults": { "model": { "primary": "siliconflow/$MODEL" } } },
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": ${PORT:-7860},
    "trustedProxies": ["*"],
    "auth": { "mode": "token", "token": "$OPENCLAW_GATEWAY_PASSWORD" },
    "controlUi": { 
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true,
      "allowedOrigins": ["https://${HF_SPACE_DOMAIN}.hf.space", "https://*.hf.space", "https://*.huggingface.co", "http://localhost:*", "http://127.0.0.1:*"]
    }
  },
  "channels": {
    "feishu": {
      "enabled": ${FEISHU_ENABLED:-false},
      "appId": "$FEISHU_APP_ID",
      "appSecret": "$FEISHU_APP_SECRET",
      "dmPolicy": "open"
    },
    "dingtalk": {
      "enabled": true,
      "clientId": "$DINGTALK_CLIENT_ID",
      "clientSecret": "$DINGTALK_CLIENT_SECRET",
      "robotCode": "$DINGTALK_ROBOT_CODE",
      "corpId": "$DINGTALK_CORP_ID"
    }
  }
}
EOF
else
    cat > /root/.openclaw/openclaw.json <<EOF
{
  "models": {
    "providers": {
      "siliconflow": {
        "baseUrl": "$CLEAN_BASE",
        "apiKey": "$OPENAI_API_KEY",
        "api": "openai-completions",
        "models": [{ "id": "$MODEL", "name": "DeepSeek", "contextWindow": 128000 }]
      }
    }
  },
  "agents": { "defaults": { "model": { "primary": "siliconflow/$MODEL" } } },
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": ${PORT:-7860},
    "trustedProxies": ["*"],
    "auth": { "mode": "token", "token": "$OPENCLAW_GATEWAY_PASSWORD" },
    "controlUi": { 
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true,
      "allowedOrigins": ["https://${HF_SPACE_DOMAIN}.hf.space", "https://*.hf.space", "https://*.huggingface.co", "http://localhost:*", "http://127.0.0.1:*"]
    }
  },
  "channels": {
    "feishu": {
      "enabled": ${FEISHU_ENABLED:-false},
      "appId": "$FEISHU_APP_ID",
      "appSecret": "$FEISHU_APP_SECRET",
      "dmPolicy": "open"
    }
  }
}
EOF
fi

echo "--- [INIT] 配置完成 ---"
cat /root/.openclaw/openclaw.json | head -20

# 如果没有备份，执行初始上传
if [ "$NEED_INITIAL_UPLOAD" = "true" ]; then
    echo "--- [INIT] 执行初始备份到 HuggingFace ---"
    python3 /usr/local/bin/sync.py backup
fi

# 启动定时备份进程 (每 3 小时执行一次)
echo "--- [INIT] 启动定时备份 ---"
(while true; do sleep 10800; python3 /usr/local/bin/sync.py backup; done) &

# 修复配置并启动网关
echo "--- [INIT] 启动 OpenClaw Gateway ---"

# 运行 doctor 修复配置
openclaw doctor --fix

# 安装钉钉插件（如果启用）
if [ "${DINGTALK_ENABLED:-false}" = "true" ]; then
    echo "--- [INIT] 安装钉钉插件 ---"
    openclaw plugins install @soimy/dingtalk || echo "--- [WARN] 钉钉插件安装失败，可能已安装 ---"
    sleep 2
fi

exec node openclaw.mjs gateway --allow-unconfigured

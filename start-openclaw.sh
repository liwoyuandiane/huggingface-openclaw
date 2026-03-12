#!/bin/bash
set -e

echo "=========================================="
echo "OpenClaw Gateway 启动中..."
echo "=========================================="

mkdir -p /root/.openclaw/sessions
mkdir -p /root/.openclaw/workspace

echo "--- [INIT] 检查 HuggingFace 数据恢复 ---"
python3 /usr/local/bin/sync.py restore

if [ ! -f /root/.openclaw/openclaw.json ]; then
    echo "--- [INIT] 无历史数据，需要初始备份 ---"
    NEED_INITIAL_UPLOAD=true
fi

CLEAN_BASE=$(echo "$OPENAI_API_BASE" | sed "s|/chat/completions||g" | sed "s|/v1/|/v1|g" | sed "s|/v1$|/v1|g")

echo "--- [INIT] 生成配置文件 ---"

HF_SPACE_DOMAIN="${HF_SPACE_DOMAIN:-}"

if [ -z "$HF_SPACE_DOMAIN" ]; then
    echo "ERROR: HF_SPACE_DOMAIN environment variable is required!"
    echo "Please set HF_SPACE_DOMAIN to your HuggingFace Space name (without .hf.space)"
    echo "Example: HF_SPACE_DOMAIN=your-space-name"
    exit 1
fi

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

echo "--- [INIT] 配置完成 ---"
cat /root/.openclaw/openclaw.json | head -20

if [ "$NEED_INITIAL_UPLOAD" = "true" ]; then
    echo "--- [INIT] 执行初始备份到 HuggingFace ---"
    python3 /usr/local/bin/sync.py backup
fi

echo "--- [INIT] 启动定时备份 ---"
(while true; do sleep 1200; python3 /usr/local/bin/sync.py backup; done) &

echo "--- [INIT] 启动 OpenClaw Gateway ---"

openclaw doctor --fix

exec node openclaw.mjs gateway --allow-unconfigured

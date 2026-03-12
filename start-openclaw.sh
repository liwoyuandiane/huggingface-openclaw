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

echo "--- [INIT] 生成配置文件 ---"

HF_SPACE_DOMAIN="${HF_SPACE_DOMAIN:-}"
if [ -z "$HF_SPACE_DOMAIN" ]; then
    echo "ERROR: HF_SPACE_DOMAIN environment variable is required!"
    exit 1
fi

# ==================== 模型配置 ====================
PRIMARY_API_BASE=$(echo "$OPENAI_API_BASE" | sed "s|/chat/completions||g" | sed "s|/v1/|/v1|g" | sed "s|/v1$|/v1|g")
PRIMARY_API_KEY="${OPENAI_API_KEY:-}"
PRIMARY_MODEL="${MODEL:-nvidia/nemotron-3-super-120b-a12b}"

# 从 API URL 提取 Provider 名称 (移除 https:// 和路径)
PRIMARY_PROVIDER=$(echo "$PRIMARY_API_BASE" | sed 's|^https://||' | sed 's|/.*$||')

FALLBACK_MODES="${FALLBACK_MODEL:-}"
FALLBACK_API_BASE=$(echo "${FALLBACK_OPENAI_API_BASE:-$OPENAI_API_BASE}" | sed "s|/chat/completions||g" | sed "s|/v1/|/v1|g" | sed "s|/v1$|/v1|g")
FALLBACK_API_KEY="${FALLBACK_OPENAI_API_KEY:-$OPENAI_API_KEY}"
FALLBACK_USE_SEPARATE=false
if [ "$FALLBACK_API_BASE" != "$PRIMARY_API_BASE" ] || [ "$FALLBACK_API_KEY" != "$PRIMARY_API_KEY" ]; then
    FALLBACK_USE_SEPARATE=true
fi

VISION_MODEL="${VISION_MODEL:-}"
VISION_API_BASE=$(echo "${VISION_API_BASE:-$OPENAI_API_BASE}" | sed "s|/chat/completions||g" | sed "s|/v1/|/v1|g" | sed "s|/v1$|/v1|g")
VISION_API_KEY="${VISION_API_KEY:-$OPENAI_API_KEY}"
VISION_USE_SEPARATE=false
if [ "$VISION_API_BASE" != "$PRIMARY_API_BASE" ] || [ "$VISION_API_KEY" != "$PRIMARY_API_KEY" ]; then
    VISION_USE_SEPARATE=true
fi

# 从视觉 API URL 提取 Provider 名称
VISION_PROVIDER=$(echo "$VISION_API_BASE" | sed 's|^https://||' | sed 's|/.*$||')

echo "--- [INIT] 主模型: $PRIMARY_MODEL (Provider: $PRIMARY_PROVIDER)"
[ -n "$FALLBACK_MODES" ] && echo "--- [INIT] 备用模型: $FALLBACK_MODES"
[ -n "$VISION_MODEL" ] && echo "--- [INIT] 视觉模型: $VISION_MODEL (Provider: $VISION_PROVIDER)"

# ==================== 生成 Provider 配置 ====================
PROVIDERS_JSON="\"$PRIMARY_PROVIDER\": {"
PROVIDERS_JSON="$PROVIDERS_JSON \"baseUrl\": \"$PRIMARY_API_BASE\","
PROVIDERS_JSON="$PROVIDERS_JSON \"apiKey\": \"$PRIMARY_API_KEY\","
PROVIDERS_JSON="$PROVIDERS_JSON \"api\": \"openai-completions\","
PROVIDERS_JSON="$PROVIDERS_JSON \"models\": ["
PROVIDERS_JSON="$PROVIDERS_JSON { \"id\": \"$PRIMARY_MODEL\", \"name\": \"主模型\", \"contextWindow\": 128000 }"
if [ -n "$FALLBACK_MODES" ]; then
    IFS=',' read -ra FALLBACK_ARRAY <<< "$FALLBACK_MODES"
    for F_ITEM in "${FALLBACK_ARRAY[@]}"; do
        PROVIDERS_JSON="$PROVIDERS_JSON, { \"id\": \"$F_ITEM\", \"name\": \"备用模型\", \"contextWindow\": 128000 }"
    done
fi
# 如果视觉模型使用主API，添加到主模型列表
if [ -n "$VISION_MODEL" ] && [ "$VISION_USE_SEPARATE" = false ]; then
    PROVIDERS_JSON="$PROVIDERS_JSON, { \"id\": \"$VISION_MODEL\", \"name\": \"视觉模型\", \"contextWindow\": 128000, \"input\": [\"text\", \"image\"] }"
fi
PROVIDERS_JSON="$PROVIDERS_JSON ]"
PROVIDERS_JSON="$PROVIDERS_JSON }"

# 备用 API Provider
if [ -n "$FALLBACK_MODES" ] && [ "$FALLBACK_USE_SEPARATE" = true ]; then
    FALLBACK_PROVIDER=$(echo "$FALLBACK_API_BASE" | sed 's|^https://||' | sed 's|/.*$||')
    echo "--- [INIT] 备用模型使用独立 API: $FALLBACK_API_BASE (Provider: $FALLBACK_PROVIDER)"
    FALLBACK_MODELS_JSON=""
    IFS=',' read -ra FALLBACK_ARRAY <<< "$FALLBACK_MODES"
    FIRST=true
    for F_ITEM in "${FALLBACK_ARRAY[@]}"; do
        [ "$FIRST" = true ] && FIRST=false || FALLBACK_MODELS_JSON="$FALLBACK_MODELS_JSON, "
        FALLBACK_MODELS_JSON="$FALLBACK_MODELS_JSON{ \"id\": \"$F_ITEM\", \"name\": \"备用模型\", \"contextWindow\": 128000 }"
    done
    
    PROVIDERS_JSON="$PROVIDERS_JSON, \"$FALLBACK_PROVIDER\": {"
    PROVIDERS_JSON="$PROVIDERS_JSON \"baseUrl\": \"$FALLBACK_API_BASE\","
    PROVIDERS_JSON="$PROVIDERS_JSON \"apiKey\": \"$FALLBACK_API_KEY\","
    PROVIDERS_JSON="$PROVIDERS_JSON \"api\": \"openai-completions\","
    PROVIDERS_JSON="$PROVIDERS_JSON \"models\": [$FALLBACK_MODELS_JSON]"
    PROVIDERS_JSON="$PROVIDERS_JSON }"
fi

# 视觉模型 Provider (独立 API)
if [ -n "$VISION_MODEL" ] && [ "$VISION_USE_SEPARATE" = true ]; then
    echo "--- [INIT] 视觉模型使用独立 API: $VISION_API_BASE (Provider: $VISION_PROVIDER)"
    PROVIDERS_JSON="$PROVIDERS_JSON, \"$VISION_PROVIDER\": {"
    PROVIDERS_JSON="$PROVIDERS_JSON \"baseUrl\": \"$VISION_API_BASE\","
    PROVIDERS_JSON="$PROVIDERS_JSON \"apiKey\": \"$VISION_API_KEY\","
    PROVIDERS_JSON="$PROVIDERS_JSON \"api\": \"openai-completions\","
    PROVIDERS_JSON="$PROVIDERS_JSON \"models\": [{ \"id\": \"$VISION_MODEL\", \"name\": \"视觉模型\", \"contextWindow\": 128000, \"input\": [\"text\", \"image\"] }]"
    PROVIDERS_JSON="$PROVIDERS_JSON }"
fi

# ==================== 生成配置文件 ====================
# 飞书频道配置
FEISHU_ENABLED="${FEISHU_ENABLED:-false}"

# 首先构建 fallbacks 数组
FALLBACK_MODELS_JSON=""
if [ -n "$FALLBACK_MODES" ]; then
    IFS=',' read -ra FALLBACK_ARRAY <<< "$FALLBACK_MODES"
    for F_ITEM in "${FALLBACK_ARRAY[@]}"; do
        if [ -z "$FALLBACK_MODELS_JSON" ]; then
            FALLBACK_MODELS_JSON="\"$PRIMARY_PROVIDER/$F_ITEM\""
        else
            FALLBACK_MODELS_JSON="$FALLBACK_MODELS_JSON, \"$PRIMARY_PROVIDER/$F_ITEM\""
        fi
    done
fi

# 构建 AGENTS_CONFIG
AGENTS_CONFIG="\"defaults\": {"
AGENTS_CONFIG="$AGENTS_CONFIG \"model\": {"
AGENTS_CONFIG="$AGENTS_CONFIG \"primary\": \"$PRIMARY_PROVIDER/$PRIMARY_MODEL\""
if [ -n "$FALLBACK_MODELS_JSON" ]; then
    AGENTS_CONFIG="$AGENTS_CONFIG, \"fallbacks\": [$FALLBACK_MODELS_JSON]"
fi
AGENTS_CONFIG="$AGENTS_CONFIG }"

# 添加 imageModel（如果视觉模型使用独立 API）
if [ -n "$VISION_MODEL" ] && [ "$VISION_USE_SEPARATE" = true ]; then
    AGENTS_CONFIG="$AGENTS_CONFIG, \"imageModel\": {"
    AGENTS_CONFIG="$AGENTS_CONFIG \"primary\": \"$VISION_PROVIDER/$VISION_MODEL\""
    AGENTS_CONFIG="$AGENTS_CONFIG }"
fi

AGENTS_CONFIG="$AGENTS_CONFIG }"

cat > /root/.openclaw/openclaw.json <<EOF
{
  "models": {
    "providers": {
      $PROVIDERS_JSON
    }
  },
  "agents": {
    $AGENTS_CONFIG
  },
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 7860,
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
cat /root/.openclaw/openclaw.json | head -30

if [ "$NEED_INITIAL_UPLOAD" = "true" ]; then
    echo "--- [INIT] 执行初始备份到 HuggingFace ---"
    python3 /usr/local/bin/sync.py backup
fi

echo "--- [INIT] 启动定时备份 ---"
(while true; do sleep 1200; python3 /usr/local/bin/sync.py backup; done) &

echo "--- [INIT] 启动 OpenClaw Gateway ---"

openclaw doctor --fix

exec node openclaw.mjs gateway --allow-unconfigured

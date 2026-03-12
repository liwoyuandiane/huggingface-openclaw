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
# 主 API 配置
PRIMARY_API_BASE=$(echo "$OPENAI_API_BASE" | sed "s|/chat/completions||g" | sed "s|/v1/|/v1|g" | sed "s|/v1$|/v1|g")
PRIMARY_API_KEY="${OPENAI_API_KEY:-}"
PRIMARY_MODEL="${MODEL:-nvidia/nemotron-3-super-120b-a12b}"

# 备用模型配置（可选独立 API）
FALLBACK_MODELS="${FALLBACK_MODEL:-}"
FALLBACK_API_BASE=$(echo "${FALLBACK_OPENAI_API_BASE:-$OPENAI_API_BASE}" | sed "s|/chat/completions||g" | sed "s|/v1/|/v1|g" | sed "s|/v1$|/v1|g")
FALLBACK_API_KEY="${FALLBACK_OPENAI_API_KEY:-$OPENAI_API_KEY}"
FALLBACK_USE_SEPARATE=false
if [ "$FALLBACK_API_BASE" != "$PRIMARY_API_BASE" ] || [ "$FALLBACK_API_KEY" != "$PRIMARY_API_KEY" ]; then
    FALLBACK_USE_SEPARATE=true
fi

# 视觉模型专用 API 配置（可选）
VISION_MODEL="${VISION_MODEL:-}"
VISION_API_BASE=$(echo "${VISION_API_BASE:-$OPENAI_API_BASE}" | sed "s|/chat/completions||g" | sed "s|/v1/|/v1|g" | sed "s|/v1$|/v1|g")
VISION_API_KEY="${VISION_API_KEY:-$OPENAI_API_KEY}"
VISION_USE_SEPARATE=false
if [ "$VISION_API_BASE" != "$PRIMARY_API_BASE" ] || [ "$VISION_API_KEY" != "$PRIMARY_API_KEY" ]; then
    VISION_USE_SEPARATE=true
fi

echo "--- [INIT] 主模型: $PRIMARY_MODEL (API: $PRIMARY_API_BASE)"
[ -n "$FALLBACK_MODELS" ] && echo "--- [INIT] 备用模型: $FALLBACK_MODELS"
[ -n "$VISION_MODEL" ] && echo "--- [INIT] 视觉模型: $VISION_MODEL"

# ==================== 生成 Provider 配置 ====================
# 主模型
MODELS_JSON="[{ \"id\": \"$PRIMARY_MODEL\", \"name\": \"主模型\", \"contextWindow\": 128000 }]"

# 主 Provider
PROVIDERS_JSON="\"siliconflow_primary\": {"
PROVIDERS_JSON="$PROVIDERS_JSON \"baseUrl\": \"$PRIMARY_API_BASE\","
PROVIDERS_JSON="$PROVIDERS_JSON \"apiKey\": \"$PRIMARY_API_KEY\","
PROVIDERS_JSON="$PROVIDERS_JSON \"api\": \"openai-completions\","
PROVIDERS_JSON="$PROVIDERS_JSON \"models\": [$MODELS_JSON]"
PROVIDERS_JSON="$PROVIDERS_JSON }"

# 备用模型 Provider
if [ -n "$FALLBACK_MODELS" ]; then
    if [ "$FALLBACK_USE_SEPARATE" = true ]; then
        echo "--- [INIT] 备用模型使用独立 API: $FALLBACK_API_BASE"
        FALLBACK_MODELS_JSON=""
        IFS=',' read -ra FALLBACK_ARRAY <<< "$FALLBACK_MODELS"
        FIRST=true
        for F_ITEM in "${FALLBACK_ARRAY[@]}"; do
            [ "$FIRST" = true ] && FIRST=false || FALLBACK_MODELS_JSON="$FALLBACK_MODELS_JSON, "
            FALLBACK_MODELS_JSON="$FALLBACK_MODELS_JSON{ \"id\": \"$F_ITEM\", \"name\": \"备用模型\", \"contextWindow\": 128000 }"
        done
        
        PROVIDERS_JSON="$PROVIDERS_JSON, \"siliconflow_fallback\": {"
        PROVIDERS_JSON="$PROVIDERS_JSON \"baseUrl\": \"$FALLBACK_API_BASE\","
        PROVIDERS_JSON="$PROVIDERS_JSON \"apiKey\": \"$FALLBACK_API_KEY\","
        PROVIDERS_JSON="$PROVIDERS_JSON \"api\": \"openai-completions\","
        PROVIDERS_JSON="$PROVIDERS_JSON \"models\": [$FALLBACK_MODELS_JSON]"
        PROVIDERS_JSON="$PROVIDERS_JSON }"
    else
        IFS=',' read -ra FALLBACK_ARRAY <<< "$FALLBACK_MODELS"
        for F_ITEM in "${FALLBACK_ARRAY[@]}"; do
            MODELS_JSON="$MODELS_JSON, { \"id\": \"$F_ITEM\", \"name\": \"备用模型\", \"contextWindow\": 128000 }"
        done
    fi
fi

# 视觉模型 Provider
if [ -n "$VISION_MODEL" ]; then
    if [ "$VISION_USE_SEPARATE" = true ]; then
        echo "--- [INIT] 视觉模型使用独立 API: $VISION_API_BASE"
        VISION_MODELS_JSON=""
        IFS=',' read -ra VISION_ARRAY <<< "$VISION_MODEL"
        FIRST=true
        for V_ITEM in "${VISION_ARRAY[@]}"; do
            [ "$FIRST" = true ] && FIRST=false || VISION_MODELS_JSON="$VISION_MODELS_JSON, "
            VISION_MODELS_JSON="$VISION_MODELS_JSON{ \"id\": \"$V_ITEM\", \"name\": \"视觉模型\", \"contextWindow\": 128000 }"
        done
        
        PROVIDERS_JSON="$PROVIDERS_JSON, \"siliconflow_vision\": {"
        PROVIDERS_JSON="$PROVIDERS_JSON \"baseUrl\": \"$VISION_API_BASE\","
        PROVIDERS_JSON="$PROVIDERS_JSON \"apiKey\": \"$VISION_API_KEY\","
        PROVIDERS_JSON="$PROVIDERS_JSON \"api\": \"openai-completions\","
        PROVIDERS_JSON="$PROVIDERS_JSON \"models\": [$VISION_MODELS_JSON]"
        PROVIDERS_JSON="$PROVIDERS_JSON }"
    fi
fi

# ==================== 生成 Agent Model 配置 ====================
MODEL_CONFIG="\"primary\": \"siliconflow_primary/$PRIMARY_MODEL\""

# 备用模型
if [ -n "$FALLBACK_MODELS" ]; then
    FALLBACK_JSON='"fallback": ['
    FIRST=true
    IFS=',' read -ra FALLBACK_ARRAY <<< "$FALLBACK_MODELS"
    for F_ITEM in "${FALLBACK_ARRAY[@]}"; do
        [ "$FIRST" = true ] && FIRST=false || FALLBACK_JSON="$FALLBACK_JSON, "
        if [ "$FALLBACK_USE_SEPARATE" = true ]; then
            FALLBACK_JSON="$FALLBACK_JSON\"siliconflow_fallback/$F_ITEM\""
        else
            FALLBACK_JSON="$FALLBACK_JSON\"siliconflow_primary/$F_ITEM\""
        fi
    done
    FALLBACK_JSON="$FALLBACK_JSON]"
    MODEL_CONFIG="$MODEL_CONFIG, $FALLBACK_JSON"
fi

# 视觉模型
if [ -n "$VISION_MODEL" ]; then
    if [ "$VISION_USE_SEPARATE" = true ]; then
        # 取第一个视觉模型
        VISION_FIRST=$(echo "$VISION_MODEL" | cut -d',' -f1)
        MODEL_CONFIG="$MODEL_CONFIG, \"visionModel\": \"siliconflow_vision/$VISION_FIRST\""
    else
        VISION_FIRST=$(echo "$VISION_MODEL" | cut -d',' -f1)
        MODEL_CONFIG="$MODEL_CONFIG, \"visionModel\": \"siliconflow_primary/$VISION_FIRST\""
    fi
fi

# ==================== 生成配置文件 ====================
cat > /root/.openclaw/openclaw.json <<EOF
{
  "models": {
    "providers": {
      $PROVIDERS_JSON
    }
  },
  "agents": { "defaults": { "model": { $MODEL_CONFIG } } },
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 7860,
    "trustedProxies": ["*"],
    "auth": { "mode": "token", "token": "\$OPENCLAW_GATEWAY_PASSWORD" },
    "controlUi": { 
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true,
      "allowedOrigins": ["https://\${HF_SPACE_DOMAIN}.hf.space", "https://*.hf.space", "https://*.huggingface.co", "http://localhost:*", "http://127.0.0.1:*"]
    }
  },
  "channels": {
    "feishu": {
      "enabled": false,
      "appId": "\$FEISHU_APP_ID",
      "appSecret": "\$FEISHU_APP_SECRET",
      "dmPolicy": "open"
    }
  }
}
EOF

echo "--- [INIT] 配置完成 ---"
cat /root/.openclaw/openclaw.json | head -50

if [ "$NEED_INITIAL_UPLOAD" = "true" ]; then
    echo "--- [INIT] 执行初始备份到 HuggingFace ---"
    python3 /usr/local/bin/sync.py backup
fi

echo "--- [INIT] 启动定时备份 ---"
(while true; do sleep 1200; python3 /usr/local/bin/sync.py backup; done) &

echo "--- [INIT] 启动 OpenClaw Gateway ---"

openclaw doctor --fix

exec node openclaw.mjs gateway --allow-unconfigured

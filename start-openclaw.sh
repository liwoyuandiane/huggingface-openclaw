#!/bin/bash
set -e

# ============================================================
# 常量配置
# ============================================================
SYNC_INTERVAL="${SYNC_INTERVAL:-60}"   # 备份间隔（秒），默认 1 分钟
BACKUP_PID_FILE="/tmp/sync_backup.pid"
LOG_FILE="/root/.openclaw/sync.log"

# ============================================================
# DNS-over-HTTPS 配置（解决 HF Spaces DNS 屏蔽问题）
# ============================================================
setup_dns_over_https() {
    echo "--- [DNS] 配置 DNS-over-HTTPS ---"
    
    # 检查是否启用（默认启用）
    if [ "${DOH_ENABLED:-true}" != "true" ]; then
        echo "--- [DNS] DNS-over-HTTPS 已禁用 ---"
        return
    fi
    
    # 安装 dnscrypt-proxy（如果可用）
    if command -v dnscrypt-proxy &> /dev/null; then
        echo "--- [DNS] 使用 dnscrypt-proxy ---"
        # dnscrypt-proxy 会自动配置
        return
    fi
    
    # 备用方案：配置 /etc/hosts 解决常见被屏蔽域名
    # 这些 IP 可能会变化，建议定期更新
    local hosts_entries=(
        # Telegram API（常见备用 IP）
        "149.154.167.220 api.telegram.org"
        "149.154.167.250 api.telegram.org"
    )
    
    local added=0
    for entry in "${hosts_entries[@]}"; do
        local ip=$(echo "$entry" | awk '{print $1}')
        local domain=$(echo "$entry" | awk '{print $2}')
        
        # 检查是否已存在
        if ! grep -q "$domain" /etc/hosts 2>/dev/null; then
            echo "$entry" >> /etc/hosts
            added=$((added + 1))
        fi
    done
    
    if [ $added -gt 0 ]; then
        echo "--- [DNS] 已添加 $added 条 hosts 记录 ---"
    else
        echo "--- [DNS] hosts 记录已存在，跳过 ---"
    fi
}

# ============================================================
# 信号处理函数
# ============================================================
cleanup() {
    echo "--- [SHUTDOWN] 收到终止信号，正在清理... ---"
    if [ -f "$BACKUP_PID_FILE" ]; then
        BACKUP_PID=$(cat "$BACKUP_PID_FILE")
        if kill -0 "$BACKUP_PID" 2>/dev/null; then
            echo "--- [SHUTDOWN] 停止备份进程 (PID: $BACKUP_PID) ---"
            kill "$BACKUP_PID" 2>/dev/null || true
        fi
        rm -f "$BACKUP_PID_FILE"
    fi
    exit 0
}

# 注册信号处理
trap cleanup SIGTERM SIGINT SIGQUIT

# ============================================================
# 备份守护函数
# ============================================================
backup_daemon() {
    local count=0
    while true; do
        sleep $SYNC_INTERVAL
        count=$((count + 1))
        echo "--- [BACKUP] 第 $count 次定时备份开始 ($(date '+%Y-%m-%d %H:%M:%S')) ---" | tee -a "$LOG_FILE"
        python3 /usr/local/bin/sync.py backup 2>&1 | tee -a "$LOG_FILE"
        echo "--- [BACKUP] 第 $count 次定时备份完成 ---" | tee -a "$LOG_FILE"
    done
}

# ============================================================
# 主启动流程
# ============================================================
echo "=========================================="
echo "OpenClaw Gateway 启动中..."
echo "=========================================="

# 配置 DNS-over-HTTPS
setup_dns_over_https

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
# 优先使用 ModelScope（如果设置了 MODELSCOPE_API_KEY）
# 否则使用传统的 OPENAI_API_KEY 配置

# ModelScope 配置
MODELSCOPE_API_KEY="${MODELSCOPE_API_KEY:-}"
MODELSCOPE_MODEL="${MODELSCOPE_MODEL:-moonshotai/Kimi-K2.5}"
MODELSCOPE_API_BASE="https://api-inference.modelscope.cn/v1"

# 备用模型配置（先设置默认值）
FALLBACK_MODES="${FALLBACK_MODEL:-}"
FALLBACK_OPENAI_API_BASE="${FALLBACK_OPENAI_API_BASE:-}"
FALLBACK_OPENAI_API_KEY="${FALLBACK_OPENAI_API_KEY:-}"
OPENAI_API_BASE="${OPENAI_API_BASE:-}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"

if [ -n "$MODELSCOPE_API_KEY" ]; then
    # 使用 ModelScope 作为主模型
    echo "--- [INIT] 使用 ModelScope 作为默认模型 ---"
    PRIMARY_API_BASE="$MODELSCOPE_API_BASE"
    PRIMARY_API_KEY="$MODELSCOPE_API_KEY"
    PRIMARY_MODEL="$MODELSCOPE_MODEL"
    PRIMARY_PROVIDER="modelscope"
    echo "--- [INIT] 主模型: $PRIMARY_MODEL (Provider: $PRIMARY_PROVIDER, API: $PRIMARY_API_BASE)"
    
    # 备用模型默认使用 ModelScope
    if [ -z "$FALLBACK_OPENAI_API_BASE" ]; then
        FALLBACK_API_BASE="$MODELSCOPE_API_BASE"
        FALLBACK_API_KEY="$MODELSCOPE_API_KEY"
    else
        FALLBACK_API_BASE=$(echo "$FALLBACK_OPENAI_API_BASE" | sed "s|/chat/completions||g" | sed "s|/v1/|/v1|g" | sed "s|/v1$||g")
        FALLBACK_API_KEY="$FALLBACK_OPENAI_API_KEY"
    fi
else
    # 使用传统 OpenAI 兼容 API 配置
    echo "--- [INIT] 使用自定义 API 作为主模型 ---"
    PRIMARY_API_BASE=$(echo "${OPENAI_API_BASE:-}" | sed "s|/chat/completions||g" | sed "s|/v1/|/v1|g" | sed "s|/v1$||g")
    PRIMARY_API_KEY="$OPENAI_API_KEY"
    PRIMARY_MODEL="${MODEL:-nvidia/nemotron-3-super-120b-a12b}"
    PRIMARY_PROVIDER=$(echo "$PRIMARY_API_BASE" | sed 's|^https://||' | sed 's|/.*$||')
    echo "--- [INIT] 主模型: $PRIMARY_MODEL (Provider: $PRIMARY_PROVIDER)"
    
    FALLBACK_API_BASE=$(echo "${FALLBACK_OPENAI_API_BASE:-$OPENAI_API_BASE}" | sed "s|/chat/completions||g" | sed "s|/v1/|/v1|g" | sed "s|/v1$||g")
    FALLBACK_API_KEY="${FALLBACK_OPENAI_API_KEY:-$OPENAI_API_KEY}"
fi
if [ "$FALLBACK_API_BASE" != "$PRIMARY_API_BASE" ] || [ "$FALLBACK_API_KEY" != "$PRIMARY_API_KEY" ]; then
    FALLBACK_USE_SEPARATE=true
fi

# 视觉模型配置
VISION_MODEL="${VISION_MODEL:-}"
VISION_API_BASE="${VISION_API_BASE:-}"
VISION_API_KEY="${VISION_API_KEY:-}"

# 如果没有设置视觉模型，跳过
if [ -z "$VISION_MODEL" ]; then
    VISION_USE_SEPARATE=false
else
    # 如果没有单独配置视觉模型 API，默认使用主模型的 API
    if [ -z "$VISION_API_BASE" ]; then
        # 如果主模型是 ModelScope，视觉模型也使用 ModelScope
        if [ -n "$MODELSCOPE_API_KEY" ]; then
            VISION_API_BASE="$MODELSCOPE_API_BASE"
            VISION_API_KEY="$MODELSCOPE_API_KEY"
        else
            # 使用主模型的 API 配置
            VISION_API_BASE="$PRIMARY_API_BASE"
            VISION_API_KEY="$PRIMARY_API_KEY"
        fi
    else
        # 单独配置了视觉模型 API
        VISION_API_BASE=$(echo "$VISION_API_BASE" | sed "s|/chat/completions||g" | sed "s|/v1/|/v1|g" | sed "s|/v1$||g")
    fi
    
    # 视觉模型使用独立的 API（与主模型不同的 API 地址或 Key）
    if [ "$VISION_API_BASE" != "$PRIMARY_API_BASE" ] || [ "$VISION_API_KEY" != "$PRIMARY_API_KEY" ]; then
        VISION_USE_SEPARATE=true
    else
        # 使用相同 API，添加到主模型列表
        VISION_USE_SEPARATE=false
    fi
fi

# 从视觉 API URL 提取 Provider 名称
VISION_PROVIDER=$(echo "$VISION_API_BASE" | sed 's|^https://||' | sed 's|/.*$||')

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

# 钉钉频道配置
DINGTALK_ENABLED="${DINGTALK_ENABLED:-false}"
DINGTALK_CLIENT_ID="${DINGTALK_CLIENT_ID:-}"
DINGTALK_CLIENT_SECRET="${DINGTALK_CLIENT_SECRET:-}"
DINGTALK_ROBOT_CODE="${DINGTALK_ROBOT_CODE:-}"
DINGTALK_CORP_ID="${DINGTALK_CORP_ID:-}"

# 首先构建 fallbacks 数组
FALLBACK_MODELS_JSON=""
if [ -n "$FALLBACK_MODES" ]; then
    IFS=',' read -ra FALLBACK_ARRAY <<< "$FALLBACK_MODES"
    # 选择正确的 provider：如果是独立 API 用 FALLBACK_PROVIDER，否则用 PRIMARY_PROVIDER
    if [ "$FALLBACK_USE_SEPARATE" = true ]; then
        FALLBACK_PROVIDER_FOR_FALLBACKS="$FALLBACK_PROVIDER"
    else
        FALLBACK_PROVIDER_FOR_FALLBACKS="$PRIMARY_PROVIDER"
    fi
    for F_ITEM in "${FALLBACK_ARRAY[@]}"; do
        if [ -z "$FALLBACK_MODELS_JSON" ]; then
            FALLBACK_MODELS_JSON="\"$FALLBACK_PROVIDER_FOR_FALLBACKS/$F_ITEM\""
        else
            FALLBACK_MODELS_JSON="$FALLBACK_MODELS_JSON, \"$FALLBACK_PROVIDER_FOR_FALLBACKS/$F_ITEM\""
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

# 构建 channels 配置
CHANNELS_CONFIG="\"feishu\": {
      \"enabled\": ${FEISHU_ENABLED:-false},
      \"appId\": \"$FEISHU_APP_ID\",
      \"appSecret\": \"$FEISHU_APP_SECRET\",
      \"dmPolicy\": \"open\"
    }"

# 添加钉钉频道配置
if [ "$DINGTALK_ENABLED" = "true" ]; then
    echo "--- [INIT] 钉钉频道已启用 ---"
    CHANNELS_CONFIG="$CHANNELS_CONFIG,
    \"dingtalk\": {
      \"enabled\": true,
      \"clientId\": \"$DINGTALK_CLIENT_ID\",
      \"clientSecret\": \"$DINGTALK_CLIENT_SECRET\",
      \"robotCode\": \"$DINGTALK_ROBOT_CODE\",
      \"corpId\": \"$DINGTALK_CORP_ID\"
    }"
fi

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
      "allowedOrigins": ["https://*.hf.space", "https://*.huggingface.co", "http://localhost:*", "http://127.0.0.1:*", "https://${HF_SPACE_DOMAIN}.hf.space"]
    }
  },
  "channels": {
    $CHANNELS_CONFIG
  }
}
EOF

echo "--- [INIT] 配置完成 ---"
cat /root/.openclaw/openclaw.json | head -30

if [ "$NEED_INITIAL_UPLOAD" = "true" ]; then
    echo "--- [INIT] 执行初始备份到 HuggingFace ---"
    python3 /usr/local/bin/sync.py backup
fi

# ==================== 启动定时备份（带 PID 管理）====================
echo "--- [INIT] 启动定时备份守护进程 (间隔: ${SYNC_INTERVAL}秒) ---"
backup_daemon &
BACKUP_PID=$!
echo $BACKUP_PID > "$BACKUP_PID_FILE"
echo "--- [INIT] 备份进程已启动 (PID: $BACKUP_PID) ---"

echo "--- [INIT] 启动 OpenClaw Gateway ---"

# 运行 doctor 修复配置
openclaw doctor --fix

# 使用 openclaw config set 设置 allowedOrigins（更可靠的方式）
# 添加通配符和用户具体的域名
openclaw config set gateway.controlUi.allowedOrigins '["https://*.hf.space", "https://*.huggingface.co", "http://localhost:*", "http://127.0.0.1:*", "https://${HF_SPACE_DOMAIN}.hf.space"]'

# 重新写入配置文件作为备份
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
      "allowedOrigins": ["https://*.hf.space", "https://*.huggingface.co", "http://localhost:*", "http://127.0.0.1:*", "https://${HF_SPACE_DOMAIN}.hf.space"]
    }
  },
  "channels": {
    $CHANNELS_CONFIG
  }
}
EOF
echo "--- [INIT] 重新写入配置完成 ---"

exec node openclaw.mjs gateway --allow-unconfigured
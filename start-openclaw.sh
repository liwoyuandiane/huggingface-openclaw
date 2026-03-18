#!/bin/bash
set -e

# ============================================================
# 常量配置
# ============================================================
SYNC_INTERVAL="${SYNC_INTERVAL:-60}"   # 备份间隔（秒），默认 1 分钟
BACKUP_PID_FILE="/tmp/sync_backup.pid"
# 日志文件路径会在运行时根据 OPENCLAW_HOME 动态设置

# ============================================================
# DNS 配置（解决 HF Spaces DNS 屏蔽问题）
# ============================================================
setup_dns() {
    echo "--- [DNS] 配置 DNS ---"
    
    # 检查是否启用（默认启用）
    if [ "${DOH_ENABLED:-true}" != "true" ]; then
        echo "--- [DNS] DNS 配置已禁用 ---"
        return
    fi
    
    # 配置 Google DNS (8.8.8.8, 8.8.4.4)
    # 优先使用 /etc/resolv.conf，如果没有权限则创建新的 resolv.conf
    local dns_added=0
    
    # 检查是否已经有 Google DNS
    if ! grep -q "8.8.8.8" /etc/resolv.conf 2>/dev/null; then
        # 尝试备份并修改 resolv.conf
        if [ -w /etc/resolv.conf ] 2>/dev/null; then
            # 添加 Google DNS 到开头
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
            echo "nameserver 8.8.4.4" >> /etc/resolv.conf
            dns_added=1
        elif [ -w /etc ]; then
            # 创建新的 resolv.conf
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
            echo "nameserver 8.8.4.4" >> /etc/resolv.conf
            dns_added=1
        fi
    fi
    
    if [ $dns_added -eq 1 ]; then
        echo "--- [DNS] 已配置 Google DNS (8.8.8.8, 8.8.4.4) ---"
    else
        echo "--- [DNS] DNS 已配置，跳过 ---"
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
    # 动态设置日志路径
    local log_file="${OPENCLAW_HOME:-/root}/.openclaw/sync.log"
    local data_dir="${OPENCLAW_HOME:-/root}/.openclaw"
    local count=0
    
    # 第一次备份等待 10 分钟，让 Gateway 完全启动并稳定运行
    local first_delay=600
    echo "--- [BACKUP] 首次备份将在 ${first_delay} 秒(10分钟)后执行 ---" | tee -a "$log_file"
    sleep $first_delay
    
    while true; do
        count=$((count + 1))
        echo "--- [BACKUP] 第 $count 次定时备份开始 ($(date '+%Y-%m-%d %H:%M:%S')) ---" | tee -a "$log_file"
        # 设置环境变量让 sync.py 知道数据目录
        OPENCLAW_DATA_DIR="$data_dir" python3 /usr/local/bin/sync.py backup 2>&1 | tee -a "$log_file"
        echo "--- [BACKUP] 第 $count 次定时备份完成 ---" | tee -a "$log_file"
        sleep $SYNC_INTERVAL
    done
}

# ============================================================
# 主启动流程
# ============================================================
echo "=========================================="
echo "OpenClaw Gateway 启动中..."
echo "=========================================="

# 配置 DNS（Google DNS 8.8.8.8, 8.8.4.4）
setup_dns

# 存储路径：优先使用 /data（HF Spaces 持久存储），否则使用 /root
if mkdir -p /data/.openclaw 2>/dev/null; then
    OPENCLAW_HOME="/data"
    echo "--- [INIT] 使用持久存储: /data ---"
else
    OPENCLAW_HOME="/root"
    echo "--- [INIT] 使用默认存储: /root ---"
fi

mkdir -p ${OPENCLAW_HOME}/.openclaw/sessions
mkdir -p ${OPENCLAW_HOME}/.openclaw/workspace

# 设置 OPENCLAW_HOME 环境变量
export OPENCLAW_HOME

# 修改数据目录常量为动态路径
OPENCLAW_DATA_DIR="${OPENCLAW_HOME}/.openclaw"
SYNC_LOG_FILE="${OPENCLAW_HOME}/.openclaw/sync.log"

echo "--- [INIT] 检查 HuggingFace 数据恢复 ---"
python3 /usr/local/bin/sync.py restore

if [ ! -f "${CONFIG_FILE}" ]; then
    echo "--- [INIT] 无历史数据，需要初始备份 ---"
    NEED_INITIAL_UPLOAD=true
fi

echo "--- [INIT] 生成配置文件 ---"

HF_SPACE_DOMAIN="${HF_SPACE_DOMAIN:-}"
if [ -z "$HF_SPACE_DOMAIN" ]; then
    echo "ERROR: HF_SPACE_DOMAIN environment variable is required!"
    exit 1
fi

# 使用动态路径
CONFIG_FILE="${OPENCLAW_HOME}/.openclaw/openclaw.json"

# ==================== 模型配置 ====================
# 优先级：ModelScope > HuggingFace 免费模型 > 自定义 API

# ModelScope 配置
MODELSCOPE_API_KEY="${MODELSCOPE_API_KEY:-}"
MODELSCOPE_MODEL="${MODELSCOPE_MODEL:-moonshotai/Kimi-K2.5}"
MODELSCOPE_API_BASE="https://api-inference.modelscope.cn/v1"

# HuggingFace 免费模型配置
HF_TOKEN="${HF_TOKEN:-}"
HF_API_BASE="https://api-inference.huggingface.co"

# 备用模型配置（先设置默认值）
FALLBACK_MODES="${FALLBACK_MODEL:-}"
FALLBACK_OPENAI_API_BASE="${FALLBACK_OPENAI_API_BASE:-}"
FALLBACK_OPENAI_API_KEY="${FALLBACK_OPENAI_API_KEY:-}"
OPENAI_API_BASE="${OPENAI_API_BASE:-}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"

# 判断使用哪个模型
if [ -n "$MODELSCOPE_API_KEY" ]; then
    # 方案1: 使用 ModelScope
    echo "--- [INIT] 使用 ModelScope 作为主模型 ---"
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
elif [ -n "$HF_TOKEN" ] && [ -z "$OPENAI_API_KEY" ] && [ -z "$MODELSCOPE_API_KEY" ]; then
    # 方案2: 使用 HuggingFace 免费模型（只有 HF_TOKEN，没有自定义 API）
    echo "--- [INIT] 使用 HuggingFace 免费模型 ---"
    PRIMARY_API_BASE="$HF_API_BASE"
    PRIMARY_API_KEY="$HF_TOKEN"
    # 使用默认免费模型（DeepSeek-R1 是热门免费模型）
    PRIMARY_MODEL="${OPENCLAW_DEFAULT_MODEL:-huggingface/deepseek-ai/DeepSeek-R1}"
    PRIMARY_PROVIDER="huggingface"
    echo "--- [INIT] 主模型: $PRIMARY_MODEL (Provider: $PRIMARY_PROVIDER, API: $PRIMARY_API_BASE)"
    
    # HuggingFace 不需要备用模型
    FALLBACK_API_BASE=""
    FALLBACK_API_KEY=""
elif [ -n "$OPENAI_API_KEY" ]; then
    # 方案3: 使用自定义 OpenAI 兼容 API
    echo "--- [INIT] 使用自定义 API 作为主模型 ---"
    # 只去掉 /chat/completions 后缀，保留完整的 /v1 路径
    PRIMARY_API_BASE=$(echo "${OPENAI_API_BASE:-}" | sed 's|/chat/completions$||')
    PRIMARY_API_KEY="$OPENAI_API_KEY"
    PRIMARY_MODEL="${MODEL:-nvidia/nemotron-3-super-120b-a12b}"
    PRIMARY_PROVIDER=$(echo "$PRIMARY_API_BASE" | sed 's|^https://||' | sed 's|/.*$||')
    echo "--- [INIT] 主模型: $PRIMARY_MODEL (Provider: $PRIMARY_PROVIDER, API: $PRIMARY_API_BASE)"
    
    # 只去掉 /chat/completions 后缀，保留完整的 /v1 路径
    FALLBACK_API_BASE=$(echo "${FALLBACK_OPENAI_API_BASE:-$OPENAI_API_BASE}" | sed 's|/chat/completions$||')
    FALLBACK_API_KEY="${FALLBACK_OPENAI_API_KEY:-$OPENAI_API_KEY}"
else
    # 没有配置任何 API，报错
    echo "ERROR: 请配置至少一种模型 API"
    echo "  - ModelScope: 设置 MODELSCOPE_API_KEY"
    echo "  - HuggingFace: 设置 HF_TOKEN"
    echo "  - 自定义 API: 设置 OPENAI_API_KEY 和 OPENAI_API_BASE"
    exit 1
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
            # 确保视觉模型名称使用 ModelScope 格式
            VISION_MODEL="$VISION_MODEL"
        else
            # 使用主模型的 API 配置
            VISION_API_BASE="$PRIMARY_API_BASE"
            VISION_API_KEY="$PRIMARY_API_KEY"
        fi
    else
        # 单独配置了视觉模型 API
        VISION_API_BASE=$(echo "$VISION_API_BASE" | sed 's|/chat/completions$||')
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

# 如果是 ModelScope API，使用 modelscope provider
if [ "$VISION_PROVIDER" = "api-inference.modelscope.cn" ]; then
    VISION_PROVIDER="modelscope"
fi

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

# OpenRouter 支持（兼容 HuggingClaw）
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"

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
elif [ -n "$VISION_MODEL" ] && [ "$VISION_USE_SEPARATE" = false ]; then
    # 如果视觉模型使用相同 API，添加到主模型列表（已在 PROVIDERS_JSON 中处理）
    AGENTS_CONFIG="$AGENTS_CONFIG, \"imageModel\": {"
    AGENTS_CONFIG="$AGENTS_CONFIG \"primary\": \"$PRIMARY_PROVIDER/$VISION_MODEL\""
    AGENTS_CONFIG="$AGENTS_CONFIG }"
fi

# 关闭 defaults 对象
AGENTS_CONFIG="$AGENTS_CONFIG }"

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

cat > "${CONFIG_FILE}" <<EOF
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
  },
  "commands": {
    "bash": true,
    "config": true
  },
  "tools": {
    "elevated": {
      "enabled": true,
      "allowFrom": {
        "webchat": ["*"],
        "feishu": ["*"],
        "dingtalk": ["*"]
      }
    },
    "exec": {
      "security": "full",
      "ask": "off"
    }
  }
}
EOF

echo "--- [INIT] 配置完成 (已启用 bash、config 命令和 elevated 工具，已设置 exec 安全策略) ---"
cat "${CONFIG_FILE}" | head -30

# 注意：初始全量备份将在 backup_daemon 启动 20 分钟后自动执行

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
cat > "${CONFIG_FILE}" <<EOF
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
  },
  "commands": {
    "bash": true,
    "config": true
  },
  "tools": {
    "elevated": {
      "enabled": true,
      "allowFrom": {
        "webchat": ["*"],
        "feishu": ["*"],
        "dingtalk": ["*"]
      }
    },
    "exec": {
      "security": "full",
      "ask": "off"
    }
  }
}
EOF
echo "--- [INIT] 重新写入配置完成 ---"

# ============================================================
# 传递完整环境变量给 OpenClaw
# ============================================================
echo "--- [INIT] 传递完整环境变量给 OpenClaw ---"

# 导出所有环境变量，确保 OpenClaw 可以访问所有配置
# 包括：HF_TOKEN, OPENAI_API_KEY, ANTHROPIC_API_KEY, GOOGLE_API_KEY 等
export HF_TOKEN
export OPENAI_API_KEY
export OPENAI_API_BASE
export ANTHROPIC_API_KEY
export GOOGLE_API_KEY
export MODELSCOPE_API_KEY
export OPENROUTER_API_KEY
export OLLAMA_HOST
export OLLAMA_NUM_PARALLEL
export OLLAMA_KEEP_ALIVE
export OPENCLAW_MEMORY_BACKEND
export OPENCLAW_REDIS_URL
export OPENCLAW_SQLITE_PATH
export OPENCLAW_HTTP_PROXY
export OPENCLAW_HTTPS_PROXY
export OPENCLAW_NO_PROXY

# 打印环境变量状态（不打印敏感值）
echo "--- [INIT] 环境变量状态: ---"
echo "  - HF_TOKEN: ${HF_TOKEN:+已设置}"
echo "  - OPENAI_API_KEY: ${OPENAI_API_KEY:+已设置}"
echo "  - MODELSCOPE_API_KEY: ${MODELSCOPE_API_KEY:+已设置}"
echo "  - OPENROUTER_API_KEY: ${OPENROUTER_API_KEY:+已设置}"
echo "  - ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:+已设置}"
echo "  - GOOGLE_API_KEY: ${GOOGLE_API_KEY:+已设置}"

echo "--- [INIT] 启动 OpenClaw Gateway ---"

exec node openclaw.mjs gateway --allow-unconfigured
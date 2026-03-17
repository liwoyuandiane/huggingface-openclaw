# OpenClaw Gateway Dockerfile for HuggingFace Deployment
# 基于官方镜像 ghcr.io/openclaw/openclaw:latest
# 支持飞书、钉钉、HuggingFace 数据同步

FROM ghcr.io/openclaw/openclaw:latest

# 切换到 root 用户
USER root

# ============================================================
# 1. 安装所有依赖（合并层以减小镜像体积）
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip curl \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --no-cache-dir huggingface_hub --break-system-packages

# ============================================================
# 注意：飞书、钉钉、企业微信已是 OpenClaw 内置功能
# 只需通过环境变量配置即可，无需额外安装
# 如需微信插件，可使用：openclaw plugins install https://github.com/dingxiang-me/OpenClaw-Wechat.git
# ============================================================

# ============================================================
# 2. 复制核心文件
# ============================================================
COPY sync.py /usr/local/bin/sync.py
COPY start-openclaw.sh /usr/local/bin/start-openclaw
RUN chmod +x /usr/local/bin/sync.py /usr/local/bin/start-openclaw

# ============================================================
# 3. 端口和环境变量
# ============================================================
ENV PORT=7860
ENV OPENCLAW_GATEWAY_MODE=local

EXPOSE 7860

# ============================================================
# 4. 健康检查（HuggingFace Spaces 兼容）
# ============================================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:7860/health || exit 1

CMD ["/usr/local/bin/start-openclaw"]
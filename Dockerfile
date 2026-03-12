# OpenClaw Gateway Dockerfile for HuggingFace Deployment
# 基于官方镜像 ghcr.io/openclaw/openclaw:latest
# 支持飞书、HuggingFace 数据同步

FROM ghcr.io/openclaw/openclaw:latest

# 切换到 root 用户
USER root

# ============================================================
# 1. 安装系统依赖
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip curl \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 2. 安装 HuggingFace CLI
# ============================================================
RUN pip3 install --no-cache-dir huggingface_hub --break-system-packages

# ============================================================
# 3. 核心同步引擎 (sync.py)
# 用于 HuggingFace 数据备份/恢复
# ============================================================
COPY sync.py /usr/local/bin/sync.py
RUN chmod +x /usr/local/bin/sync.py

# ============================================================
# 4. 容器启动脚本
# ============================================================
COPY start-openclaw.sh /usr/local/bin/start-openclaw
RUN chmod +x /usr/local/bin/start-openclaw

# ============================================================
# 5. 端口和环境变量
# ============================================================
ENV PORT=7860
ENV OPENCLAW_GATEWAY_MODE=local

EXPOSE 7860

CMD ["/usr/local/bin/start-openclaw"]

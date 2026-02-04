# ProxifAI Base Image - Minimal Alpine with SSH and essential tools
# Size optimized for fast container startup

FROM alpine:3.19

LABEL org.opencontainers.image.title="ProxifAI Base"
LABEL org.opencontainers.image.description="Minimal base image for ProxifAI agents with SSH support"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL ai.proxifai.image.type="base"
LABEL ai.proxifai.image.version="1.0.0"

# Install minimal dependencies in single layer
RUN apk add --no-cache \
    openssh-server \
    bash \
    curl \
    git \
    && mkdir -p /var/run/sshd /root/.ssh \
    && ssh-keygen -A \
    && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config \
    && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config \
    && echo 'PermitEmptyPasswords no' >> /etc/ssh/sshd_config \
    && echo 'root:root' | chpasswd \
    && rm -rf /var/cache/apk/* /tmp/*

# Create workspace directory
WORKDIR /workspace

# Expose SSH port
EXPOSE 22

# Default command starts SSH daemon
CMD ["/usr/sbin/sshd", "-D", "-e"]

FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    sudo \
    supervisor \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install VS Code Server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Create directories
RUN mkdir -p /var/lib/tailscale /var/run/tailscale /workspace

# Create supervisor configuration
RUN echo '[supervisord]\n\
nodaemon=true\n\
user=root\n\
\n\
[program:code-server]\n\
command=code-server --bind-addr 0.0.0.0:8080 --auth none /workspace\n\
directory=/workspace\n\
autorestart=true\n\
priority=100\n\
stdout_logfile=/dev/stdout\n\
stdout_logfile_maxbytes=0\n\
stderr_logfile=/dev/stderr\n\
stderr_logfile_maxbytes=0\n\
\n\
[program:tailscaled]\n\
command=tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state\n\
autorestart=true\n\
priority=200\n\
stdout_logfile=/var/log/tailscaled.log\n\
stderr_logfile=/var/log/tailscaled.log\n\
\n\
[program:tailscale-connect]\n\
command=/tailscale-connect.sh\n\
autorestart=false\n\
priority=300\n\
startsecs=0\n\
stdout_logfile=/var/log/tailscale-connect.log\n\
stderr_logfile=/var/log/tailscale-connect.log' > /etc/supervisor/conf.d/services.conf

# Create Tailscale connection script
RUN echo '#!/bin/bash\n\
echo "Waiting for tailscaled to start..."\n\
sleep 15\n\
\n\
while true; do\n\
    if tailscale status > /dev/null 2>&1; then\n\
        echo "Already connected to Tailscale"\n\
        break\n\
    fi\n\
    \n\
    if [ -n "$TAILSCALE_AUTHKEY" ]; then\n\
        echo "Connecting to Tailscale with authkey..."\n\
        if tailscale up --authkey="$TAILSCALE_AUTHKEY" --advertise-exit-node --accept-routes; then\n\
            echo "Successfully connected to Tailscale!"\n\
            echo "VS Code Server: Available at your Render URL"\n\
            echo "Tailscale IP: $(tailscale ip -4 2>/dev/null || echo \"Not available yet\")" \n\
            tailscale status\n\
            break\n\
        else\n\
            echo "Failed to connect, retrying in 30 seconds..."\n\
            sleep 30\n\
        fi\n\
    else\n\
        echo "No TAILSCALE_AUTHKEY provided, skipping Tailscale setup"\n\
        echo "Only VS Code Server will be available"\n\
        break\n\
    fi\n\
done\n\
\n\
# Monitor connection and reconnect if needed\n\
while true; do\n\
    sleep 60\n\
    if [ -n "$TAILSCALE_AUTHKEY" ] && ! tailscale status > /dev/null 2>&1; then\n\
        echo "Tailscale disconnected, attempting to reconnect..."\n\
        tailscale up --authkey="$TAILSCALE_AUTHKEY" --advertise-exit-node --accept-routes\n\
    fi\n\
done' > /tailscale-connect.sh && chmod +x /tailscale-connect.sh

# Set proper permissions
RUN chown -R root:root /var/lib/tailscale /var/run/tailscale

# Expose VS Code Server port
EXPOSE 8080

# Start supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]

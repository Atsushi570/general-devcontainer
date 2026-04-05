FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# =============================================================================
# 1. System packages + git PPA (git >= 2.48 for worktree.useRelativePaths)
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    && add-apt-repository -y ppa:git-core/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
    git \
    zsh \
    tmux \
    ripgrep \
    jq \
    build-essential \
    curl \
    wget \
    unzip \
    zip \
    ca-certificates \
    gnupg \
    sudo \
    vim \
    locales \
    xclip \
    openssh-client \
    && locale-gen en_US.UTF-8 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# =============================================================================
# 2. GitHub CLI (official apt repository)
# =============================================================================
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# =============================================================================
# 3. Docker CLI (official apt, docker-ce-cli only)
# =============================================================================
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends \
    docker-ce-cli \
    docker-buildx-plugin \
    docker-compose-plugin \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# =============================================================================
# 4. User creation (devuser, UID 1000, zsh, passwordless sudo)
# =============================================================================
RUN userdel -r ubuntu 2>/dev/null; groupdel ubuntu 2>/dev/null; \
    groupadd -g 1000 devuser \
    && useradd -m -u 1000 -g 1000 -s /bin/zsh devuser \
    && echo "devuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/devuser \
    && chmod 0440 /etc/sudoers.d/devuser

# =============================================================================
# 5. Binary tools (ghq, go-task, AWS CLI, Terraform)
# =============================================================================
# ghq
RUN ARCH=$(dpkg --print-architecture) \
    && GHQ_VERSION=$(curl -fsSL https://api.github.com/repos/x-motemen/ghq/releases/latest | jq -r .tag_name | sed 's/^v//') \
    && if [ "$ARCH" = "amd64" ]; then GHQ_ARCH="amd64"; else GHQ_ARCH="arm64"; fi \
    && curl -fsSL "https://github.com/x-motemen/ghq/releases/download/v${GHQ_VERSION}/ghq_linux_${GHQ_ARCH}.zip" -o /tmp/ghq.zip \
    && unzip /tmp/ghq.zip -d /tmp/ghq \
    && mv /tmp/ghq/ghq_linux_${GHQ_ARCH}/ghq /usr/local/bin/ghq \
    && chmod +x /usr/local/bin/ghq \
    && rm -rf /tmp/ghq /tmp/ghq.zip

# lazygit
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "amd64" ]; then LG_ARCH="x86_64"; else LG_ARCH="arm64"; fi \
    && LG_VERSION=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r .tag_name | sed 's/^v//') \
    && curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${LG_VERSION}/lazygit_${LG_VERSION}_linux_${LG_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin lazygit

# gwq (git worktree manager)
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "amd64" ]; then GWQ_ARCH="x86_64"; else GWQ_ARCH="arm64"; fi \
    && GWQ_VERSION=$(curl -fsSL https://api.github.com/repos/d-kuro/gwq/releases/latest | jq -r .tag_name | sed 's/^v//') \
    && curl -fsSL "https://github.com/d-kuro/gwq/releases/download/v${GWQ_VERSION}/gwq_Linux_${GWQ_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin gwq

# uv (Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && mv /root/.local/bin/uv /usr/local/bin/ && mv /root/.local/bin/uvx /usr/local/bin/

# go-task
RUN sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# AWS CLI v2
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "amd64" ]; then AWS_ARCH="x86_64"; else AWS_ARCH="aarch64"; fi \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscli.zip \
    && unzip /tmp/awscli.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscli.zip

# Terraform
RUN ARCH=$(dpkg --print-architecture) \
    && TF_VERSION=$(curl -fsSL https://api.github.com/repos/hashicorp/terraform/releases/latest | jq -r .tag_name | sed 's/^v//') \
    && curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${ARCH}.zip" -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/terraform \
    && rm /tmp/terraform.zip

# Google Cloud CLI (includes bq for BigQuery)
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | tee /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update && apt-get install -y --no-install-recommends google-cloud-cli \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# fzf (latest, for --zsh support / Ctrl+R history search)
RUN FZF_VERSION=$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest | jq -r .tag_name | sed 's/^v//') \
    && ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin

# =============================================================================
# 6. Dotfiles to /etc/skel/ (home is overwritten by volume)
# =============================================================================
COPY config/ssh_config /etc/ssh/ssh_config.d/99-devcontainer.conf
COPY config/.zshrc /etc/skel/.zshrc
COPY config/.gitconfig /etc/skel/.gitconfig
COPY config/.tmux.conf /etc/skel/.tmux.conf
RUN mkdir -p /etc/skel/.config/mise
COPY config/mise-config.toml /etc/skel/.config/mise/config.toml

# =============================================================================
# 7. Switch to devuser
# =============================================================================
USER devuser
WORKDIR /home/devuser
ENV HOME=/home/devuser

# =============================================================================
# 8. Oh My Zsh + zsh-completions
# =============================================================================
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-completions

# =============================================================================
# 9. mise + runtimes (node, python, go, java)
# =============================================================================
RUN curl https://mise.run | sh \
    && echo 'eval "$(~/.local/bin/mise activate zsh)"' >> /tmp/mise_init.sh
ENV PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
RUN mkdir -p $HOME/.config/mise \
    && cp /etc/skel/.config/mise/config.toml $HOME/.config/mise/config.toml \
    && mise install

# =============================================================================
# 10. Claude Code (native installer)
# =============================================================================
RUN curl -fsSL https://claude.ai/install.sh | bash

# =============================================================================
# 11. tmux plugin manager (tpm)
# =============================================================================
RUN git clone https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm

# =============================================================================
# 12. Entrypoint
# =============================================================================
COPY --chown=devuser:devuser scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
USER root
RUN chmod +x /usr/local/bin/entrypoint.sh
USER devuser

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]

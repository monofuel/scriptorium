ARG MONOLAB_NIM_TAG=2.2.4
FROM gitea.solution-nine.monofuel.dev/monolab/monolab-nim:${MONOLAB_NIM_TAG}
LABEL monolab.nim.tag="${MONOLAB_NIM_TAG}"

ARG MONOLAB_NIM_TAG
ENV MONOLAB_NIM_TAG=${MONOLAB_NIM_TAG}

WORKDIR /app

RUN mkdir -p /etc/portage/package.use && \
    echo 'net-libs/nodejs npm' >> /etc/portage/package.use/nodejs
RUN emerge --quiet net-libs/nodejs \
    && node --version \
    && npm --version
ARG CODEX_VERSION=0.114.0
ARG CLAUDE_CODE_VERSION=2.1.76
RUN npm install --global @openai/codex@${CODEX_VERSION} @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    && codex --version \
    && claude --version

COPY nimby.lock scriptorium.nimble Makefile ./
COPY src ./src
COPY scripts ./scripts

RUN echo 'path = "src"' > nim.cfg
RUN nimby sync -g nimby.lock
ARG BUILD_COMMIT=unknown
RUN make build BUILD_COMMIT=${BUILD_COMMIT}

RUN useradd -m -s /bin/bash scriptorium && \
    cp -r /root/.nimble /home/scriptorium/.nimble && \
    cp -r /root/.nimby /home/scriptorium/.nimby && \
    chown -R scriptorium:scriptorium /home/scriptorium/.nimble /home/scriptorium/.nimby

ENV PATH="/home/scriptorium/.nimble/bin:${PATH}"
USER scriptorium

RUN git config --global --add safe.directory /workspace && \
    git config --global user.email "scriptorium@localhost" && \
    git config --global user.name "Scriptorium"

ENTRYPOINT ["/app/scripts/entrypoint.sh"]
CMD ["--help"]

FROM gitea.solution-nine.monofuel.dev/monolab/monolab/monolab-nim:latest

WORKDIR /app

RUN mkdir -p /etc/portage/package.use && \
    echo 'net-libs/nodejs npm' >> /etc/portage/package.use/nodejs
RUN emerge --quiet net-libs/nodejs \
    && node --version \
    && npm --version
RUN npm install --global @openai/codex @anthropic-ai/claude-code \
    && codex --version \
    && claude --version

COPY nim.cfg nimby.lock scriptorium.nimble Makefile ./
COPY src ./src



RUN nimby sync -g nimby.lock
RUN make build

RUN git config --global --add safe.directory /workspace

ENTRYPOINT ["/app/scriptorium"]
CMD ["--help"]

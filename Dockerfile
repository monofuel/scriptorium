FROM gitea.solution-nine.monofuel.dev/monolab/monolab/monolab-nim:latest

WORKDIR /app

COPY nim.cfg nimby.lock scriptorium.nimble Makefile ./
COPY src ./src

RUN emerge --quiet net-libs/nodejs \
    && node --version \
    && npm --version
RUN npm install --global @openai/codex @anthropic-ai/claude-code \
    && codex --version \
    && claude --version

RUN nimby sync -g nimby.lock
RUN make build

ENTRYPOINT ["/app/scriptorium"]
CMD ["--help"]

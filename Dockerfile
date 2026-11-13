FROM node:24-bookworm-slim AS node
FROM gitea.solution-nine.monofuel.dev/monolab/monolab/monolab-nim:latest

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm

ARG NIM_VERSION=2.2.14
ARG NIMBY_VERSION=0.2.4
ARG BUILD_COMMIT=unknown
ENV BUILD_COMMIT=${BUILD_COMMIT}
RUN curl -fsSL "https://nim-lang.org/download/nim-${NIM_VERSION}-linux_x64.tar.xz" | tar -xJ -C /opt
RUN curl -fsSL "https://github.com/treeform/nimby/releases/download/${NIMBY_VERSION}/nimby-Linux-X64" -o /usr/local/bin/nimby \
    && chmod +x /usr/local/bin/nimby
ENV PATH="/opt/nim-2.2.14/bin:/usr/local/bin:/app/.build/agent-tools/node_modules/.bin:${PATH}"

WORKDIR /app
COPY nimby.lock scriptorium.nimble Makefile config.nims package.json package-lock.json ./
COPY src ./src
COPY scripts ./scripts
RUN make setup agent-setup build && cp scriptorium /usr/local/bin/
RUN useradd -m -s /bin/bash scriptorium \
    && chown -R scriptorium:scriptorium /app/.build
USER scriptorium
RUN git config --global --add safe.directory /workspace \
    && git config --global user.email "scriptorium@localhost" \
    && git config --global user.name "Scriptorium"
ENTRYPOINT ["/app/scripts/entrypoint.sh"]
CMD ["--help"]

FROM gitea.solution-nine.monofuel.dev/monolab/monolab/monolab-nim:latest

WORKDIR /app

COPY nim.cfg nimby.lock scriptorium.nimble Makefile ./
COPY src ./src

RUN nimby sync -g nimby.lock
RUN make build

ENTRYPOINT ["/app/scriptorium"]
CMD ["--help"]

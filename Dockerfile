# ── Builder stage ─────────────────────────────────────────────────────────────
FROM hexpm/elixir:1.19.2-erlang-27.3.4.2-debian-bookworm-20260316-slim AS builder

# Install build tools
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends build-essential git && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && mix local.rebar --force

# MIX_ENV propagates to all subsequent RUN steps
ENV MIX_ENV=prod

# ── Layer 1: dependencies (cached until mix.lock or config/ changes) ──────────
COPY mix.exs mix.lock ./
COPY config/ config/

RUN mix deps.get --only prod && mix deps.compile

# ── Layer 2: application code (cached until lib/ or priv/ changes) ───────────
# Must compile before assets — phoenix-colocated/taniwha is generated at compile
# time by scanning lib/ for co-located JS hooks.
COPY lib/ lib/
COPY priv/ priv/

RUN mix compile

# ── Layer 3: assets (cached until assets/ changes) ────────────────────────────
COPY assets/ assets/

RUN mix tailwind.install --if-missing && \
    mix esbuild.install --if-missing && \
    mix assets.deploy

# ── Layer 4: release ──────────────────────────────────────────────────────────
RUN mix release

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

# Install runtime dependencies
# - libssl3: OpenSSL shared library (not headers)
# - libncurses6: Erlang terminal detection
# - locale: prevents Erlang string module falling back to ASCII
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libssl3 libncurses6 locales && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

# Create non-root user
RUN groupadd --gid 1001 taniwha && \
    useradd --uid 1001 --gid taniwha --no-create-home taniwha

# Copy release from builder
COPY --from=builder --chown=taniwha:taniwha /app/_build/prod/rel/taniwha ./

USER taniwha

# PHX_SERVER=true tells runtime.exs to enable the HTTP server
# SECRET_KEY_BASE and PHX_HOST must be provided at runtime via --env-file
ENV PHX_SERVER=true

EXPOSE 4000

# Exec form ensures SIGTERM reaches the BEAM directly
CMD ["./bin/taniwha", "start"]

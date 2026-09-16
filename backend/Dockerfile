FROM node:22-bookworm-slim AS validator
WORKDIR /validator
COPY priv/chess_validator/package.json priv/chess_validator/package-lock.json ./
RUN npm ci --omit=dev

FROM elixir:1.18.3-otp-27-slim AS build

ENV MIX_ENV=prod
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/
RUN mix deps.get --only prod && mix deps.compile
COPY priv priv
COPY --from=validator /validator/node_modules priv/chess_validator/node_modules
COPY lib lib
COPY config/runtime.exs config/runtime.exs
RUN mix compile && mix release

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libstdc++6 libssl3 libncurses6 stockfish gosu \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 chessduel \
    && useradd --uid 10001 --gid chessduel --no-create-home chessduel
WORKDIR /app
ENV LANG=C.UTF-8 STOCKFISH_PATH=/usr/games/stockfish
COPY --from=validator /usr/local/bin/node /usr/local/bin/node
COPY --from=build --chown=chessduel:chessduel /app/_build/prod/rel/chess_duel_backend ./
COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/chessduel-entrypoint
EXPOSE 4000
ENTRYPOINT ["chessduel-entrypoint"]
CMD ["bin/chess_duel_backend", "start"]

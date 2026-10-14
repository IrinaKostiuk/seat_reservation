FROM hexpm/elixir:1.15.8-erlang-25.3.2.8-debian-bookworm-20260610-slim
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get && mix deps.compile
COPY . .
RUN mix compile --warnings-as-errors
EXPOSE 4000
CMD ["mix", "phx.server"]

# Taniwha

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `SECRET_KEY_BASE` | **yes** (prod) | — | Phoenix session signing key (64+ chars) |
| `PHX_HOST` | **yes** (prod) | — | Public hostname (e.g. `driky.lol`) |
| `PORT` | no | `4000` | HTTP port |
| `RTORRENT_SOCKET` | no | `/var/run/rtorrent.sock` | Path to rtorrent SCGI socket |
| `TANIWHA_API_KEY` | **yes** (prod) | — | Bearer token for the REST API and WebSocket |
| `OTEL_SERVICE_NAME` | no | `taniwha` | Service name shown in traces |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | no | `http://localhost:4318` | OTLP collector endpoint (leave empty to disable) |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | no | `http_protobuf` | `http_protobuf` or `grpc` |
| `OTEL_EXPORTER_OTLP_HEADERS` | no | — | Auth headers (e.g. `signoz-ingestion-key=<key>`) |
| `OTEL_TRACES_SAMPLER` | no | `parentbased_always_on` | Set `always_off` to disable tracing |

See [`docs/server-setup.md`](docs/server-setup.md) for the full deployment guide.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

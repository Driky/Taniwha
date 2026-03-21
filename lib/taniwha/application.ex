defmodule Taniwha.Application do
  @moduledoc "OTP Application entry point. Custom children wired in later tasks."
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Taniwha.PubSub},
      Taniwha.RPC.Client,
      Taniwha.State.Store,
      Taniwha.State.Poller,
      TaniwhaWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Taniwha.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    TaniwhaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

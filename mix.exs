defmodule Taniwha.MixProject do
  use Mix.Project

  def project do
    [
      app: :taniwha,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: [
        plt_add_apps: [:mix],
        plt_local_path: "priv/plts"
      ],
      # 80% threshold accounts for Phoenix-generated boilerplate modules
      # (PageController, PageHTML, Telemetry), the Guardian auth plug, stub
      # LiveViews pending Task 5.3, and socket I/O helpers that require a live
      # rtorrent connection (covered by integration tests in Task 6.5).
      test_coverage: [threshold: 80, summary: [threshold: 80]]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Taniwha.Application, []},
      extra_applications: [:logger, :runtime_tools, :opentelemetry]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:bcrypt_elixir, "~> 3.1"},
      {:guardian, "~> 2.3"},
      {:wax_, "~> 0.6"},
      {:sweet_xml, "~> 0.7"},
      {:opentelemetry, "~> 1.7.0"},
      {:opentelemetry_api, "~> 1.5.0"},
      {:opentelemetry_exporter, "~> 1.10.0"},
      {:opentelemetry_semantic_conventions, "~> 1.27.0"},
      {:opentelemetry_phoenix, "~> 2.0.1"},
      {:opentelemetry_bandit, "~> 0.3.0"},
      {:opentelemetry_logger_metadata, "~> 0.2.0"},
      {:mox, "~> 1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind taniwha", "esbuild taniwha"],
      "assets.deploy": [
        "tailwind taniwha --minify",
        "esbuild taniwha --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end

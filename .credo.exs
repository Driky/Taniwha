%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/priv/"]
      },
      strict: true,
      color: true,
      checks: %{enabled: []}
    }
  ]
}

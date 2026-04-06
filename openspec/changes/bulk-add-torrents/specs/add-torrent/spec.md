## ADDED Requirements

### Requirement: Commands layer exposes batch add functions
`Taniwha.Commands` SHALL provide `load_urls/2` and `load_raws/2` that accept a list of items and return a structured result distinguishing successes from failures.

#### Scenario: All URLs load successfully
- **WHEN** `Commands.load_urls(["magnet:?xt=..."], opts)` is called with a list of valid magnet links
- **THEN** each URL is submitted to rtorrent via `load.start` and `{:ok, count}` is returned where `count` equals the number of URLs

#### Scenario: Some URLs fail to load
- **WHEN** `Commands.load_urls(urls, opts)` is called and one or more URLs produce an RPC error
- **THEN** remaining URLs are still attempted and `{:error, [{url, reason}]}` is returned listing each failed URL and its reason

#### Scenario: All raw files load successfully
- **WHEN** `Commands.load_raws([binary1, binary2], opts)` is called with valid torrent binaries
- **THEN** each binary is submitted via `load.raw_start` and `{:ok, count}` is returned

#### Scenario: Some raw files fail to load
- **WHEN** `Commands.load_raws(binaries, opts)` is called and one or more binaries produce an RPC error
- **THEN** remaining binaries are still attempted and `{:error, [{binary_label, reason}]}` is returned

### Requirement: File upload configuration supports multiple files
`DashboardLive` SHALL configure the `:torrent_file` upload to accept up to 20 entries.

#### Scenario: Multiple files accepted
- **WHEN** the user uploads up to 20 `.torrent` files
- **THEN** all files are queued without error

#### Scenario: Excess files rejected
- **WHEN** the user attempts to upload more than 20 files in one batch
- **THEN** files beyond the 20th are rejected with a client-side error before submission

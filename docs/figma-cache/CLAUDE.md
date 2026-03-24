# Figma Design Cache

Cached responses from the Figma MCP (`mcp__plugin_figma_figma__*`).
Use these files instead of calling the MCP — the project is on a rate-limited plan.

**Figma file key:** `hp8ISSdpaxXF9wiSTYsaOx`

## How to use a cached response

Each `.json` file has two top-level fields:

```
{
  "_meta": { tool, input, timestamp, source_session },
  "response": <the raw MCP response>
}
```

Read the `response` field directly as you would the live MCP result.
Ignore `_meta` — it is bookkeeping only.

For large responses (`4:2`, `1:2`) the `response` is a JSON array of
`{type: "text", text: "..."}` objects. Concatenate the `text` fields in order.

## Image assets

All 17 SVG assets referenced in the responses have been downloaded locally to
`docs/figma-cache/assets/`. The JSON cache files already use local paths
(e.g. `assets/d9e2fd24-….svg`) instead of the original remote URLs —
no network calls needed.

## Cached nodes

| File | Node | Status | Description |
|---|---|---|---|
| `get_design_context_hp8ISSdpaxXF9wiSTYsaOx_1_2.json` | `1:2` | ✅ valid | **Component Library** — full XML tree of all Taniwha UI components (80 KB) |
| `get_design_context_hp8ISSdpaxXF9wiSTYsaOx_4_2.json` | `4:2` | ✅ valid | **Main dashboard frame** — JSX reference + image asset constants (100 KB) |
| `get_design_context_hp8ISSdpaxXF9wiSTYsaOx_1_467.json` | `1:467` | ✅ valid | **TorrentRow** — default and selected states (small, JSX label node) |
| `get_design_context_hp8ISSdpaxXF9wiSTYsaOx_1_204.json` | `1:204` | ❌ rate limit | No data — hit API limit before response |
| `get_design_context_hp8ISSdpaxXF9wiSTYsaOx_1_241.json` | `1:241` | ❌ rate limit | No data — hit API limit before response |
| `get_design_context_hp8ISSdpaxXF9wiSTYsaOx_1_471.json` | `1:471` | ❌ rate limit | No data — hit API limit before response |
| `get_metadata_hp8ISSdpaxXF9wiSTYsaOx_0_1.json` | `0:1` | ❌ rate limit | No data — hit API limit before response |
| `whoami_unknown_.json` | — | ✅ valid | MCP auth identity check |
| `generate_figma_design_hp8ISSdpaxXF9wiSTYsaOx_.json` | — | ✅ valid | `generate_figma_design` result for the file |
| `generate_figma_design_unknown_.json` | — | ✅ valid | `generate_figma_design` result (capture-based) |

## File naming convention

```
{tool_short}_{fileKey}_{nodeId_colons_as_underscores}.json
```

Example: node `1:2` → `get_design_context_hp8ISSdpaxXF9wiSTYsaOx_1_2.json`

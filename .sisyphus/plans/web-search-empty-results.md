# WebSearch Tool Returns Empty Results Consistently

## Status: Done

## Completed: 2026-03-03

## TL;DR

> **Quick Summary**: The `WebSearch` tool (built into Claude Code) consistently
> returns zero results for a wide variety of queries. This was observed during
> a 2026-03-03 session where over 15 different search queries — covering YouTube
> videos, AI coding agents, Agile software development, specific people, specific
> sites — all returned completely empty result sets. This makes any workflow that
> depends on web research (e.g. periodic content scanning, resource discovery,
> trend tracking) completely non-functional.
>
> **Deliverables**: Diagnosis and workaround so that pykoclaw agents can
> reliably perform web searches.

## Problem Description

### Observed behavior

During a conversation on 2026-03-03, the agent attempted to find recent YouTube
videos and podcasts about AI coding agents and Agile software development. Every
single `WebSearch` call returned an empty result set — no URLs, no snippets,
no titles. The tool did not return errors; it simply returned nothing.

### Queries attempted (all returned zero results)

1. `"AI software development" OR "AI coding teams" 2026 YouTube Lex Fridman podcast`
2. `best AI coding agent video 2026 software engineering team`
3. `AI agent engineering software development 2026 "must watch"`
4. `Lex Fridman AI software developer 2026`
5. `site:youtube.com "AI coding" "software team" 2026`
6. `Cognition Labs Devin AI 2026 video presentation`
7. `"Anthropic" OR "OpenAI" OR "Claude Code" 2026 developer video presentation`
8. `"agentic coding" OR "AI developer" OR "AI programmer" 2026 YouTube interview`
9. `The Primeagen AI coding agent video 2026`
10. `top Agile thought leaders 2025 2026 influencers software development`
11. `Agile coaches to follow 2025 "modern agile" podcast blog`
12. `site:youtube.com "Claude Code" OR "Cursor" OR "Devin" "software team" 2026`
13. `2026 YouTube video AI coding agent software engineering team workflow`
14. `AI coding assistant developer experience 2026 "full video" tutorial`
15. `Lex Fridman podcast 2026 AI software engineering developer`

None of these are obscure queries. Any general-purpose search engine should
return dozens of results for most of them.

### What works vs. what doesn't

- `WebFetch` (fetching a known URL) works fine.
- `WebSearch` (searching for content by query) returns empty results consistently.

### Impact on pykoclaw workflows

This blocks several features and use cases:

1. **Periodic content scanning** — the weekly Monday scan task (pykoclaw task
   `9a18e283`) searches for recent YouTube videos and podcasts. If WebSearch
   doesn't work, this task will silently produce no results every week.
2. **Resource discovery** — users asking the agent to research topics, find
   articles, or discover new content cannot be served.
3. **Nightly review enrichment** — any future nightly review steps that involve
   web lookups would fail silently.

## Possible Causes

1. **Geographic restriction**: The WebSearch tool documentation states "Web search
   is only available in the US." The pykoclaw instance runs on `gogo` in Finland
   (Europe/Helsinki timezone). This is the most likely cause — the tool may be
   geo-blocked.

2. **Rate limiting or quota**: Possible but unlikely, since results were empty
   from the very first query in the session.

3. **Tool misconfiguration**: The tool may require API keys or configuration
   that aren't set up in the pykoclaw/ACP environment.

4. **Transient outage**: Could be a temporary backend issue, but the consistency
   across 15+ queries over ~10 minutes argues against this.

## Potential Workarounds

1. **Use `WebFetch` with a search engine URL**: Construct a Google/DuckDuckGo
   search URL and fetch it with `WebFetch`, then parse the results. This is
   hacky but might bypass the geo-restriction.

2. **Use an MCP web search tool**: The WebSearch documentation says "If an
   MCP-provided web fetch tool is available, prefer using that tool." A
   dedicated MCP search tool (e.g. Brave Search, SearXNG, Tavily) could be
   added as a pykoclaw plugin or MCP server.

3. **Use `yt-dlp --flat-playlist` for YouTube specifically**: For the YouTube
   video scanning use case, `yt-dlp` can search YouTube directly:

   ```bash
   yt-dlp --flat-playlist "ytsearch10:AI coding agents 2026" --print title --print url
   ```

   This bypasses WebSearch entirely for YouTube content.

4. **Proxy through a US-based service**: Route search requests through a
   US-based proxy or VPN endpoint.

## Recommended Next Steps

1. Confirm the geo-restriction hypothesis by checking Claude Code documentation
   or testing from a US IP.
2. Implement workaround #3 (`yt-dlp ytsearch`) immediately for the YouTube
   scanning use case — it's simple and doesn't require new infrastructure.
3. Evaluate adding a SearXNG or Tavily MCP server for general web search
   capability as a medium-term fix.

## Effort: Quick (investigation) + Short (workaround)

## Depends On: —

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Oban Web is a Phoenix LiveView dashboard for the [Oban](https://github.com/oban-bg/oban) background job processing framework. It's an embeddable library (not a standalone app) that users mount in their Phoenix router.

## Common Commands

```bash
# Install dependencies
mix deps.get

# Setup test databases (requires PostgreSQL 12+ and MySQL 8+ running locally)
mix test.setup

# Reset test databases
mix test.reset

# Run all tests
mix test

# Run a single test file
mix test test/oban/web/resolver_test.exs

# Run a specific test by line number
mix test test/oban/web/pages/jobs/index_test.exs:42

# Run tests excluding Oban Pro (when Pro is not available)
mix test --exclude pro

# Full CI pipeline (format check, deps check, credo, tests)
mix test.ci

# Run development server with fake job generation (http://localhost:4000/oban)
iex -S mix dev

# Build assets (tailwind + esbuild)
mix assets.build

# Lint
mix credo --strict

# Format
mix format
```

## Architecture

### LiveView Page System

The dashboard uses a single LiveView entry point (`DashboardLive`) with a page-based routing pattern:

- `DashboardLive` mounts at the router path and delegates to page modules
- Pages (`JobsPage`, `QueuesPage`) implement the `Oban.Web.Page` behaviour with callbacks: `handle_mount/1`, `handle_refresh/1`, `handle_params/2`, `handle_info/2`
- Routes: `/` (home), `/:page` (index), `/:page/:id` (show)

### Module Organization

- `Oban.Web` — `__using__` macro providing `:live_view`, `:live_component`, and `:html` variants that wire up common imports
- `Oban.Web.Router` — `oban_dashboard/2` macro for mounting the dashboard in host app routers
- `Oban.Web.Resolver` — behaviour for customizing access control, user resolution, and refresh rates
- `Oban.Web.Authentication` — LiveView `on_mount` hook for access control
- `Oban.Web.Queries.JobQuery` / `QueueQuery` — Ecto query builders for filtering and pagination
- `Oban.Web.Cache` — ETS-based cache with 5-minute purge interval
- `Oban.Web.Plugins.Stats` — Oban plugin for telemetry/stats collection
- `Oban.Web.Assets` — serves CSS/JS with MD5-versioned routes and CSP nonce support

### Component Organization

Components live under `lib/oban/web/components/`:
- `Core` — shared UI primitives
- `Icons` — SVG icon components
- `Layouts` — root and live layouts
- `SidebarComponents` — filter/search sidebar
- `Sort` — sort UI

Feature-specific LiveComponents are under `lib/oban/web/live/`:
- `jobs/` — table, detail, sidebar, chart, timeline
- `queues/` — table, detail, instances, sidebar
- Shared: search, shortcuts, theme, refresh, connectivity

### Frontend Assets

- `assets/js/app.js` — entry point, registers LiveView hooks
- `assets/js/hooks/` — JS hooks for charts (Chart.js), keyboard shortcuts, theme toggle, search autocomplete, sidebar resizing, tooltips (Tippy.js), auto-refresh, relative time
- `assets/js/lib/settings.js` — LocalStorage persistence for user preferences
- `assets/css/app.css` — Tailwind CSS source

### Multi-Database Testing

Tests run against three databases simultaneously:
- PostgreSQL (primary): `Oban.Web.Repo`
- MySQL: `Oban.Web.MyXQLRepo`
- SQLite: `Oban.Web.SQLiteRepo`

The `Oban.Web.Case` test helper provides: `start_supervised_oban!/0`, `insert_job!/0`, `flush_reporter/0`, `build_gossip/1`, `with_backoff/1`, and Floki HTML assertion helpers.

### Routing Context

The router prefix is stored in the process dictionary via `Process.put(:routing, {socket, prefix})` to support mounting at arbitrary paths.

## Code Style

- Max line length: 120 characters
- Formatter uses `Phoenix.LiveView.HTMLFormatter` plugin
- `oban_dashboard/1` and `oban_dashboard/2` are formatted without parens
- Credo runs in strict mode
- Oban Pro tests are tagged with `@tag :pro` and auto-excluded when Pro is unavailable

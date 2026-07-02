# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**ecocor-api** is an XQuery/eXist-db REST API for the EcoCor project (Environmental Complexity in Literature). It manages corpora of literary texts, extracts ecological entities (animals, plants), and computes metrics. Part of the broader DraCor ecosystem.

## Build & Run Commands

```bash
ant                    # Build the .xar package (output: build/ecocor-*.xar)
ant clean              # Remove build/ directory
ant existdb.json       # Generate .existdb.json for VS Code eXist-db extension
ant print.version      # Show current version (derived from git tags)

docker compose up      # Start full stack: eXist-db + ecocor-api + extractor service
```

The API is available at `http://localhost:8090/exist/restxq/ecocor/info` when running via Docker (host port 8090 maps to eXist's internal port 8080).

There is no automated test suite — test manually via HTTP/curl against a running instance.

## Architecture

### Technology Stack

- **Language**: XQuery 3.1
- **Runtime**: eXist-db 6.4.0 (XML database with built-in REST/scheduler)
- **Build tool**: Apache Ant (produces `.xar` package for eXist deployment)
- **External service**: `ecocor-extractor` (NLP service for entity recognition, port 8040)

### Module Responsibilities

| Module | Namespace | Purpose |
|--------|-----------|---------|
| `modules/api.xqm` | `http://ecocor.org/ns/exist/api` | All RESTXQ endpoint handlers |
| `modules/tei.xqm` | `http://ecocor.org/ns/exist/tei` | TEI XML parsing and metadata extraction |
| `modules/entities.xqm` | `http://ecocor.org/ns/exist/entities` | Entity management; calls extractor service |
| `modules/metrics.xqm` | `http://ecocor.org/ns/exist/metrics` | Word/entity count calculations |
| `modules/load.xqm` | `http://ecocor.org/ns/exist/load` | Downloads corpus repos from GitHub as ZIP |
| `modules/github.xqm` | `http://ecocor.org/ns/exist/github` | GitHub API (commit SHA, archive download) |
| `modules/config.xqm` | `http://ecocor.org/ns/exist/config` | App constants and config file paths |
| `modules/util.xqm` | `http://ecocor.org/ns/exist/util` | Path helpers, document retrieval |
| `modules/trigger.xqm` | `http://ecocor.org/ns/exist/trigger` | eXist database trigger (auto-update on document change) |
| `jobs/load-corpus.xq` | — | Scheduled async job for corpus loading |

### Request Flow

```
HTTP → RESTXQ (api.xqm) → tei.xqm / entities.xqm / metrics.xqm → eXist-db XML collections
```

### Data Storage Layout in eXist-db

```
/db/apps/ecocor/           ← deployed application code
/db/ecocor/
  config.xml               ← runtime config (API base URL, extractor server)
  secrets.xml              ← webhook secret (rw-------)
  corpora/{name}/
    corpus.xml             ← corpus metadata
    {textname}/
      tei.xml              ← source TEI document
      metrics.xml          ← computed word counts  [DERIVED — never edit]
      entities.xml         ← extracted animals/plants [DERIVED — never edit]
      git.xml              ← source repo commit SHA
```

### Trigger-Based Auto-Update

`data.xconf` configures an XQuery trigger on `/db/ecocor/corpora/`. When `tei.xml` is created or updated:
1. `metrics:update()` recalculates word counts
2. `entities:update()` sends text to the extractor service and stores results

`metrics.xml` and `entities.xml` are always derived — edits are overwritten on next trigger.

### Corpus Loading Flow

1. `POST /ecocor/corpora/{name}` schedules `jobs/load-corpus.xq` via eXist scheduler; returns **HTTP 202**
2. Job fetches the GitHub repo ZIP; prefers `tokenized/` subdirectory, falls back to `tei/`
3. Branch selection via URL fragment: `https://github.com/org/repo#branch-name`
4. TEI files stored in `/db/ecocor/corpora/{name}/`
5. Triggers fire automatically for each new/updated document

## Configuration

Runtime config is created during `post-install.xq` from environment variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `ECOCOR_API_BASE` | `https://ecocor.org/api` | Public API base URL |
| `EXTRACTOR_SERVER` | `http://localhost:8040` | NLP entity extractor URL |
| `GITHUB_WEBHOOK_SECRET` | — | Webhook HMAC secret |
| `EXIST_PASSWORD` | random | eXist-db admin password |
| `EXIST_PASSWORD_FILE` | — | Docker secret file path |
| `EXIST_ENV` | `development` | Set to `production` to require a non-empty password |

Key constants from `modules/config.xqm`:
- `$config:corpora-root` = `/db/ecocor/corpora`
- `$config:corpus-repo-prefix` = `'tei'` (subdirectory name inside corpus repos)

`adjust-conf-files.xsl` is applied by `entrypoint.sh` at container startup to patch eXist configuration files with runtime values.

## API Authentication

Write endpoints (POST/PUT/DELETE) check that an `Authorization` header is present. The header value is compared directly against the stored admin secret — no JWT, no OAuth, no "Bearer" prefix parsing. Returns 401 if header is absent.

## API Endpoints

Read-only (no auth):
- `GET /ecocor/info` — version, eXist version, base URL
- `GET /ecocor/corpora` — all corpora with metrics
- `GET /ecocor/corpora/{corpus}` — single corpus metadata
- `GET /ecocor/corpora/{corpus}/texts` — text list
- `GET /ecocor/corpora/{corpus}/texts/{text}/tei` — TEI XML
- `GET /ecocor/corpora/{corpus}/texts/{text}/plaintext` — extracted plain text
- `GET /ecocor/corpora/{corpus}/entities?type=animal|plant` — corpus-level entities
- `GET /ecocor/corpora/{corpus}/texts/{text}/entities?type=animal|plant` — text-level entities
- `GET /ecocor/corpora/{corpus}/texts/{text}/entities/csv` — CSV export

Admin (require `Authorization` header):
- `POST /ecocor/corpora` — create corpus (XML or JSON body)
- `PUT /ecocor/corpora/{corpus}` — update corpus metadata
- `POST /ecocor/corpora/{corpus}` — schedule async reload from GitHub (202)
- `DELETE /ecocor/corpora/{corpus}` — remove corpus
- `PUT /ecocor/corpora/{corpus}/texts/{text}` — add/replace TEI document
- `DELETE /ecocor/corpora/{corpus}/texts/{text}` — remove text

## eXist-db Specifics

- RESTXQ routing is enabled in `collection.xconf`
- Lucene full-text indexing is configured in `data.xconf`
- The `.existdb.json` file (generated by `ant existdb.json`) enables live sync from VS Code using the eXist-db extension
- Logging uses `util:log-system-out()` throughout — check Docker logs with `docker compose logs api`
- The eXpath dependencies (`functx`, `expath-crypto`, `openapi`) are auto-deployed as `.xar` files listed in `repo.xml`

## Extractor Service Contract

`entities:extract()` POSTs JSON to `{EXTRACTOR_SERVER}/extractor`:
- Input: `{ language, text: [{id, text}], entity_list_url }`
- Output: `{ entity_list: [{ name, wikidata_id, category, segment_frequencies: {id: count} }] }`

Extraction failures are logged but do not block TEI storage; an empty `entities.xml` is written instead.

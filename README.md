# HAPI FHIR MCP POC

A Docker Compose v2 stack that runs a fully-configured **HAPI FHIR R4** server backed by **PostgreSQL 18**, pre-loaded with synthetic clinical data, and exposed as a **Model Context Protocol (MCP) tool server** so any MCP-compatible AI client (Claude Desktop, Cursor, MCP Inspector) can query and mutate FHIR resources through natural language.

```
┌──────────────┐     JDBC      ┌──────────────────────────────┐
│ PostgreSQL 18│◄──────────────│  HAPI FHIR R4 v8.8.0        │ :8080
│  (hapi-db)   │               │  + Tester UI + MCP server    │
└──────────────┘               └───────┬──────────┬───────────┘
                                       │ FHIR REST │ POST /mcp
                              ┌────────▼────────┐  └─► MCP clients
                              │  seed (1-shot)  │      (Claude Desktop,
                              │  POSTs bundles  │       Cursor, Inspector)
                              └─────────────────┘
```

---

## What's inside

| Component | Technology | Purpose |
|-----------|-----------|---------|
| `db` | `postgres:18.3-alpine3.23` | Persistent FHIR data store |
| `hapi` | `hapiproject/hapi:v8.8.0-1` + custom Dockerfile | FHIR R4 server, Tester UI, **MCP server at `POST /mcp`** |
| `seed` | `alpine:3.21` + bash | One-shot container that POSTs FHIR transaction bundles on first boot |

---

## Quick start

### Prerequisites

- Docker Engine ≥ 24 with the Compose v2 plugin (`docker compose`)
- ~2 GB free RAM (HAPI is capped at 1 500 MB; PostgreSQL at 512 MB)
- Port **8080** available on the host

### 1. Clone and configure

```bash
git clone https://github.com/Konstantinos-Mavridis/hapi-fhir-mcp_poc.git
cd hapi-fhir-mcp_poc

# Copy the sample env file (defaults work for local dev)
cp .env.example .env
```

> **Production/non-local environments** – before exposing the stack on a network, generate a strong PostgreSQL password and restrict CORS (see [Security](#security)).

### 2. Start the stack

```bash
docker compose up --build
```

Allow ~90 seconds for HAPI to initialise Hibernate and for the seed container to finish. You will see `Seeding complete!` in the seed container's output when ready.

### 3. Verify

| URL | Description |
|-----|-------------|
| `http://localhost:8080/` | HAPI FHIR Tester UI |
| `http://localhost:8080/fhir` | FHIR R4 base endpoint |
| `http://localhost:8080/fhir/metadata` | CapabilityStatement (health indicator) |
| `http://localhost:8080/mcp` | MCP Streamable HTTP endpoint |

---

## Seeded data

Bundles are applied in filename order under `seed/bundles/`. Each is a FHIR transaction bundle; resources in later bundles reference those seeded earlier.

| Bundle | Resource type | Count | Highlights |
|--------|--------------|-------|-----------|
| `00-organizations.json` | Organization | 1 | Athens General Hospital |
| `01-practitioners.json` | Practitioner | 2 | Dr. Jane Smith (GP), Dr. Robert Johnson (Cardiologist) |
| `02-patients.json` | Patient | 3 | Alice Walker, Marcus Chen, Elena Rodriguez |
| `03-conditions.json` | Condition | 4 | T2DM · Hypertension · Atrial Fibrillation · Asthma |
| `04-observations.json` | Observation | 7 | BP × 2, HbA1c × 2, SpO2, HR, BMI |
| `05-encounters.json` | Encounter | 3 | Ambulatory visits linking patients/conditions |

### Sample FHIR queries

```bash
# All patients
curl http://localhost:8080/fhir/Patient

# Conditions for a specific patient
curl "http://localhost:8080/fhir/Condition?subject=Patient/patient-1"

# Observations for patient-2, newest first
curl "http://localhost:8080/fhir/Observation?subject=Patient/patient-2&_sort=-date"

# Full patient record ($everything)
curl "http://localhost:8080/fhir/Patient/patient-1/\$everything"
```

---

## MCP integration

The HAPI FHIR server exposes itself as an **MCP Streamable HTTP** tool server on `POST http://localhost:8080/mcp`. Any MCP-compatible client can connect to query or mutate FHIR resources through natural language.

### Claude Desktop

Add the following to `claude_desktop_config.json` (requires `npx` / Node 18+):

```json
{
  "mcpServers": {
    "hapi-fhir-mcp_poc": {
      "command": "npx",
      "args": ["mcp-remote@latest", "http://localhost:8080/mcp"]
    }
  }
}
```

Restart Claude Desktop. You can then ask questions like:
- *"List all patients in the FHIR store."*
- *"What conditions does patient-1 have?"*
- *"Create a new Observation for patient-2 with a blood-pressure reading of 130/85."*

### MCP Inspector (browser-based testing)

```bash
npx @modelcontextprotocol/inspector
```

Connect to `http://localhost:8080/mcp` using the **Streamable HTTP** transport.

### Cursor / other MCP clients

Point any MCP client that supports Streamable HTTP at `http://localhost:8080/mcp`.

---

## Project structure

```
hapi-fhir-mcp_poc/
├── compose.yml                  # Docker Compose stack definition
├── .env.example                 # Environment variable template
├── hapi/
│   ├── Dockerfile               # Multi-stage: compiles HealthCheck.java → extends hapiproject/hapi:v8.8.0-1
│   ├── HealthCheck.java         # Docker HEALTHCHECK: GETs /fhir/metadata, verifies CapabilityStatement
│   └── application.yaml        # Spring Boot / HAPI FHIR configuration (DB, MCP server, CORS, tester UI)
└── seed/
    ├── Dockerfile               # alpine:3.21 + bash; runs as non-root user `seed`
    ├── seed.sh                  # POSTs each bundle in alphabetical order; exits 1 on any failure
    └── bundles/
        ├── 00-organizations.json
        ├── 01-practitioners.json
        ├── 02-patients.json
        ├── 03-conditions.json
        ├── 04-observations.json
        └── 05-encounters.json
```

---

## Configuration reference

All runtime configuration lives in two files:

### `.env` (copy from `.env.example`)

| Variable | Default | Description |
|----------|---------|-------------|
| `COMPOSE_PROJECT_NAME` | `hapi-fhir_poc` | Names Docker images, volumes, networks |
| `POSTGRES_DB` | `hapi` | PostgreSQL database name |
| `POSTGRES_USER` | `user` | PostgreSQL user |
| `POSTGRES_PASSWORD` | `changeme` | **Change before any non-local deploy** |
| `HAPI_TESTER_SERVER_ADDRESS` | `http://localhost:8080/fhir` | Tester UI FHIR base URL (override for remote access) |

### `hapi/application.yaml`

Key sections:

| Section | What it controls |
|---------|-----------------|
| `spring.datasource` | JDBC URL, credentials (injected from env) |
| `spring.ai.mcp.server` | MCP server toggle, name, and system instructions |
| `hapi.fhir.tester` | Tester UI target server address |
| `hapi.fhir.validation` | FHIR resource validation (disabled by default for fast POC startup) |
| `hapi.fhir.cors` | CORS allowed origins (wildcard `*` by default – **restrict in production**) |

After editing `application.yaml`, apply changes with:

```bash
docker compose restart hapi
```

---

## Resource limits

| Container | Memory cap | Notes |
|-----------|-----------|-------|
| `db` | 512 MB | Sufficient for the seeded dataset |
| `hapi` | 1 500 MB | JVM heap is `25–75 %` of this cap via `InitialRAMPercentage` / `MaxRAMPercentage`; raise to `2g` on machines with more headroom |
| `seed` | — | Exits after seeding; no persistent footprint |

---

## Health checks

| Service | Mechanism | Interval | Retries | Start period |
|---------|-----------|----------|---------|--------------|
| `db` | `pg_isready` | 10 s | 10 | 20 s |
| `hapi` | `HealthCheck.java` – GETs `/fhir/metadata`, asserts `CapabilityStatement` in response body | 15 s | 15 | 60 s |

The `seed` container waits for `hapi` to pass its health check before posting any bundles. The `hapi` container waits for `db` to pass its health check before starting.

---

## Common operations

### Re-seed after a wipe

```bash
docker compose run --rm seed
```

### Stop (keep data)

```bash
docker compose down
```

### Full teardown (removes PostgreSQL volume)

```bash
docker compose down -v
```

### View logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f hapi
docker compose logs -f seed
```

### Rebuild after code changes

```bash
docker compose up --build
```

---

## Security

The defaults are intentionally permissive for local development. **Before exposing this stack beyond localhost:**

1. **Generate a strong PostgreSQL password:**
   ```bash
   openssl rand -base64 32
   ```
2. **Update `.env`:**
   ```
   POSTGRES_PASSWORD=<generated-password>
   ```
3. **Restrict CORS** in `hapi/application.yaml`:
   ```yaml
   hapi:
     fhir:
       cors:
         allowed_origin:
           - "https://your-trusted-domain.example"
   ```
4. **Do not commit `.env`** – it is already listed in `.gitignore`.

---

## Notes & known quirks

- **PostgreSQL 18 image availability** – `postgres:18.3-alpine3.23` may not be available in all regions. If the pull fails, pin to `postgres:17` in `compose.yml` as a fallback.
- **FHIR validation is disabled** by default (`hapi.fhir.validation.enabled: false`) to speed up POC startup. Enable it in `application.yaml` when strict conformance is required.
- **MCP `McpServerAnnotation*` auto-configurations are excluded** because HAPI FHIR's classpath conflicts with Spring AI MCP Server annotation scanning. The MCP server still works correctly via `spring.ai.mcp.server.enabled: true`.
- **Elasticsearch auto-configuration is excluded** to prevent Spring Boot from attempting to connect to a non-existent Elasticsearch instance.
- **Hibernate search is disabled** (`hibernate.search.enabled: false`) – all queries go through JPA/PostgreSQL only.

---

## License

[GPLv3](LICENSE)

# HAPI FHIR MCP POC

A Docker Compose v2 stack with HAPI FHIR R4, PostgreSQL 18, and pre-loaded synthetic clinical data.

```
┌──────────────┐     JDBC      ┌─────────────────┐
│ PostgreSQL 18│◄──────────────│  HAPI FHIR R4   │ :8080
│  (hapi-db)   │               │  + Tester UI    │
└──────────────┘               └────────┬────────┘
                                        │ FHIR REST
                               ┌────────▼────────┐
                               │   seed (1-shot)  │
                               │  POSTs bundles   │
                               └─────────────────┘
```

## Quick start

```bash
docker compose up --build
```

Wait ~90 s for HAPI to initialise Hibernate + seed to finish. Then:

| URL | Description |
|-----|-------------|
| http://localhost:8080/ | HAPI FHIR Tester UI |
| http://localhost:8080/fhir | FHIR R4 base endpoint |
| http://localhost:8080/fhir/metadata | CapabilityStatement |

## Seeded data

Bundles are applied in filename order. Each bundle is a FHIR transaction. Resources in later bundles reference those seeded earlier.

| Bundle | Resource | Count | Highlights |
|--------|----------|-------|-----------|
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

# Patient's conditions
curl "http://localhost:8080/fhir/Condition?subject=Patient/patient-1"

# All observations for patient-2, newest first
curl "http://localhost:8080/fhir/Observation?subject=Patient/patient-2&_sort=-date"

# Full patient record (everything linked)
curl "http://localhost:8080/fhir/Patient/patient-1/\$everything"
```

## Re-seed after wipe

```bash
docker compose run --rm seed
```

## Teardown

```bash
# Stop but keep data
docker compose down

# Full wipe (removes DB volume)
docker compose down -v
```

## Configuration

Edit `./hapi/application.yaml` to adjust HAPI settings (validation, CORS,
subscriptions, etc.) and restart: `docker compose restart hapi`.

### Security Setup

Before deploying to any environment beyond local development:

1. **Generate strong PostgreSQL password:**
   ```bash
   openssl rand -base64 32
   ```

2. **Update `.env` with the generated password:**
   ```
   POSTGRES_PASSWORD=<generated-password-here>
   ```

3. **Restrict CORS origins** in `./hapi/application.yaml` to only trusted domains.

> **PostgreSQL 18 note** – if `postgres:18` is not yet on Docker Hub in your region,
> pin to `postgres:17` in `compose.yml` as a fallback.

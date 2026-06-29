# Distribution Guide

Install guide for the FormaX Reporting Engine distribution.

## What's in this distribution

| File | What it's for |
|---|---|
| `formax-reporting-engine_<version>_amd64.deb` | The package — install this on a Debian/Ubuntu host, or use it to build the Docker image (below). Contains the compiled binary plus an example template/sample payload under `examples/`. |
| `Dockerfile` | Builds a runtime container image from the `.deb` above. Run `docker build -t formax-reporting-engine .` from inside this folder. |
| `FormaX-Reporting-Engine.postman_collection.json` | Every endpoint, ready to import into Postman. |
| `DISTRIBUTION.md` | This file. |

No Python (or anything else) needs to be installed on the target machine
beforehand — the package is fully self-contained.

## This is an Evaluation build

Printed on every startup and returned by `GET /health`:

```
FormaX 0.1.0 - Asynchronous Excel Reporting Engine
Edition: Evaluation (no expiry date, max 5 concurrent report renders)
```

- **No time limit.** The Evaluation edition does not expire.
- **Concurrency capped at 5.** `REPORTING_WORKER_CONCURRENCY` can be set
  higher, but the engine clamps it to 5 and logs a warning — at most 5
  reports render at the same time regardless. Submitted reports beyond
  that just wait in queue (`status: QUEUED`); none are rejected.

---

## Option A: install the .deb (systemd-managed, bare-metal)

```bash
sudo dpkg -i formax-reporting-engine_0.1.0_amd64.deb
```

This installs to `/opt/formax/reporting-engine`, creates a dedicated
unprivileged `formax` system user, data directories under
`/var/lib/formax/`, and a `systemd` unit. The installer prints next steps;
in short:

```bash
sudo nano /etc/formax/reporting-engine.env   # set REPORTING_JWT_SECRET
sudo systemctl enable --now formax-reporting-engine

sudo systemctl status formax-reporting-engine
sudo journalctl -u formax-reporting-engine -f
```

The example template + sample payload ship at
`/opt/formax/reporting-engine/examples/`.

To remove: `sudo dpkg -r formax-reporting-engine` (stops the service first;
data under `/var/lib/formax` and the env file at `/etc/formax/` are kept).

If you'd rather not install a package at all, the binary works standalone
too — extract it from the `.deb` without installing:

```bash
dpkg-deb -x formax-reporting-engine_0.1.0_amd64.deb extracted/
cd extracted/opt/formax/reporting-engine
REPORTING_TEMPLATES_DIR=./templates REPORTING_OUTPUTS_DIR=./outputs \
REPORTING_DB_PATH=./engine.db REPORTING_JWT_SECRET=replace-me \
  ./reporting-engine
```

## Option B: Docker (no host install)

The `.deb` is built for `linux/amd64`. On an amd64 Docker host (almost any
cloud VM) the plain commands below are enough. On an ARM host (Apple
Silicon Mac, AWS Graviton, etc.) add `--platform linux/amd64` to both
`docker build` and `docker run` — Docker emulates amd64 transparently.

```bash
docker build -t formax-reporting-engine .
# ARM host: docker build --platform linux/amd64 -t formax-reporting-engine .

docker run -d \
  --name formax-reporting-engine \
  -p 8000:8000 \
  -e REPORTING_JWT_SECRET=replace-with-a-long-random-value \
  -v formax-data:/var/lib/formax \
  formax-reporting-engine:latest
# ARM host: add --platform linux/amd64 right after `docker run -d`

docker logs -f formax-reporting-engine
```

Run both commands from inside this folder (the `Dockerfile` expects the
`.deb` alongside it). `/var/lib/formax` is a declared volume so
templates/outputs/the SQLite tracking DB survive container recreation.

---

## Using the shipped sample template + sample.json

The point of shipping these is: **don't write a JSON payload from scratch
— upload the example, ask the server what it expects, then adapt.**

```bash
# 1. Upload the example template (path depends on install method - see above)
curl -s -X POST http://localhost:8000/templates \
  -H "Authorization: Bearer $TOKEN" \
  -F name=hospital_report \
  -F file=@/opt/formax/reporting-engine/examples/hospital_report.xlsx
# {"id": "0199...", "name": "hospital_report", ...}

# 2. Ask the server for a sample payload built from that template's markers
curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/templates/0199.../sample
# Same shape as the bundled examples/hospital_report.sample.json, but with
# the real template_id already filled in instead of "<template_id>".

# 3. Adapt the sample's field values to real data, then submit it
curl -s -X POST http://localhost:8000/reports \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d @my_adapted_payload.json
# {"report_id": "...", "status": "QUEUED"}
```

`GET /templates/{id}/sample` is what you actually copy from once the
template has a real id (omit the `Authorization` header if
`REPORTING_JWT_SECRET` is unset).

## Using the Postman collection

1. Import `FormaX-Reporting-Engine.postman_collection.json` into Postman.
2. Set the collection variables: `base_url` (e.g. `http://localhost:8000`),
   `jwt_token` (leave blank if auth is disabled), `template_id`,
   `report_id`.
3. Run **Templates → Upload template** (attach
   `examples/hospital_report.xlsx` from the installed package to the
   `file` field) — copy the returned `id` into the `template_id` variable.
4. Run **Templates → Get template sample payload** to see the expected
   JSON shape for that template.
5. Run **Reports → Submit report**, then **Reports → Get report status**
   (poll until `SUCCESS`), then **Reports → Download rendered report**.

The collection's `Submit report` request body is pre-filled with a
complete example payload, with `template_id` pointed at the
`{{template_id}}` variable.

## Logging

Every log line is plain English with no embedded filesystem paths —
intentional, so logs are safe to forward to a centralized log collector
without leaking host details:

```
2026-06-29 00:05:54 INFO renderer.startup: FormaX 0.1.0 - Asynchronous Excel Reporting Engine
2026-06-29 00:05:54 INFO renderer.startup: Edition: Evaluation (no expiry date, max 5 concurrent report renders)
2026-06-29 00:05:54 INFO renderer.startup: Startup complete - ready to accept requests
```

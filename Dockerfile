# Builds the FormaX Reporting Engine Docker image directly from the
# distributable .deb — not from source. This file has no dependency on
# anything in renderer/ or the rest of the repository; given just the
# .deb it produces a runnable image.
#
# Build context must be a directory containing exactly the .deb to install
# alongside this Dockerfile. When distributed, both files sit together in
# dist/ - build from there:
#
#   cd dist/
#   docker build -t formax-reporting-engine .
#
# The installed .deb's postinst script creates the unprivileged `formax`
# user/group and /var/lib/formax data directories; its systemctl calls are
# guarded and no-op cleanly here since this image has no systemd.
FROM debian:bookworm-slim

COPY *.deb /tmp/formax-reporting-engine.deb
RUN dpkg -i /tmp/formax-reporting-engine.deb && rm -f /tmp/formax-reporting-engine.deb

# ── Required ──────────────────────────────────────────────────────────────────
# REPORTING_JWT_SECRET   Shared secret for signing API bearer tokens.
#                        Set a long random string (32+ chars).
#
# REPORTING_LICENSE      License JWT issued by FormaX.
#                        Required to activate the management dashboard.
#                        The report/template API works without it.
#
# ── Optional (defaults shown) ─────────────────────────────────────────────────
# REPORTING_WORKER_CONCURRENCY=5   Max reports rendered in parallel.
# REPORTING_OUTPUT_RETENTION_DAYS=0  Days to keep generated files (0 = forever).
# REPORTING_DASHBOARD_USERNAME     Dashboard login username (required for dashboard).
# REPORTING_DASHBOARD_PASSWORD     Dashboard login password (required for dashboard).
# REPORTING_HOST=0.0.0.0           Bind address.
# REPORTING_PORT=8000              HTTP port.
# REPORTING_ENABLE_DOCS=false      Expose /docs (OpenAPI). Keep false in production.
ENV REPORTING_TEMPLATES_DIR=/var/lib/formax/templates \
    REPORTING_OUTPUTS_DIR=/var/lib/formax/outputs \
    REPORTING_DB_PATH=/var/lib/formax/engine.db \
    REPORTING_WORKER_CONCURRENCY=5 \
    REPORTING_HOST=0.0.0.0 \
    REPORTING_PORT=8000

USER formax
WORKDIR /opt/formax/reporting-engine
EXPOSE 8000
VOLUME ["/var/lib/formax"]
ENTRYPOINT ["/opt/formax/reporting-engine/reporting-engine"]

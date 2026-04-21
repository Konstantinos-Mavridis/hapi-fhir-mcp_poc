# ── Stage 1: Compile the HealthCheck class using Java 21 ───────────────────────
FROM eclipse-temurin:21-jdk-alpine AS builder

WORKDIR /build

COPY HealthCheck.java .

# --release validates against the correct Java 21 API surface
# (-source/-target are deprecated since Java 17)
RUN javac --release 21 HealthCheck.java && \
    rm HealthCheck.java

# ── Stage 2: Final HAPI image with compiled health check ──────────────────────
FROM hapiproject/hapi:v8.8.0-1

# Use numeric UID 65532 (Distroless nonroot) instead of name to prevent silent failures.
# Distroless images don't include /etc/passwd, so username resolution fails silently.
# Numeric UIDs always work and fail loudly if the UID is invalid.
COPY --from=builder --chown=65532:65532 /build/HealthCheck.class /app/HealthCheck.class

HEALTHCHECK --interval=15s --timeout=10s --retries=15 --start-period=60s \
    CMD ["java", "-cp", "/app", "HealthCheck"]

EXPOSE 8080

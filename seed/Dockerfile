FROM alpine:3.21

# Install minimal dependencies and create non-root user
RUN apk add --no-cache bash curl && \
    adduser -D -s /sbin/nologin seed

WORKDIR /

# Copy with correct ownership
COPY --chown=seed:seed seed.sh /seed.sh
COPY --chown=seed:seed bundles/ /bundles/

RUN chmod +x /seed.sh && \
    chmod 700 /bundles && chmod 600 /bundles/*.json

# Run as non-root
USER seed

ENTRYPOINT ["/seed.sh"]

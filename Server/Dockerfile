FROM oven/bun:1.4.4@sha256:1d22548f177f4ff38e0c15baa3c2c46c6c2060ba2d1bc573bb4720b407548f1d AS dependencies
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production

FROM oven/bun:1.4.4@sha256:1d22548f177f4ff38e0c15baa3c2c46c6c2060ba2d1bc573bb4720b407548f1d
WORKDIR /app
COPY --from=dependencies --chown=bun:bun /app/node_modules ./node_modules
COPY --chown=bun:bun package.json ./
COPY --chown=bun:bun src ./src
ARG BALM_AUTH_REVISION=development
ENV NODE_ENV=production PORT=3000 BALM_AUTH_REVISION=${BALM_AUTH_REVISION}
USER bun
EXPOSE 3000
# Health ownership: deploy/healthcheck.md at the repository root.
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD ["bun", "-e", "const r = await fetch('http://127.0.0.1:3000/health', { signal: AbortSignal.timeout(3000) }); if (!r.ok) process.exit(1)"]
CMD ["bun", "src/index.ts"]

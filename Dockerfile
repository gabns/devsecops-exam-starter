# ---- Build stage ----
FROM node:20-alpine AS build

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY server.js ./

# ---- Runtime stage ----
FROM node:20-alpine

ENV NODE_ENV=production
WORKDIR /app

# Alpine's node image already ships a non-root "node" user (uid 1000)
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/package.json ./package.json
COPY --from=build --chown=node:node /app/server.js ./server.js

USER node

EXPOSE 3000

CMD ["node", "server.js"]

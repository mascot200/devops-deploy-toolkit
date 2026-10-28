# syntax=docker/dockerfile:1
# Node.js app. Copy to your repo root as ./Dockerfile and adjust the lines marked ADJUST.
# Build:  docker build -t my-app:dev .      Run: docker run --rm -p 8080:8080 my-app:dev

FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
# ADJUST: remove if you have no build step (TypeScript, bundler, ...)
RUN npm run build --if-present
RUN npm prune --omit=dev

FROM node:22-alpine
ENV NODE_ENV=production PORT=8080
WORKDIR /app
COPY --from=build --chown=node:node /app ./
# never run as root inside the container
USER node
EXPOSE 8080
# ADJUST: your start command; the app must listen on $PORT and serve GET /healthz -> 200
CMD ["node", "server.js"]

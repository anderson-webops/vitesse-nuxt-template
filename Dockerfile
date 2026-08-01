# syntax=docker/dockerfile:1.7

FROM node:24.18.1-alpine3.24@sha256:f70403e87646dc51b45295f4b8b70cdad0b63d2297c4c9899119b03f7af7a6b3 AS npm-base

ARG NPM_VERSION=12.0.2
WORKDIR /app

RUN npm install --global "npm@${NPM_VERSION}" --allow-scripts=npm \
    && npm --version \
    && rm -rf /root/.npm

FROM npm-base AS build-dependencies

COPY .npmrc package.json package-lock.json ./
COPY front-end/package.json ./front-end/package.json
COPY back-end/package.json ./back-end/package.json

RUN --mount=type=cache,id=vitesse-nuxt-template-npm-cache,target=/root/.npm \
    SKIP_INSTALL_SIMPLE_GIT_HOOKS=1 NUXT_TELEMETRY_DISABLED=1 \
    npm ci --include=optional

FROM build-dependencies AS builder

COPY . .
RUN NUXT_TELEMETRY_DISABLED=1 npm run build

FROM npm-base AS api-dependencies

WORKDIR /app/back-end
COPY .npmrc ./
COPY back-end/package.json back-end/package-lock.json ./

RUN --mount=type=cache,id=vitesse-nuxt-template-api-npm-cache,target=/root/.npm \
    npm ci --omit=dev --include=optional --ignore-scripts

FROM node:24.18.1-alpine3.24@sha256:f70403e87646dc51b45295f4b8b70cdad0b63d2297c4c9899119b03f7af7a6b3 AS api

ENV HOST=0.0.0.0 \
    NODE_ENV=production \
    PORT=3006 \
    TRUST_PROXY_HOPS=1

WORKDIR /app

RUN rm -rf \
        /opt/yarn-v1.22.22 \
        /root/.npm \
        /usr/local/lib/node_modules/corepack \
        /usr/local/lib/node_modules/npm \
    && rm -f \
        /usr/local/bin/corepack \
        /usr/local/bin/npm \
        /usr/local/bin/npx \
        /usr/local/bin/yarn \
        /usr/local/bin/yarnpkg

COPY --from=api-dependencies --chown=node:node /app/back-end/node_modules ./back-end/node_modules
COPY --from=builder --chown=node:node /app/back-end/dist ./back-end/dist
COPY --chown=node:node back-end/package.json ./back-end/package.json

USER node

EXPOSE 3006

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["node", "-e", "fetch('http://127.0.0.1:3006/api/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"]

STOPSIGNAL SIGTERM
CMD ["node", "back-end/dist/server.js"]

FROM nginx:stable-alpine@sha256:97d490c12ba55b4946b01546d1c3ed324e8d41ab1c9fcb2a616aa470620e5b46 AS frontend

COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=builder --chown=nginx:nginx /app/front-end/.output/public /usr/share/nginx/html

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["wget", "--spider", "--quiet", "http://127.0.0.1:8080/healthz"]

CMD ["nginx", "-g", "daemon off;"]

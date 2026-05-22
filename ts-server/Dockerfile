FROM node:20-alpine

WORKDIR /app

# Upgrade npm to avoid "Invalid Version" bug seen with npm 10.8.2 on some lockfiles
RUN npm i -g npm@11.11.0

COPY package.json package-lock.json* ./

# `npm ci` fails when package.json was changed without refreshing package-lock.json
# (e.g. new deps). `npm install` reconciles from package.json and keeps deploys working.
# After adding dependencies, run `npm install` locally and commit an updated lockfile if you want `npm ci` again.
RUN npm install --omit=dev --no-audit --no-fund

COPY . .

EXPOSE 3000
CMD ["npm","start"]

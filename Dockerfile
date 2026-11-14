FROM node:22.15.0-slim

WORKDIR /app
COPY index.html ./index.html
COPY assets ./assets
COPY server.js ./server.js

ENV NODE_ENV=production
CMD ["node", "server.js"]

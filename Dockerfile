FROM node:20-alpine

WORKDIR /app

COPY app/package.json ./
COPY app/server.js ./

EXPOSE 8080

USER node

CMD ["node", "server.js"]

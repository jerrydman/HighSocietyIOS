FROM node:20-alpine
WORKDIR /app
COPY package.json server.js engine.js ./
ENV PORT=8080 DATA_DIR=/data
EXPOSE 8080
CMD ["node", "server.js"]

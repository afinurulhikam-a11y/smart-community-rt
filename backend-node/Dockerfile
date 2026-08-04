# Dockerfile untuk Backend Node.js (Smart Community RT)
FROM node:20-alpine

WORKDIR /app

# Copy manifest dependensi
COPY package*.json ./

# Install dependensi produksi
RUN npm ci --only=production

# Copy seluruh source code backend
COPY . .

# Expose port REST API & WebSocket
EXPOSE 3001

# Command utama menjalankan server
CMD ["node", "src/index.js"]

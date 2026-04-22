# --- Estgio 1: Build ---
FROM node:18-alpine AS builder

# Define o diretrio de trabalho
WORKDIR /app

# Copia arquivos de dependncias
# Isso aproveita o cache do Docker se o package.json no mudar
COPY package*.json ./

# Instala apenas as dependncias (incluindo devDependencies se necessrio para build)
RUN npm install

# Copia o restante do cdigo fonte
COPY . .

# --- Estgio 2: Runner ---
FROM node:18-alpine

# Define o diretrio de trabalho
WORKDIR /app

# Atualiza pacotes do sistema para corrigir vulnerabilidades conhecidas
# CVE-2025-15467: libcrypto3/libssl3 (OpenSSL) → corrigido na 3.3.6-r0
RUN apk upgrade --no-cache

# Copia as dependncias do estgio de build
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/app.js ./app.js

# Define variveis de ambiente padro (no sensveis)
ENV NODE_ENV=production
ENV PORT=3000

# Porta que a aplicao exppe
EXPOSE 3000

# Segurana: Executa a aplicao com um usurio sem privilgios root (j incluso na imagem alpine)
USER node

# Comando para iniciar a aplicao
CMD ["npm", "start"]

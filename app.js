const express = require("express");
const helmet = require("helmet");
const cors = require("cors");
const app = express();

// ─── Logs Estruturados em JSON ───────────────────────────────────────────────
// Emite logs no formato JSON para facilitar ingestão pelo CloudWatch Logs Insights
// Campos padrão: timestamp, level, method, url, status, responseTime, ip
function logRequest(req, res, startTime) {
  const responseTime = Date.now() - startTime;
  const logEntry = {
    timestamp: new Date().toISOString(),
    level: res.statusCode >= 500 ? "ERROR" : res.statusCode >= 400 ? "WARN" : "INFO",
    method: req.method,
    url: req.originalUrl,
    status: res.statusCode,
    responseTimeMs: responseTime,
    ip: req.headers["x-forwarded-for"] || req.socket.remoteAddress,
    userAgent: req.headers["user-agent"] || "-",
    environment: process.env.NODE_ENV || "development",
  };
  console.log(JSON.stringify(logEntry));
}

// Middleware de logging (intercepta todas as respostas)
app.use((req, res, next) => {
  const startTime = Date.now();
  res.on("finish", () => logRequest(req, res, startTime));
  next();
});

// ─── Segurança ───────────────────────────────────────────────────────────────
app.use(helmet());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS || "*" }));

// ─── Gerenciamento de Segredos via Variáveis de Ambiente ─────────────────────
const PORT = process.env.PORT || 3000;
const DATABASE_URL = process.env.DATABASE_URL || "Não configurada";
const API_SECRET_KEY = process.env.API_SECRET_KEY || "Não configurada";

// ─── Rotas ───────────────────────────────────────────────────────────────────
app.get("/", (req, res) => {
  res.json({
    message: "Bem-vindo ao App Lacrei Saude!",
    status: "Online",
    environment: process.env.NODE_ENV || "development",
  });
});

app.get("/health", (req, res) => {
  res.status(200).send("OK");
});

app.get("/status", (req, res) => {
  res.json({
    status: "Service is up and running",
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  });
});

app.get("/config-check", (req, res) => {
  const isDbConfigured = DATABASE_URL !== "Não configurada";
  const isSecretConfigured = API_SECRET_KEY !== "Não configurada";

  res.json({
    database_ready: isDbConfigured,
    secret_ready: isSecretConfigured,
    message: "Configurações carregadas via variáveis de ambiente.",
  });
});

module.exports = app;

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(JSON.stringify({
      timestamp: new Date().toISOString(),
      level: "INFO",
      message: `Servidor iniciado`,
      port: PORT,
      environment: process.env.NODE_ENV || "development",
    }));
  });
}

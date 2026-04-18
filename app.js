const express = require("express");
const helmet = require("helmet");
const cors = require("cors");
const app = express();

// Configurao de Segurana
app.use(helmet());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS || "*" }));

// Gerenciamento de Segredos: Lendo via variveis de ambiente
const PORT = process.env.PORT || 3000;
const DATABASE_URL = process.env.DATABASE_URL || "No configurada";
const API_SECRET_KEY = process.env.API_SECRET_KEY || "No configurada";

app.get("/", (req, res) => {
  res.json({
    message: "Bem-vindo ao App Lacrei Sade!",
    status: "Online",
    environment: process.env.NODE_ENV || "development",
  });
});

app.get("/health", (req, res) => {
  res.status(200).send("OK");
});

app.get("/config-check", (req, res) => {
  const isDbConfigured = DATABASE_URL !== "No configurada";
  const isSecretConfigured = API_SECRET_KEY !== "No configurada";

  res.json({
    database_ready: isDbConfigured,
    secret_ready: isSecretConfigured,
    message: "Configuraes carregadas via variveis de ambiente.",
  });
});

module.exports = app;

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`Servidor rodando na porta ${PORT}`);
  });
}

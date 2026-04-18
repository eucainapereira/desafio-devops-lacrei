const request = require("supertest");
const app = require("./app"); // Alterado para app.js refatorado

describe("GET /health", () => {
  it("deve retornar status 200 e texto OK", async () => {
    const response = await request(app).get("/health");
    expect(response.statusCode).toBe(200);
    expect(response.text).toBe("OK");
  });
});

describe("GET /config-check", () => {
  it("deve retornar JSON com status de configurao", async () => {
    const response = await request(app).get("/config-check");
    expect(response.statusCode).toBe(200);
    expect(response.body).toHaveProperty("database_ready");
    expect(response.body).toHaveProperty("secret_ready");
  });
});

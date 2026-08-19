const http = require("http");

const port = process.env.PORT || 8080;
const dbPassword = process.env.DB_PASSWORD;
const expectedDbPassword = process.env.EXPECTED_DB_PASSWORD;

const server = http.createServer((req, res) => {
  if (req.url === "/healthz") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("ok");
    return;
  }

  if (req.url === "/readyz") {
    if (!dbPassword) {
      res.writeHead(503, { "Content-Type": "text/plain" });
      res.end("DB_PASSWORD not available\n");
      return;
    }
    if (expectedDbPassword && dbPassword !== expectedDbPassword) {
      res.writeHead(503, { "Content-Type": "text/plain" });
      res.end("DB_PASSWORD does not match EXPECTED_DB_PASSWORD\n");
      return;
    }
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("ok\n");
    return;
  }

  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("Hello, World! (invoice-sync)\n");
});

server.listen(port, () => {
  console.log(`invoice-sync listening on port ${port}`);
});

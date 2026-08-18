const http = require("http");

const port = process.env.PORT || 8080;

const server = http.createServer((req, res) => {
  if (req.url === "/healthz") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("ok");
    return;
  }

  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("Hello, World! (invoice-sync)\n");
});

server.listen(port, () => {
  console.log(`invoice-sync listening on port ${port}`);
});

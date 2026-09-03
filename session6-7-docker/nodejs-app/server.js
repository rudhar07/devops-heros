// Minimal Express web server that serves a Hello World HTML page.
const express = require("express");

const app = express();
// Inside the container we always listen on 3000; the host port is chosen with `docker run -p`.
const PORT = process.env.PORT || 3000;

app.get("/", (req, res) => {
  res.type("html").send(`<!DOCTYPE html>
<html lang="en">
  <head><meta charset="utf-8"><title>Hello World - Node.js</title></head>
  <body>
    <h1>Hello World</h1>
    <p>Served by Node.js ${process.version} + Express inside a Docker container.</p>
  </body>
</html>`);
});

// Bind to 0.0.0.0 so the server is reachable from outside the container, not just from localhost inside it.
app.listen(PORT, "0.0.0.0", () => {
  console.log(`hello-nodejs listening on port ${PORT}`);
});

import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, resolve } from "node:path";

const args = process.argv.slice(2);
const valueAfter = name => {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
};
const port = Number(valueAfter("--port")) || 4173;
const host = valueAfter("--host") || "0.0.0.0";
const root = process.cwd();
const contentTypes = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8",
  ".png": "image/png"
};

createServer(async (request, response) => {
  try {
    const pathname = new URL(request.url, "http://localhost").pathname;
    const candidate = resolve(root, `.${pathname === "/" ? "/index.html" : pathname}`);
    if (!candidate.startsWith(root)) throw new Error("invalid path");
    const details = await stat(candidate);
    const filePath = details.isDirectory() ? resolve(candidate, "index.html") : candidate;
    const body = await readFile(filePath);
    response.writeHead(200, {
      "Content-Type": contentTypes[extname(filePath)] || "application/octet-stream",
      "Cache-Control": "no-cache"
    });
    response.end(body);
  } catch {
    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("Arquivo não encontrado");
  }
}).listen(port, host, () => {
  console.log(`MeuKM disponível na porta ${port}`);
});

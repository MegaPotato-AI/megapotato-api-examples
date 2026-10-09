// Upscale one photo with the MegaPotato API: upload it, wait for the result, download it.
//
// Usage:  node upscale.mjs photo.jpg [scale]     scale: 1 (refine, same size), 2, 4 (default) or 8
// Needs:  Node.js 18+ (no dependencies), and your API key in the MEGAPOTATO_API_KEY
//         environment variable.
import { randomUUID } from "node:crypto"
import { readFile, writeFile } from "node:fs/promises"
import { basename, extname } from "node:path"

const API = "https://megapotato.app/v1"
const [src, scale = "4"] = process.argv.slice(2)
const fail = (message) => {
  console.error(message)
  process.exit(1)
}
if (!src || !process.env.MEGAPOTATO_API_KEY) {
  fail("usage: MEGAPOTATO_API_KEY=... node upscale.mjs photo.jpg [scale]")
}
const headers = { Authorization: `Bearer ${process.env.MEGAPOTATO_API_KEY}` }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

// { type, message } of an API error, or the raw body if it isn't the usual JSON.
function errorOf(text) {
  try {
    const { type, message } = JSON.parse(text).error
    return { type, message }
  } catch {
    return { type: "error", message: text.slice(0, 200) }
  }
}

// One API call. Retries what can succeed later (429, 5xx, network errors) and stops on
// everything else.
async function call(path, init = {}) {
  for (let attempt = 0; attempt < 8; attempt++) {
    let res
    try {
      res = await fetch(`${API}${path}`, { ...init, headers: { ...headers, ...init.headers } })
    } catch {
      await sleep(2 ** attempt * 1000)
      continue
    }
    const text = await res.text()
    if (res.ok) return JSON.parse(text)
    const { type, message } = errorOf(text)
    // spend_limit_reached is a 429 too, but it only resets at 00:00 UTC: not worth waiting for.
    if (res.status >= 500 || (res.status === 429 && type !== "spend_limit_reached")) {
      await sleep(Number(res.headers.get("retry-after") ?? 2 ** attempt) * 1000)
      continue
    }
    fail(`${res.status} ${type}: ${message}`)
  }
  fail("gave up after repeated temporary errors")
}

// A FormData body is re-sent in full on every retry.
const form = new FormData()
form.append("file", new Blob([await readFile(src)]), basename(src))
form.append("upscale", scale)
// One key per run: if the upload is retried, the server returns the same job and charges once.
const upload = await call("/upscale", {
  method: "POST",
  headers: { "Idempotency-Key": `upscale-${randomUUID()}` },
  body: form,
})
console.log(`job ${upload.id}: ${upload.cost_chips} chips`)

// Each request waits up to 55 s on the server. Read the job at least once even if the upload
// answer already says "completed": only this request carries result_url and error.
let job
for (;;) {
  job = await call(`/jobs/${upload.id}?wait=55`)
  if (job.status === "completed" || job.status === "failed") break
  console.log(job.status + (job.eta_seconds ? `, about ${Math.round(job.eta_seconds)} s left` : ""))
}

if (job.status === "failed") fail(`failed: ${job.error}`)

// The link works for about an hour. Results are PNG; test keys return a sample JPEG.
const result = await fetch(job.result_url)
if (!result.ok) fail(`download failed: HTTP ${result.status}`)
const ext = extname(new URL(job.result_url).pathname) || ".png"
const out = `${src.slice(0, src.length - extname(src).length)}_x${scale}${ext}`
await writeFile(out, Buffer.from(await result.arrayBuffer()))
console.log(`saved ${out}`)

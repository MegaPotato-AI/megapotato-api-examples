# MegaPotato API examples

Ready-to-run scripts for the [MegaPotato](https://megapotato.app) image upscaling API. Send a photo
and get it back 2×, 4× or 8× larger, up to 16 400 px on the long side, or sharpened at its original
size. The API runs the same models at the same prices as the website.

Full reference: **[megapotato.app/developers](https://megapotato.app/developers)**

## Get a key

1. Sign in at [megapotato.app](https://megapotato.app) and open the
   [API section of your account page](https://megapotato.app/account#api).
2. Create a **test key** (`mp_test_…`) to try the whole flow for free. Uploads are checked and priced
   exactly like real ones, but nothing runs and nothing is charged: every job comes back completed
   with a sample picture.
3. Live keys (`mp_live_…`) unlock with your first chip pack. They draw on the same chip balance as
   the website.

```sh
export MEGAPOTATO_API_KEY=mp_test_...
```

Keep keys on your server, never in a web page, a mobile app or a repository.

## Examples

| File | What it does | Needs |
| --- | --- | --- |
| [`upscale.sh`](upscale.sh) | Upscale a photo from the command line | curl, jq |
| [`upscale.py`](upscale.py) | The same in Python | Python 3.9+, [requests](requirements.txt) |
| [`upscale.mjs`](upscale.mjs) | The same in Node.js | Node.js 18+, no dependencies |
| [`quote.sh`](quote.sh) | Price a photo before sending it | curl |

```console
$ bash upscale.sh photo.jpg 4
job 6f6f4c1e-…: 8 chips
running, about 6 s left
saved photo_x4.png
```

```sh
python upscale.py photo.jpg 2
node upscale.mjs photo.jpg 8
bash quote.sh 4000 3000 2
```

The second argument is the factor: `1` (refine: same size, sharper detail), `2`, `4` (the default)
or `8`. The result is saved next to the photo. With a test key it is the sample picture, saved as
`.jpg`.

## How it works

Two requests do the job:

```sh
# 1. Send the photo
curl https://megapotato.app/v1/upscale \
  -H "Authorization: Bearer $MEGAPOTATO_API_KEY" \
  -H "Idempotency-Key: photo-001" \
  -F file=@photo.jpg \
  -F upscale=4
# {"id":"6f6f4c1e-…","status":"queued","upscale":4,"cost_chips":8}

# 2. Wait for the result (the server holds the request for up to 55 s)
curl "https://megapotato.app/v1/jobs/6f6f4c1e-…?wait=55" \
  -H "Authorization: Bearer $MEGAPOTATO_API_KEY"
# {"id":"6f6f4c1e-…","status":"completed","result_url":"https://…","error":null,…}
```

- **POST /v1/upscale** returns a job id and its price. The chips are held right away and come back
  automatically if processing fails.
- **GET /v1/jobs/{id}?wait=55** answers as soon as the job is done, or after 55 s with its current
  status (`queued`, `running`, `completed` or `failed`). One or two calls usually cover a whole job.
- **result_url** is a PNG link that works for about an hour. Fetch the job again for a fresh link;
  results are kept for 90 days.
- **POST /v1/quote** prices a size without uploading anything, as in `quote.sh`.

The scripts also handle the parts that are easy to get wrong:

- Every upload carries an `Idempotency-Key`, so a retried upload returns the same job and is
  charged once.
- `429` and `5xx` responses and network errors are retried, waiting for `Retry-After` when the
  server sends it. The one exception is `spend_limit_reached`, which resets only at 00:00 UTC.
- Any other error stops the script with its message. Errors always have the same shape:
  `{"error": {"type": "insufficient_credits", "message": "insufficient chips: available 3, needed 8"}}`

## Limits

- Input: PNG, JPG, WEBP or HEIC, up to 6 000 px on the long side and 40 MB.
- Output: up to 16 400 px on the long side, so pick a smaller factor for large photos.
- Up to 10 photos in progress at once per account, and up to 100 uploads a minute per key.
- A daily API spending limit (5 000 chips by default, and you can set a lower one) keeps a leaked
  key from draining your balance.

The [reference](https://megapotato.app/developers#limits) always has the current values.

## Pricing

The same as on the website: one-time chip packs, no subscription, and chips never expire. The
price of a photo depends on the size of the result. Check any size for free with `quote.sh`, and
see the packs on the [pricing page](https://megapotato.app/pricing).

The API is in public beta. Within `/v1` changes are only additive, such as new fields and new
error types.

## Support

Questions and problems: [support@megapotato.app](mailto:support@megapotato.app)

## License

[MIT](LICENSE)

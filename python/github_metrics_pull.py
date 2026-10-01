"""Daily GitHub API pull — stars / forks / contributor count.

The "genuinely live" data source per docs/PROJECT_BRIEF.md §3.2 — proves the
pipeline runs on a real schedule rather than a one-off snapshot.

Appends one row per (fetched_at, repo) to `olist_raw.github_metrics`
via a batch LOAD job (WRITE_APPEND, sandbox-safe). Over weeks of
scheduled runs this accumulates a per-repo time series that any
downstream mart can read from.

Repos chosen to reflect the project's own stack (three we actually
depend on):
    * dbt-labs/dbt-core          — the dbt runtime we use
    * googleapis/python-bigquery — the BQ client library
    * astral-sh/uv               — the Python installer that unblocked
                                   this whole pipeline locally

Contributor count uses the /contributors?per_page=1 trick — GitHub
returns a Link header with rel="last" whose page number equals the
total contributor count (up to their internal cap of ~500 for very
large repos, which is fine here — we're tracking direction, not
absolute levels).

Auth: reads GH_API_TOKEN from env if set (bumps GitHub's rate limit
from 60 to 5,000 requests/hour). GitHub Actions provides one
automatically. Local runs work without it but count against the
anonymous 60/hour quota per IP.

BigQuery auth: Application Default Credentials — set locally by
`gcloud auth application-default login`, set in CI by
`google-github-actions/auth@v2` writing a service-account keyfile
and pointing GOOGLE_APPLICATION_CREDENTIALS at it.
"""
from __future__ import annotations

import io
import json
import os
import re
import urllib.error
import urllib.request
from datetime import datetime, timezone

from google.cloud import bigquery

REPOS: list[str] = [
    "dbt-labs/dbt-core",
    "googleapis/python-bigquery",
    "astral-sh/uv",
]

PROJECT_ID = "ecommerce-channel-attribution"
DATASET = "olist_raw"
TABLE = f"{PROJECT_ID}.{DATASET}.github_metrics"
LOCATION = "EU"


def gh_get(path: str) -> tuple[dict | list, dict[str, str]]:
    """GET https://api.github.com{path}. Returns (parsed JSON body, headers)."""
    req = urllib.request.Request(f"https://api.github.com{path}")
    req.add_header("User-Agent", "ecommerce-attribution-cron")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    token = os.getenv("GH_API_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = json.load(resp)
        headers = {k: v for k, v in resp.headers.items()}
    return body, headers


def contributors_count(repo: str) -> int | None:
    """Total contributors via the Link-header pagination trick.

    GitHub's /contributors endpoint returns paginated results; asking
    for per_page=1 forces one contributor per page, so the Link
    header's `rel="last"` page number == total contributor count.
    Returns None if the header is missing (repo has 0 or 1 contributor,
    or GitHub omitted the header for some other reason).
    """
    _, headers = gh_get(f"/repos/{repo}/contributors?per_page=1&anon=0")
    link = headers.get("Link", "") or headers.get("link", "")
    for part in link.split(","):
        if 'rel="last"' in part:
            m = re.search(r"[?&]page=(\d+)", part)
            if m:
                return int(m.group(1))
    return None


def collect_rows() -> list[dict]:
    now = datetime.now(timezone.utc).isoformat()
    rows: list[dict] = []
    for repo in REPOS:
        body, _ = gh_get(f"/repos/{repo}")
        rows.append(
            {
                "fetched_at": now,
                "repo": repo,
                "stars": body["stargazers_count"],
                "forks": body["forks_count"],
                "contributors": contributors_count(repo),
            }
        )
    return rows


def load_to_bq(rows: list[dict]) -> None:
    client = bigquery.Client(project=PROJECT_ID, location=LOCATION)
    schema = [
        bigquery.SchemaField("fetched_at", "TIMESTAMP", mode="REQUIRED"),
        bigquery.SchemaField("repo", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("stars", "INT64"),
        bigquery.SchemaField("forks", "INT64"),
        bigquery.SchemaField("contributors", "INT64"),
    ]
    job_config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
    )
    body = "\n".join(json.dumps(r) for r in rows).encode()
    job = client.load_table_from_file(io.BytesIO(body), TABLE, job_config=job_config)
    job.result()


def main() -> None:
    rows = collect_rows()
    load_to_bq(rows)
    print(f"appended {len(rows)} rows to {TABLE}")
    for r in rows:
        print(
            f"  {r['repo']:32s}  stars={r['stars']:>7}  "
            f"forks={r['forks']:>6}  contributors={r['contributors']}"
        )


if __name__ == "__main__":
    main()

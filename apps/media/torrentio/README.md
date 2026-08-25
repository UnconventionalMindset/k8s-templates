# Torrentio (Self-Hosted)

This directory contains the manifests to deploy a self-hosted instance of the Torrentio Stremio addon, using the [Knight Crawler](https://github.com/knightcrawler-stremio/knightcrawler) fork.

## Installation

```bash
k apply -f apps/media/torrentio/namespace.yaml
k apply -f apps/media/torrentio/torrentio.yaml
k apply -f apps/media/torrentio/ingress.yaml
```

## Configuration

1.  Access the addon configuration page at `https://torrentio.umhomelab.com/configure`.
2.  Enter your Real Debrid API Key (NOT the URL, just the token).
3.  Click "Install" or copy the generated link to add it to your Stremio client.

## Setup Notes

### Database
The application requires a PostgreSQL database. The current deployment uses the existing `postgres` service in the `db` namespace.
**Important:** The tables must be created manually if they don't exist.

Access the postgres pod:
```bash
kubectl run postgres-admin --image=postgres:16 --restart=Never --env="PGPASSWORD=JG1@postgres" --rm -it -- psql -h 10.43.109.37 -U jac -d knightcrawler
```

Run the schema creation SQL (see `schema.sql` if available, or reconstruct from models).

### Redis
The application uses the existing Redis service (`redis-master.db.svc.cluster.local`).
Authentication is handled via a workaround in the `REDIS_HOST` environment variable: `:password@hostname`.

### Docker Image
Image used: `gabisonfire/knightcrawler-addon:latest`

## Troubleshooting
-   If you see `SequelizeDatabaseError: relation "files" does not exist`, you need to create the tables.
-   If you see `Not a valid moch provider`, check your Stremio addon URL configuration. Ensure your API key is correct and not a URL.
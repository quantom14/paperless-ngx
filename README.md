# Paperless-ngx on Raspberry Pi (Docker + VPN)

This repository contains the Docker configuration to run [paperless-ngx](https://github.com/paperless-ngx/paperless-ngx)
on a Raspberry Pi.
It is designed for **local VPN-only access**, safe backups, and reproducible deployment.

## Features

* Docker Compose setup with PostgreSQL and Redis
* Secrets stored in a local `.env` (never committed)
* WireGuard VPN for secure remote access
* Daily backups of database and document volumes

---

## Setup

### 1. Prerequisites

* Raspberry Pi running a recent 64-bit OS
* Docker & Docker Compose installed  
  `curl -fsSL https://get.docker.com | sh`
  `sudo apt install docker-compose`
* Git

### 2. Clone the repository

`git clone https://github.com/quantom14>/paperless-ngx.git`
`cd paperless-ngx`

### 3. Create the `.env` file

Create a file named `.env` in the project root (it is ignored by git):

``` 
POSTGRES_DB=paperless
POSTGRES_USER=paperless
POSTGRES_PASSWORD=<strong password>
PAPERLESS_DBPASS=<same strong password>
PAPERLESS_SECRET_KEY=<output of: openssl rand -hex 32>
```

### 4. Start the stack

`docker compose up -d`

The web UI listens on internal port 8000 but is not exposed to the public network.

### 5. Remote access (VPN)

Install PiVPN and choose WireGuard.  
Create client profiles for your laptop and phone, import them into the WireGuard apps,
and connect.  
When connected, open `http://<pi-vpn-ip>:8000` in a browser.

---

## Backups

Backups include:

* PostgreSQL dump (db-YYYYMMDD-HHMMSS.sql)
* PostgreSQL volume snapshot (pgdata-*.tar.gz)
* Paperless data (data-*.tar.gz)
* Paperless media (media-*.tar.gz)

Backups are stored in the `backup/` directory and should be copied to external storage.

### Manual backup

./backup/backup.sh

### Automated daily backup

See backup/README.txt for scheduling with cron.

---

## Restore

1. Stop the stack: docker compose down
2. Restore volumes from the latest tarballs (use tar xzf).
3. Restore the database:  
   cat backup/db-<date>.sql | docker compose exec -T db psql -U $POSTGRES_USER $POSTGRES_DB
4. Start again: docker compose up -d

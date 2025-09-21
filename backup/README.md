# Backup and Restore

The `backup.sh` script creates timestamped archives of all important volumes.

## Manual run

From the repository root:
`./backup.sh`

## Automatic daily run at 02:00

Use cron to schedule:

1. Edit the cron table:
   `crontab -e`

2. Add the following line (adjust path to your repo):
   `0 2 * * * /bin/bash ~/projects/paperless-ngx/backup/backup.sh >> ~/projects/paperless-ngx/backup/backup.log 2>&1`

    * `0 2 * * *` = every day at 02:00
    * Output and errors are appended to backup.log

Check with:
`crontab -l`

## Verify backups

List recent backups:
`ls -lh backup/`

Always copy or sync the backup directory to external storage (NAS, USB drive, or cloud).

## Restore

1. Stop containers:
   `docker compose down`

2. Extract the desired archive back into the corresponding volume. Example for pgdata:
   `docker run --rm -v paperless-ngx_pgdata:/volume -v $(pwd)/backup:/backup alpine sh -c "cd /volume && tar xzf /backup/pgdata-YYYYMMDD-HHMMSS.tar.gz --strip 1"`

3. Restore database if using SQL dump:
   `cat backup/db-YYYYMMDD-HHMMSS.sql | docker compose exec -T db psql -U $POSTGRES_USER $POSTGRES_DB`

4. Start again:
   `docker compose up -d`

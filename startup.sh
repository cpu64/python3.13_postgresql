#!/bin/bash

export PGHOST="${PGHOST:-localhost}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-password}"
export PGDATABASE="${PGDATABASE:-mydb}"
export PGDIR="${PGDIR:-/db}"

export PGDATA="$PGDIR/data"
export PGINIT="$PGDIR/init"
export PGLOGS="$PGDIR/logs"

# Create /db directory if it doesn't exist
mkdir -p $PGDATA $PGINIT $PGLOGS

# Set the correct permissions for PostgreSQL to access /db
chown -R postgres:postgres $PGDATA $PGINIT $PGLOGS

# Initialize PostgreSQL database (only if it's not initialized yet)
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "Initializing PostgreSQL database..."
    su -c "/usr/lib/postgresql/*/bin/initdb -D $PGDATA" postgres
fi

# Start the PostgreSQL service
echo "Starting PostgreSQL..."
su -c "/usr/lib/postgresql/*/bin/pg_ctl start -D $PGDATA -l $PGLOGS/postgresql.log" postgres

# Create the PostgreSQL user and database if they don't exist
echo "Creating user and database if they don't exist..."
psql -U $PGUSER -h $PGHOST -d postgres -c "SELECT 1 FROM pg_database WHERE datname = '$PGDATABASE'" | grep -q 1 || psql -U $PGUSER -h $PGHOST -d postgres -c "CREATE DATABASE $PGDATABASE;"
psql -U $PGUSER -h $PGHOST -d postgres -c "SELECT 1 FROM pg_roles WHERE rolname = '$PGUSER'" | grep -q 1 || psql -U $PGUSER -h $PGHOST -d postgres -c "CREATE USER $PGUSER WITH PASSWORD '$PGPASSWORD';"

# Grant privileges to the user on the database
psql -U $PGUSER -h $PGHOST -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE $PGDATABASE TO $PGUSER;"

# Check if the SQL script exists and run it
if [ -f "$PGINIT/init.sql" ]; then
    echo "Running SQL script to initialize the database..."
    psql -U $PGUSER -h $PGHOST -d $PGDATABASE -f "$PGINIT/init.sql"
else
    echo "SQL script not found, skipping initialization."
fi

# Run the command passed as CMD
exec "$@"

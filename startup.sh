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

    # Modify postgresql.conf to allow connections from any IP
    echo "listen_addresses = '*'" >> $PGDATA/postgresql.conf

    # Modify pg_hba.conf to allow md5 authentication from any IP
    echo "host all all all scram-sha-256" >> $PGDATA/pg_hba.conf
fi

# Start the PostgreSQL service
echo "Starting PostgreSQL..."
su -c "/usr/lib/postgresql/*/bin/pg_ctl start -D $PGDATA -l $PGLOGS/postgresql.log" postgres

# Ensure the password is correct for the user, either create or alter the user
psql -U postgres -h $PGHOST -d postgres -c "SELECT 1 FROM pg_roles WHERE rolname = '$PGUSER'" | grep -q 1
if [ $? -eq 0 ]; then
    # If the user exists, alter the password
    echo "User $PGUSER exists. Updating password..."
    psql -U postgres -h $PGHOST -d postgres -c "ALTER USER $PGUSER WITH PASSWORD '$PGPASSWORD';"
else
    # If the user does not exist, create the user with the specified password
    echo "User $PGUSER does not exist. Creating user..."
    psql -U postgres -h $PGHOST -d postgres -c "CREATE USER $PGUSER WITH PASSWORD '$PGPASSWORD';"
fi

# Check if the database exists
DB_EXISTS=$(psql -U postgres -h $PGHOST -d postgres -t -c "SELECT 1 FROM pg_database WHERE datname = '$PGDATABASE'")

DB_EXISTS="${DB_EXISTS#"${DB_EXISTS%%[![:space:]]*}"}"  # Remove leading whitespace
DB_EXISTS="${DB_EXISTS%"${DB_EXISTS##[![:space:]]*}"}"  # Remove trailing whitespace

# If the database does not exist, create it and run the init.sql script
if [ "$DB_EXISTS" != "1" ]; then
    echo "Database $PGDATABASE does not exist. Creating database..."
    psql -U postgres -h $PGHOST -d postgres -c "CREATE DATABASE $PGDATABASE;"

    # Check if init.sql script exists and run it
    if [ -f "$PGINIT/init.sql" ]; then
        echo "Running SQL script to initialize the database..."
        psql -U postgres -h $PGHOST -d $PGDATABASE -f "$PGINIT/init.sql"
    else
        echo "SQL script not found, skipping initialization."
    fi
else
    echo "Database $PGDATABASE already exists. Skipping creation and initialization."
fi

# Grant privileges to the user on the database
psql -U postgres -h $PGHOST -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE $PGDATABASE TO $PGUSER;"

# Run the command passed as CMD
exec "$@"

#!/bin/sh
set -e

echo "Waiting for Garage server to start..."
sleep 5

# ─── NODE ID ───────────────────────────────────────────────────────────────────
echo "Getting node ID..."
NODE_ID=$(garage -c /etc/garage.toml status | grep -v "^=" | grep -v "^ID" | awk 'NR==1 {print $1}')
echo "Node ID: $NODE_ID"

if [ -z "$NODE_ID" ]; then
    echo "ERROR: Could not get node ID"
    exit 1
fi

# ─── LAYOUT ────────────────────────────────────────────────────────────────────
echo "Checking layout..."
LAYOUT_CONFIGURED=$(garage -c /etc/garage.toml layout show 2>&1 | grep "^Current cluster layout version" | awk '{print $5}')

if [ -z "$LAYOUT_CONFIGURED" ] || [ "$LAYOUT_CONFIGURED" = "0" ]; then
    echo "Configuring layout..."
    garage -c /etc/garage.toml layout assign -z local -c 10G $NODE_ID
    garage -c /etc/garage.toml layout apply --version 1
else
    echo "Layout already configured (version: $LAYOUT_CONFIGURED), skipping..."
fi

# ─── KEY ───────────────────────────────────────────────────────────────────────
echo "Checking key..."
KEY_EXISTS=$(garage -c /etc/garage.toml key list | grep "app-key" || true)

if [ -z "$KEY_EXISTS" ]; then
    echo "Creating key..."
    KEY_CREATE_OUTPUT=$(garage -c /etc/garage.toml key create app-key 2>&1)
    ACCESS_KEY=$(echo "$KEY_CREATE_OUTPUT" | grep "Key ID:" | awk '{print $3}')
    SECRET_KEY=$(echo "$KEY_CREATE_OUTPUT" | grep "Secret key:" | awk '{print $3}')
    echo "Key created! Access Key: $ACCESS_KEY"
else
    echo "Key already exists, reading from credential file..."
    if [ -f /env/.env.garage.credential ]; then
        ACCESS_KEY=$(grep "GARAGE_ACCESS_KEY_ID" /env/.env.garage.credential | cut -d'=' -f2)
        SECRET_KEY=$(grep "GARAGE_SECRET_ACCESS_KEY" /env/.env.garage.credential | cut -d'=' -f2)
        echo "Credentials loaded from file."
    else
        echo "ERROR: Key exists but credential file not found."
        echo "To reset: docker exec s3_storage garage -c /etc/garage.toml key delete app-key"
        exit 1
    fi
fi

# ─── KEY PERMISSIONS ───────────────────────────────────────────────────────────
garage -c /etc/garage.toml key allow --create-bucket app-key || true

# ─── BUCKET ────────────────────────────────────────────────────────────────────
echo "Checking bucket..."
BUCKET_EXISTS=$(garage -c /etc/garage.toml bucket list | grep "public" || true)

if [ -z "$BUCKET_EXISTS" ]; then
    echo "Creating bucket..."
    garage -c /etc/garage.toml bucket create public
else
    echo "Bucket 'public' already exists, skipping..."
fi

BUCKET_EXISTS=$(garage -c /etc/garage.toml bucket list | grep "auth" || true)

if [ -z "$BUCKET_EXISTS" ]; then
    echo "Creating bucket..."
    garage -c /etc/garage.toml bucket create auth
else
    echo "Bucket 'auth' already exists, skipping..."
fi

BUCKET_EXISTS=$(garage -c /etc/garage.toml bucket list | grep "course" || true)

if [ -z "$BUCKET_EXISTS" ]; then
    echo "Creating bucket..."
    garage -c /etc/garage.toml bucket create course
else
    echo "Bucket 'course' already exists, skipping..."
fi

# ─── BUCKET PERMISSIONS ────────────────────────────────────────────────────────
echo "Setting bucket permissions..."
KEY_ID=$(garage -c /etc/garage.toml key list | grep app-key | awk '{print $1}')
garage -c /etc/garage.toml bucket allow --read --write --owner public --key $KEY_ID
garage -c /etc/garage.toml bucket allow --read --write --owner auth --key $KEY_ID
garage -c /etc/garage.toml bucket allow --read --write --owner course --key $KEY_ID
garage -c /etc/garage.toml bucket website --allow public

# ─── CREDENTIALS FILE ──────────────────────────────────────────────────────────
echo "Saving credentials to /env/.env.garage.credential..."
cat > /env/.env.garage.credential << EOF
# Garage S3 Credentials - Auto-generated
GARAGE_ACCESS_KEY_ID=${ACCESS_KEY}
GARAGE_SECRET_ACCESS_KEY=${SECRET_KEY}
GARAGE_ENDPOINT_URL=http://garage:3900
GARAGE_CDN_HOST=public.cdn.eduscrum.local
GARAGE_CDN_PORT=3902
GARAGE_S3_HOST=s3.eduscrum.local
GARAGE_S3_PORT=3900
GARAGE_REGION=eduscrum
GARAGE_BUCKET_PUBLIC=public
GARAGE_BUCKET_AUTH=auth
GARAGE_BUCKET_COURSE=course
EOF

echo "Setup complete!"
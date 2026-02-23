set -e

echo "Waiting for Garage server to start..."
sleep 5

echo "Getting node ID..."
NODE_ID=$(garage -c /etc/garage.toml status | grep -v "^=" | grep -v "^ID" | grep "NO ROLE ASSIGNED" | awk '{print $1}')
echo "Node ID: $NODE_ID"

echo "Configuring layout..."
garage -c /etc/garage.toml layout assign -z local -c 10G $NODE_ID
garage -c /etc/garage.toml layout apply --version 1 || true

echo "Creating key and capturing credentials..."
KEY_CREATE_OUTPUT=$(garage -c /etc/garage.toml key create app-key 2>&1 || echo "Key may already exist")

if echo "$KEY_CREATE_OUTPUT" | grep -q "Secret key:"; then
    ACCESS_KEY=$(echo "$KEY_CREATE_OUTPUT" | grep "Key ID:" | awk '{print $3}')
    SECRET_KEY=$(echo "$KEY_CREATE_OUTPUT" | grep "Secret key:" | awk '{print $3}')
    echo "New key created!"
else
    echo "WARNING: Key 'app-key' already exists. Cannot retrieve secret key."
    echo "If you need the secret key, delete the key and re-run initialization."
    echo "To delete: docker exec s3_storage garage -c /etc/garage.toml key delete app-key"
    exit 1
fi

echo "Access Key: $ACCESS_KEY"
echo "Secret Key: $SECRET_KEY"

echo "Allowing bucket creation permission..."
garage -c /etc/garage.toml key allow --create-bucket app-key || true

echo "Getting key ID..."
KEY_ID=$(garage -c /etc/garage.toml key list | grep app-key | awk '{print $1}')
echo "Key ID: $KEY_ID"

echo "Creating buckets..."
garage -c /etc/garage.toml bucket create auth || true

echo "Setting bucket permissions..."
garage -c /etc/garage.toml bucket allow --read --write auth --key $KEY_ID

echo "Setup complete!"

echo "Saving credentials to ./env/.env.garage.credential..."
cat > /env/.env.garage.credential << EOF
# Garage S3 Credentials - Auto-generated
GARAGE_ACCESS_KEY_ID=${ACCESS_KEY}
GARAGE_SECRET_ACCESS_KEY=${SECRET_KEY}
GARAGE_ENDPOINT_URL=http://garage:3900
GARAGE_ENDPOINT_PUBLIC_URL=http://s3.eduscrum.local:3900
GARAGE_REGION=eduscrum
GARAGE_BUCKET_AUTH=auth
EOF

echo "Credentials saved to ./env/.env.garage.credential"

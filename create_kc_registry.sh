# Create docker network
docker network create kc_reg_net

# Create PostgreSQL database
docker run -d --network kc_reg_net --name postgres \
  -e POSTGRES_USER=$(cat config.json | jq -r .dbUsername) \
  -e POSTGRES_PASSWORD=$(cat config.json | jq -r .dbPassword) \
  -e POSTGRES_DB=keycloak \
  -p 5432:5432 \
  postgres:latest

# Generate certfile and keyfile for https keycloak
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr
openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt

docker run -d --network kc_reg_net --name keycloak \
  -e KC_BOOTSTRAP_ADMIN_USERNAME=$(cat config.json | jq -r .kcAdminUsername) \
  -e KC_BOOTSTRAP_ADMIN_PASSWORD=$(cat config.json | jq -r .kcAdminPassword) \
  -e KC_DB=postgres \
  -e KC_DB_URL_HOST=host.docker.internal \
  -e KC_DB_URL_PORT=5432 \
  -e KC_DB_USERNAME=$(cat config.json | jq -r .dbUsername) \
  -e KC_DB_PASSWORD=$(cat config.json | jq -r .dbPassword) \
  -e KC_FEATURES="docker,token-exchange" \
  -e KC_HTTPS_CERTIFICATE_FILE="/etc/x509/https/tls.crt" \
  -e KC_HTTPS_CERTIFICATE_KEY_FILE="/etc/x509/https/tls.key" \
  -e KC_HOSTNAME_STRICT=false \
  -p 8080:8443 \
  -v "$(pwd)/server.crt:/etc/x509/https/tls.crt" \
  -v "$(pwd)/server.key:/etc/x509/https/tls.key" \
  quay.io/keycloak/keycloak:26.0.5 start

# Remove public key if exists
rm -rf public_key.crt

# Wait until keycloak endpoint accessible
while ! curl -s -k https://localhost:8080/realms/master/protocol/openid-connect/certs > /dev/null; do
  echo "Waiting for endpoint to be accessible..."
  sleep 5
done
echo "Endpoint is now accessible!"

# Save Public Certificate
echo "-----BEGIN CERTIFICATE-----\n\
$(curl -k https://localhost:8080/realms/master/protocol/openid-connect/certs | jq -r '.keys[] | select(.alg == "RS256") | .x5c[0]')\n-----END CERTIFICATE-----" > public_key.crt

# Change permissions on cert
chmod 400 public_key.crt

# Start Registry
docker run -d --network kc_reg_net --name registry \
  -v `pwd`/config.yml:/etc/docker/registry/config.yml \
  -v `pwd`/public_key.crt:/var/lib/registry/public_key.crt \
  -p 5000:5000 \
  registry:2
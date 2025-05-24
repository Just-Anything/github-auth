#!/usr/bin/env bash

set -o pipefail

client_id=$1          # Client ID as first argument
private_key_file=$2   # file path of the private key as second argument
installation_id=$3    # GitHub App installation ID as third argument
repo=$4               # Repository name as fourth argument (optional)

# Validate inputs
if [[ -z "$client_id" || -z "$private_key_file" || -z "$installation_id" ]]; then
  echo "Usage: $0 <client_id> <private_key_file> <installation_id>"
  exit 1
fi

# Check if private key file exists and is readable
if [[ ! -r "$private_key_file" ]]; then
  echo "Error: Private key file '$private_key_file' not found or not readable"
  exit 1
fi

# Verify private key
openssl rsa -in "$private_key_file" -check >/dev/null 2>&1 || {
  echo "Error: Invalid RSA private key"
  exit 1
}

now=$(date +%s)
iat=$((${now} - 60)) # Issues 60 seconds in the past
exp=$((${now} + 600)) # Expires 10 minutes in the future

b64enc() { openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }

header_json='{
    "typ":"JWT",
    "alg":"RS256"
}'
header=$( echo -n "${header_json}" | b64enc ) || {
  echo "Error encoding header"
  exit 1
}

payload_json="{
    \"iss\":\"${client_id}\",
    \"iat\":${iat},
    \"exp\":${exp}
}"
payload=$( echo -n "${payload_json}" | b64enc ) || {
  echo "Error encoding payload"
  exit 1
}

header_payload="${header}.${payload}"
signature=$(
    echo -n "${header_payload}" | openssl dgst -sha256 -sign "${private_key_file}" | b64enc
) || {
    echo "Error generating signature"
    exit 1
}

JWT="${header_payload}.${signature}"

echo "Generated JWT:"
echo "$JWT"
echo

# Call GitHub API to get installation info using JWT
get_response=$(curl -s -X GET \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $JWT" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/app)

echo "GitHub API GET response:"
echo "$get_response"

# Using an installation access token to authenticate as an app installation
post_response=$(curl --request POST \
--url "https://api.github.com/app/installations/$installation_id/access_tokens" \
--header "Accept: application/vnd.github+json" \
--header "Authorization: Bearer $JWT" \
--header "X-GitHub-Api-Version: 2022-11-28")

echo "GitHub API POST response:"
echo "$post_response"

# Build git org URL
# JQ needed to be installed
owner=$(echo "$get_response" | jq -r '.owner.login')
access_token=$(echo "$post_response" | jq -r '.token')
git_url="https://x-access-token:$access_token@github.com/$owner/$repo.git"
echo "Access token: $access_token"
echo "======================================================================================="
echo "Run the following command if error is: No such remote 'origin'"
echo "git remote -v"
echo "git remote add origin $git_url"
echo "git push origin main --force (optional)"
echo "======================================================================================="
echo "Run the following command if error is: remote origin already exists"
echo "git remote set-url origin $git_url"
echo "Option commands for this error:"
echo "git remote remove origin"
echo "git remote add origin $git_url"
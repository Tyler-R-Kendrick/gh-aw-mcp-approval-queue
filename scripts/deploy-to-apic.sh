#!/usr/bin/env bash
# deploy-to-apic.sh – Register an approved MCP server in Azure API Center.
#
# Usage:
#   deploy-to-apic.sh \
#     --server-name    <name>          \
#     --server-url     <https://...>   \
#     --description    <text>          \
#     --subscription   <azure-sub-id>  \
#     --resource-group <rg-name>       \
#     --apic-service   <apic-name>

set -euo pipefail

SERVER_NAME=""
SERVER_URL=""
DESCRIPTION=""
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-}"
APIC_SERVICE="${AZURE_APIC_SERVICE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-name)    SERVER_NAME="$2";    shift 2 ;;
    --server-url)     SERVER_URL="$2";     shift 2 ;;
    --description)    DESCRIPTION="$2";   shift 2 ;;
    --subscription)   SUBSCRIPTION_ID="$2"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --apic-service)   APIC_SERVICE="$2";   shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ─── validation ───────────────────────────────────────────────────────────────
for var in SERVER_NAME SERVER_URL SUBSCRIPTION_ID RESOURCE_GROUP APIC_SERVICE; do
  [[ -z "${!var}" ]] && { echo "❌ Required: --${var//_/-}" >&2; exit 1; }
done

info()  { echo "ℹ  $*"; }
ok()    { echo "✅ $*"; }
die()   { echo "❌ $*" >&2; exit 1; }

# ─── auth ─────────────────────────────────────────────────────────────────────
ensure_az_login() {
  if ! az account show &>/dev/null; then
    info "Logging in to Azure …"
    if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" && -n "${AZURE_TENANT_ID:-}" ]]; then
      az login --service-principal \
        --username "$AZURE_CLIENT_ID" \
        --password "$AZURE_CLIENT_SECRET" \
        --tenant   "$AZURE_TENANT_ID" \
        --output none
    else
      az login --output none
    fi
  fi
  az account set --subscription "$SUBSCRIPTION_ID"
  ok "Authenticated to Azure subscription: $SUBSCRIPTION_ID"
}

# ─── register API in APIC ─────────────────────────────────────────────────────
register_mcp_in_apic() {
  local api_id
  api_id=$(echo "$SERVER_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')

  info "Registering MCP server '$SERVER_NAME' in Azure API Center …"

  # Create or update the API entry — probe first to distinguish "already exists"
  # from genuine failures (auth, throttling, invalid params, etc.).
  if az apic api show \
       --resource-group "$RESOURCE_GROUP" \
       --service-name   "$APIC_SERVICE" \
       --api-id         "$api_id" \
       --subscription   "$SUBSCRIPTION_ID" \
       --output none &>/dev/null; then
    info "API '$api_id' already exists — updating …"
    az apic api update \
      --resource-group "$RESOURCE_GROUP" \
      --service-name   "$APIC_SERVICE" \
      --api-id         "$api_id" \
      --title          "$SERVER_NAME" \
      --description    "${DESCRIPTION:-MCP server registered via automated approval pipeline}" \
      --subscription   "$SUBSCRIPTION_ID" \
      --output none
  else
    info "Creating API '$api_id' …"
    az apic api create \
      --resource-group "$RESOURCE_GROUP" \
      --service-name   "$APIC_SERVICE" \
      --api-id         "$api_id" \
      --title          "$SERVER_NAME" \
      --type           "REST" \
      --description    "${DESCRIPTION:-MCP server registered via automated approval pipeline}" \
      --subscription   "$SUBSCRIPTION_ID" \
      --output none
  fi

  # Register the deployment (runtime URL)
  local env_name="production"
  az apic environment create \
    --resource-group   "$RESOURCE_GROUP" \
    --service-name     "$APIC_SERVICE" \
    --environment-id   "$env_name" \
    --title            "Production" \
    --type             "production" \
    --subscription     "$SUBSCRIPTION_ID" \
    --output none 2>/dev/null \
    || true

  az apic api deployment create \
    --resource-group   "$RESOURCE_GROUP" \
    --service-name     "$APIC_SERVICE" \
    --api-id           "$api_id" \
    --deployment-id    "v1" \
    --title            "v1" \
    --server           "{\"runtimeUri\":[\"$SERVER_URL\"]}" \
    --environment-id   "/workspaces/default/environments/$env_name" \
    --subscription     "$SUBSCRIPTION_ID" \
    --output none 2>/dev/null \
    || info "Deployment already exists – skipping."

  ok "MCP server registered in Azure API Center."
  echo "$api_id"
}

# ─── output summary ───────────────────────────────────────────────────────────
print_summary() {
  local api_id="$1"
  echo ""
  echo "========================================"
  echo "  Azure API Center Registration Summary"
  echo "========================================"
  echo "  Server Name   : $SERVER_NAME"
  echo "  Runtime URL   : $SERVER_URL"
  echo "  APIC Service  : $APIC_SERVICE"
  echo "  API ID        : $api_id"
  echo "  Resource Group: $RESOURCE_GROUP"
  echo "  Subscription  : $SUBSCRIPTION_ID"
  echo "========================================"
}

# ─── main ─────────────────────────────────────────────────────────────────────
main() {
  ensure_az_login
  local api_id
  api_id=$(register_mcp_in_apic)
  print_summary "$api_id"
}

main "$@"

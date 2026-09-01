#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

if [[ $# -gt 1 && "${1:-}" != "restart" ]] || [[ $# -eq 1 && ! "${1:-}" =~ ^(check|restart|--pull)$ ]]; then
	echo "Usage: $0 [--pull]" >&2
	echo "       $0 check" >&2
	echo "       $0 restart [service ...]" >&2
	exit 1
fi

command -v docker >/dev/null 2>&1 || {
	echo "docker is required" >&2
	exit 1
}
docker compose version >/dev/null 2>&1 || {
	echo "docker compose is required" >&2
	exit 1
}
command -v git >/dev/null 2>&1 || {
	echo "git is required" >&2
	exit 1
}
[[ -f .env.production ]] || {
	echo ".env.production is required" >&2
	exit 1
}

PLAUSIBLE_TAG="$(git tag --sort=-version:refname --list 'v[0-9]*' | head -n1)"
[[ -n "${PLAUSIBLE_TAG}" ]] || {
	echo "no version tag found in repository" >&2
	exit 1
}

PLAUSIBLE_VERSION="${PLAUSIBLE_TAG#v}"
PLAUSIBLE_REVISION="$(git rev-parse HEAD)"
BUILD_METADATA=$(printf '{"labels":{"org.opencontainers.image.version":"%s","org.opencontainers.image.revision":"%s","org.opencontainers.image.created":"%s"}}' \
	"${PLAUSIBLE_VERSION}" \
	"${PLAUSIBLE_REVISION}" \
	"$(date -u +%Y-%m-%dT%H:%M:%SZ)")
export PLAUSIBLE_VERSION PLAUSIBLE_REVISION BUILD_METADATA

# Restart all services or the named services without building or pulling images.
if [[ "${1:-}" == "restart" ]]; then
	shift
	echo "==> Restarting version ${PLAUSIBLE_VERSION}${*:+: $*}"
	docker compose --env-file .env.production restart "$@"
	echo "==> Done."
	exit 0
fi

echo "==> Version:  ${PLAUSIBLE_VERSION}"
echo "==> Revision: ${PLAUSIBLE_REVISION}"

echo "==> Check compose configuration"
echo "==> Images:"
docker compose --env-file .env.production config --images

if [[ "${1:-}" == "check" ]]; then
	echo "==> Check passed."
	exit 0
fi

echo "==> Build and deploy on local host"
[[ -s priv/geodb/dbip-country.mmdb.gz ]] || {
	echo "priv/geodb/dbip-country.mmdb.gz is required; restore the existing database before building" >&2
	exit 1
}
gzip -t priv/geodb/dbip-country.mmdb.gz
if [[ "${1:-}" == "--pull" ]]; then
	docker compose --env-file .env.production build --pull
	docker compose --env-file .env.production pull --policy always --ignore-buildable
else
	docker compose --env-file .env.production build
fi
docker compose --env-file .env.production up -d --remove-orphans

echo "==> Done. Released ${PLAUSIBLE_VERSION} (${PLAUSIBLE_REVISION}) on the local host."

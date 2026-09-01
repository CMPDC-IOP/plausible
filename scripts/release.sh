#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

if [[ $# -gt 1 && "${1:-}" != "restart" || $# -eq 1 && ! "${1:-}" =~ ^(check|restart|--pull)$ ]]; then
	echo "usage: $0 [--pull] [check | restart [service ...]]" >&2
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

if [[ "${1:-}" == "check" ]]; then
	echo "==> Check script syntax"
	bash -n "${BASH_SOURCE[0]}"

	echo "==> Check compose configuration"
	# PLAUSIBLE_VERSION is intentionally required by compose.yml; any value
	# satisfies interpolation for a config-only check.
	PLAUSIBLE_VERSION=check BUILD_METADATA='' docker compose --env-file .env.production config --quiet

	echo "==> Check passed."
	exit 0
fi

PLAUSIBLE_TAG="$(git tag --sort=-version:refname --list 'v[0-9]*' | sed -n '1p')"
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

PULL_IMAGES=0
if [[ "${1:-}" == "--pull" ]]; then
	PULL_IMAGES=1
	shift
fi

# Restart-only mode: ./scripts/release.sh restart [service ...]
# No build, no pull; restarts all services or the ones named.
if [[ "${1:-}" == "restart" ]]; then
	shift
	echo "==> Restarting version ${PLAUSIBLE_VERSION}${*:+: $*}"
	docker compose --env-file .env.production restart "$@"
	echo "==> Done."
	exit 0
fi

PLAUSIBLE_IMAGE="plausible:${PLAUSIBLE_VERSION}"

echo "==> Version:  ${PLAUSIBLE_VERSION}"
echo "==> Revision: ${PLAUSIBLE_REVISION}"
echo "==> Build image: ${PLAUSIBLE_IMAGE}"

echo "==> Build and deploy on local host"
[[ -s priv/geodb/dbip-country.mmdb.gz ]] || {
	echo "priv/geodb/dbip-country.mmdb.gz is required; restore the existing database before building" >&2
	exit 1
}
gzip -t priv/geodb/dbip-country.mmdb.gz
if ((PULL_IMAGES)); then
	docker compose --env-file .env.production build --pull
	docker compose --env-file .env.production pull --policy always --ignore-buildable
else
	docker compose --env-file .env.production build
fi
docker compose --env-file .env.production up -d --remove-orphans

echo "==> Done. Released ${PLAUSIBLE_VERSION} (${PLAUSIBLE_REVISION}) on the local host."

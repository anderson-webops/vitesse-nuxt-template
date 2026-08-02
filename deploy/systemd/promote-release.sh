#!/usr/bin/env bash
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

release_root="${RELEASE_ROOT:-/srv/vitesse-nuxt-template/releases}"
current_link="${CURRENT_LINK:-/srv/vitesse-nuxt-template/current}"
service_name="${SERVICE_NAME:-vitesse-nuxt-template-api.service}"
health_url="${HEALTH_URL:-http://127.0.0.1:3006/api/health}"
public_host="${PUBLIC_HOST:-}"

if [[ $# -ne 1 ]]; then
	echo "Usage: PUBLIC_HOST=site.example promote-release.sh /srv/vitesse-nuxt-template/releases/<prepared-release>" >&2
	exit 2
fi
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
	echo "Run promotion with root privileges." >&2
	exit 1
fi
if [[ ! -x /usr/bin/node || "$(/usr/bin/node --version)" != "v24.18.1" ]]; then
	echo "/usr/bin/node must be Node 24.18.1." >&2
	exit 1
fi
if [[ -z "$public_host" || ! "$public_host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]]; then
	echo "PUBLIC_HOST must be the certificate-covered production hostname." >&2
	exit 1
fi

public_origin="${PUBLIC_ORIGIN:-https://$public_host}"
resolve_ipv4="${VITESSE_RESOLVE_IPV4:-$public_host:443:127.0.0.1}"
resolve_ipv6="${VITESSE_RESOLVE_IPV6:-$public_host:443:[::1]}"
release_root_real="$(cd -- "$release_root" && pwd -P)"
candidate="$(cd -- "$1" && pwd -P)"
case "$candidate/" in
	"$release_root_real/"*) ;;
	*) echo "Candidate must resolve beneath $release_root_real: $candidate" >&2; exit 1 ;;
esac
if [[ "$candidate" == "$release_root_real" ]]; then
	echo "Candidate must be a prepared release beneath, not equal to, $release_root_real." >&2
	exit 1
fi

for required_path in \
	.vitesse-release-prepared.json \
	back-end/dist/server.js \
	back-end/node_modules/express/package.json \
	front-end/.output/public/index.html \
	front-end/.output/public/release.json; do
	if [[ ! -e "$candidate/$required_path" ]]; then
		echo "Prepared release is missing $required_path." >&2
		exit 1
	fi
done
if [[ -e "$current_link" && ! -L "$current_link" ]]; then
	echo "Refusing to replace non-symlink deployment path: $current_link" >&2
	exit 1
fi
if ! nginx -t; then
	echo "Nginx configuration must pass before promotion." >&2
	exit 1
fi

previous_target=""
if [[ -L "$current_link" ]]; then
	previous_target="$(readlink -f -- "$current_link" 2>/dev/null || true)"
	if [[ -z "$previous_target" ]]; then
		echo "Existing deployment symlink does not resolve: $current_link" >&2
		exit 1
	fi
	case "$previous_target/" in
		"$release_root_real/"*) ;;
		*) echo "Existing deployment target is outside $release_root_real: $previous_target" >&2; exit 1 ;;
	esac
	if [[ ! -f "$previous_target/.vitesse-release-prepared.json" ]]; then
		echo "Existing direct release is missing its rollback identity." >&2
		exit 1
	fi
fi

next_link="${current_link}.next.$$"
response_health="$(mktemp)"
response_release="$(mktemp)"
headers_ipv4="$(mktemp)"
headers_ipv6="$(mktemp)"
cleanup() {
	if [[ -L "$next_link" ]]; then unlink -- "$next_link"; fi
	rm -f -- "$response_health" "$response_release" "$headers_ipv4" "$headers_ipv6"
}
trap cleanup EXIT

activate_target() {
	local target="$1"
	ln -s -- "$target" "$next_link"
	mv -Tf -- "$next_link" "$current_link"
}

identity_matches() {
	local expected="$1"
	local actual="$2"
	/usr/bin/node -e '
const fs = require("node:fs")
const expected = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
const actual = JSON.parse(fs.readFileSync(process.argv[2], "utf8"))
if (expected.release !== actual.release || expected.commitSha !== actual.commitSha || expected.deployedAt !== actual.deployedAt) process.exit(1)
' "$expected" "$actual"
}

health_is_minimal() {
	local actual="$1"
	/usr/bin/node -e '
const fs = require("node:fs")
const body = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
if (JSON.stringify(body) !== JSON.stringify({ ok: true })) process.exit(1)
' "$actual"
}

strict_page_headers() {
	local headers="$1"
	grep -Eiq '^Content-Security-Policy:.*frame-ancestors .none.' "$headers" \
		&& grep -Eiq '^X-Content-Type-Options:[[:space:]]*nosniff' "$headers" \
		&& grep -Eiq '^X-Frame-Options:[[:space:]]*DENY' "$headers"
}

edge_status() {
	local family="$1"
	local resolve="$2"
	local url="$3"
	shift 3
	curl --noproxy '*' "$family" --silent --show-error --max-time 5 --resolve "$resolve" \
		--output /dev/null --write-out '%{http_code}' "$@" "$url"
}

wait_for_target() {
	local target="$1"
	local marker="$target/.vitesse-release-prepared.json"
	local attempt
	for attempt in {1..40}; do
		if curl --noproxy '*' --fail --silent --show-error --max-time 5 "$health_url" --output "$response_health" \
			&& health_is_minimal "$response_health" \
			&& curl --noproxy '*' --ipv4 --fail --silent --show-error --max-time 5 --resolve "$resolve_ipv4" \
				"$public_origin/release.json" --output "$response_release" \
			&& identity_matches "$marker" "$response_release" \
			&& curl --noproxy '*' --ipv6 --fail --silent --show-error --max-time 5 --resolve "$resolve_ipv6" \
				"$public_origin/release.json" --output "$response_release" \
			&& identity_matches "$marker" "$response_release" \
			&& curl --noproxy '*' --ipv4 --fail --silent --show-error --max-time 5 --resolve "$resolve_ipv4" \
				--dump-header "$headers_ipv4" "$public_origin/" --output /dev/null \
			&& curl --noproxy '*' --ipv6 --fail --silent --show-error --max-time 5 --resolve "$resolve_ipv6" \
				--dump-header "$headers_ipv6" "$public_origin/" --output /dev/null \
			&& strict_page_headers "$headers_ipv4" \
			&& strict_page_headers "$headers_ipv6" \
			&& [[ "$(edge_status --ipv4 "$resolve_ipv4" "$public_origin/api/health" -X POST -H 'Content-Type: application/json' --data '{}')" == "405" ]] \
			&& [[ "$(edge_status --ipv6 "$resolve_ipv6" "$public_origin/api/health" -X POST -H 'Content-Type: application/json' --data '{}')" == "405" ]] \
			&& [[ "$(edge_status --ipv4 "$resolve_ipv4" "$public_origin/api/admin")" == "404" ]] \
			&& [[ "$(edge_status --ipv6 "$resolve_ipv6" "$public_origin/api/admin")" == "404" ]]; then
			return 0
		fi
		sleep 1
	done
	return 1
}

activate_target "$candidate"
if systemctl restart "$service_name" \
	&& nginx -t \
	&& systemctl reload nginx \
	&& wait_for_target "$candidate"; then
	echo "Promoted $candidate and verified exact identity and read-only policy over local IPv4 and IPv6 TLS."
	exit 0
fi

echo "Candidate health, identity, or edge policy failed; restoring the previous direct release." >&2
if [[ -n "$previous_target" ]]; then
	activate_target "$previous_target"
	systemctl restart "$service_name"
	nginx -t && systemctl reload nginx
	if ! wait_for_target "$previous_target"; then
		echo "The previous release was restored but did not pass health, identity, and edge checks." >&2
	fi
else
	unlink -- "$current_link"
	systemctl stop "$service_name" || true
	nginx -t && systemctl reload nginx
fi
exit 1

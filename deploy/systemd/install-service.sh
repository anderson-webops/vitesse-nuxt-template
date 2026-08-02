#!/usr/bin/env bash
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
	echo "Run install-service.sh with root privileges." >&2
	exit 1
fi
if [[ ! -x /usr/bin/node || "$(/usr/bin/node --version)" != "v24.18.1" ]]; then
	echo "/usr/bin/node must be Node 24.18.1." >&2
	exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

if ! getent group vitesse-template >/dev/null; then
	groupadd --system vitesse-template
fi
if ! id vitesse-template >/dev/null 2>&1; then
	useradd --system --gid vitesse-template --home-dir /srv/vitesse-nuxt-template --shell /usr/sbin/nologin vitesse-template
fi

install -d -o vitesse-template -g vitesse-template -m 0750 /srv/vitesse-nuxt-template
install -d -o vitesse-template -g vitesse-template -m 0750 /srv/vitesse-nuxt-template/releases
install -d -o vitesse-template -g vitesse-template -m 0750 /srv/vitesse-nuxt-template/shared
install -d -o vitesse-template -g vitesse-template -m 0700 /srv/vitesse-nuxt-template/shared/npm-cache
install -o root -g root -m 0644 "$script_dir/vitesse-nuxt-template-api.service" /etc/systemd/system/vitesse-nuxt-template-api.service

systemctl daemon-reload
systemctl enable vitesse-nuxt-template-api.service

echo "Installed the Docker-free Vitesse template API service without starting it. Install the Nginx server snippet and promote a prepared release."

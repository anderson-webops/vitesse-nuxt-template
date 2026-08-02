# Docker-free production rollout

The default self-hosted topology is static Nuxt output served by the host Nginx process plus one loopback-only Express
process managed by systemd. Netlify remains a separate supported Docker-free adapter. There is no production Docker,
Compose, Podman, or container-registry dependency.

## First direct rollout

1. Install Node `24.18.1` at `/usr/bin/node`. Run `sudo deploy/systemd/install-service.sh`; this creates the
   unprivileged `vitesse-template` account and release directories but does not start the service.
2. Copy the contents of `deploy/nginx/vitesse-nuxt-template.server.conf` into the existing certificate-covered TLS
   server block. Retain its IPv4 and IPv6 listeners, test the complete Nginx configuration, and reload it only after a
   release is prepared.
3. Check out the annotated release tag beneath `/srv/vitesse-nuxt-template/releases` as `vitesse-template`, then run:

   ```bash
   NPM_CONFIG_CACHE=/srv/vitesse-nuxt-template/shared/npm-cache \
   deploy/systemd/prepare-release.sh /srv/vitesse-nuxt-template/releases/<release>
   ```

   Preparation rejects source-local environment files and requires a clean checkout at the exact fetched
   `origin/main` and annotated version tag. It validates the full and production dependency graphs, package signatures,
   Linux ARM64 bindings, source, API behavior, generated output, accessibility, and the real minimal direct runtime.
4. Promote as root with the certificate-covered hostname:

   ```bash
   sudo PUBLIC_HOST=site.example \
   deploy/systemd/promote-release.sh /srv/vitesse-nuxt-template/releases/<release>
   ```

   Promotion atomically selects the candidate, restarts the API, reloads Nginx, and verifies API health, exact release
   identity, strict headers, mutation denial, and reserved API denial through both local IPv4 and IPv6 TLS paths. Any
   failure restores the previous prepared release automatically.

This workflow does not modify DNS, certificates, routing, or firewall policy. Preserve every existing A and AAAA record
and both address families. A or AAAA records are not troubleshooting controls; repair the host listener, certificate,
route, or firewall separately if one family fails.

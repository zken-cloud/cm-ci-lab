# Serves the single-page CodeMender CI Lab guide behind the HTTPS LB + IAP.
# Static content only — nginx listens on 8080 (Cloud Run's default port).
FROM nginx:1.27-alpine
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY gate.html /usr/share/nginx/html/gate.html
# webapp/index.html (Cloud Build guide) is intentionally NOT copied — the Cloud
# Build variant is hidden for the shared-project preview. Kept in the repo for revival.
COPY gha/index.html /usr/share/nginx/html/gha/index.html
# webapp/gha-setup/index.html intentionally NOT copied — the WIF setup page is
# pulled from the live site pending review. Kept in the repo for revival.
COPY eap/index.html /usr/share/nginx/html/eap/index.html
COPY smoke/index.html /usr/share/nginx/html/smoke/index.html
# webapp/skills/index.html intentionally NOT copied — Skills page hidden for now
# (AGY harness refused the scan). Kept in the repo for revival.

# The token gate value is NOT in the repo: it is read from the SITE_TOKEN env var
# at container start (envsubst renders the template), and the container refuses
# to start without it. Set it on the Cloud Run service (see README).
CMD ["/bin/sh", "-c", ": \"${SITE_TOKEN:?set SITE_TOKEN}\" && envsubst '${SITE_TOKEN}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf && exec nginx -g 'daemon off;'"]

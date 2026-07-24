# Serves the single-page CodeMender CI Lab guide behind the HTTPS LB + IAP.
# Static content only — nginx listens on 8080 (Cloud Run's default port).
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
# webapp/index.html (Cloud Build guide) is intentionally NOT copied — the Cloud
# Build variant is hidden for the shared-project preview. Kept in the repo for revival.
COPY gha/index.html /usr/share/nginx/html/gha/index.html
COPY eap/index.html /usr/share/nginx/html/eap/index.html
COPY smoke/index.html /usr/share/nginx/html/smoke/index.html
COPY skills/index.html /usr/share/nginx/html/skills/index.html

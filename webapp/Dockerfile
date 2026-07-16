# Serves the single-page CodeMender CI Lab guide behind the HTTPS LB + IAP.
# Static content only — nginx listens on 8080 (Cloud Run's default port).
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
COPY gha/index.html /usr/share/nginx/html/gha/index.html

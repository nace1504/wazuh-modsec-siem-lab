FROM owasp/modsecurity-crs:nginx-alpine

USER root

# Create log directory for ModSecurity single-line JSON logs
RUN mkdir -p /var/log/modsec && \
    chown -R nginx:nginx /var/log/modsec && \
    chmod 755 /var/log/modsec

# Copy customized configurations
COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY conf/modsec.conf /etc/nginx/modsec/modsec.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]


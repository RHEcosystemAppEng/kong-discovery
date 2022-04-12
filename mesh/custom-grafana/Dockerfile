FROM grafana/grafana:8.3.3 

RUN wget -O /tmp/kuma.zip https://github.com/kumahq/kuma-grafana-datasource/releases/download/v0.1.0/kumahq-kuma-datasource-0.1.0.zip \
          && unzip /tmp/kuma.zip -d /var/lib/grafana/plugins/ && rm /tmp/kuma.zip
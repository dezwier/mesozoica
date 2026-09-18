# Railway Flutter web for learnfromdata.ai/mesozoica/app
FROM --platform=linux/amd64 ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter pub get

ARG MAPBOX_ACCESS_TOKEN
ENV MAPBOX_ACCESS_TOKEN=${MAPBOX_ACCESS_TOKEN}

RUN flutter precache --web

RUN flutter build web --release --base-href /mesozoica/app/ \
    --dart-define=MAPBOX_ACCESS_TOKEN="${MAPBOX_ACCESS_TOKEN:-}"

FROM --platform=linux/amd64 nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html/mesozoica/app
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 80
CMD ["/start.sh"]

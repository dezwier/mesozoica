# Build from the repository root so flutter/assets/game_config
# (a symlink to backend/app/game_config) is present:
#   docker build -f flutter/Dockerfile .
FROM --platform=linux/amd64 ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /src/flutter

COPY flutter/pubspec.yaml flutter/pubspec.lock ./
RUN flutter pub get

COPY flutter /src/flutter
COPY backend/app/game_config /src/backend/app/game_config
RUN flutter pub get

ARG MAPBOX_ACCESS_TOKEN
ENV MAPBOX_ACCESS_TOKEN=${MAPBOX_ACCESS_TOKEN}

RUN flutter precache --web

RUN flutter build web --release --base-href /mesozoica/app/ \
    --dart-define=MAPBOX_ACCESS_TOKEN="${MAPBOX_ACCESS_TOKEN:-}"

FROM --platform=linux/amd64 nginx:alpine
COPY --from=build /src/flutter/build/web /usr/share/nginx/html/mesozoica/app
COPY flutter/nginx.conf /etc/nginx/conf.d/default.conf
COPY flutter/start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 80
CMD ["/start.sh"]

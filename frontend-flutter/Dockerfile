# Stage 1: Build Flutter Web Release
FROM ghcr.io/cirrusci/flutter:3.38.0 AS build

WORKDIR /app
COPY . .

RUN flutter config --enable-web
RUN flutter pub get
RUN flutter build web --release

# Stage 2: Serve Flutter Web via Nginx Web Server
FROM nginx:alpine

COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

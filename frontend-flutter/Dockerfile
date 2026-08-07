# Stage 1: Build Flutter Web Release
#
# Vercel TIDAK menyediakan Flutter SDK di environment build-nya, jadi SDK
# diunduh dari tarball resmi Flutter (storage.googleapis.com). Versi disematkan
# (pinned) agar build tidak bergeser diam-diam — pubspec meminta >=3.44.0.
#
# Base image Debian dipilih karena Flutter Linux membutuhkan git, curl, dan
# xz-utils untuk mengekstrak SDK; image `cirrusci/flutter` yang lama tidak valid.
FROM debian:bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    unzip \
    xz-utils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG FLUTTER_VERSION=3.44.9

RUN curl -fsSL -o /tmp/flutter.tar.xz \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz

ENV PATH="/opt/flutter/bin:$PATH"

# Flutter memakai git untuk membaca versi SDK. Direktori /opt/flutter dimiliki
# root sedangkan build dijalankan user lain (Vercel/buildah), dan git menolak
# bekerja pada direktori dengan kepemilikan asing ("dubious ownership").
# Daftarkan sebagai safe.directory sebelum perintah flutter pertama.
RUN git config --global --add safe.directory /opt/flutter

WORKDIR /app
COPY . .

RUN flutter config --no-analytics --enable-web
RUN flutter pub get
RUN flutter build web --release

# Stage 2: Serve Flutter Web via Nginx Web Server
#
# Vercel container mengarahkan lalu lintas ke port $PORT (bawaan 8080).
# Template nginx memakai envsubst (dijalankan otomatis oleh image nginx resmi),
# jadi nginx mendengarkan port yang diberikan Vercel, bukan port 80 baku.
FROM nginx:alpine

# Baku untuk envsubst: nginx resmi tidak memahami sintaks ${PORT:-8080},
# jadi PORT di-set eksplisit dan template memakai ${PORT} polos. Nilai dari
# Vercel (melalui PORT) akan menimpanya bila disediakan.
ENV PORT=8080

COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf.template /etc/nginx/templates/default.conf.template

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]

#!/bin/bash
set -e
if [ ! -d "../flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 ../flutter
fi
export PATH="$PATH:`pwd`/../flutter/bin"
flutter config --no-analytics --enable-web
flutter pub get
flutter build web --release

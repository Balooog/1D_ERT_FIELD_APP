.PHONY: dev test apk format analyze

dev:
flutter run

test:
flutter test

format:
dart format .

analyze:
flutter analyze

apk:
flutter build apk --release

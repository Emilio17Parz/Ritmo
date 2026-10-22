# Componentes de Ritmo 1.3.0

- youtubedl-android 0.18.1: https://github.com/yausername/youtubedl-android (GPL-3.0). Se usan los artefactos Maven Central io.github.junkfood02.youtubedl-android:library y :ffmpeg. Su código fuente y licencia están en el repositorio original.
- yt-dlp: https://github.com/yt-dlp/yt-dlp — motor de extracción ejecutado localmente; contiene sus avisos de licencia y componentes de terceros.
- FFmpeg: https://ffmpeg.org — compilación nativa suministrada por youtubedl-android. Véanse las opciones de compilación y licencias de ese proyecto.
- Python y QuickJS: entornos suministrados por youtubedl-android.
- Flutter, just_audio, path_provider, share_plus y url_launcher: conservan sus licencias y avisos originales.

Este paquete contiene fuentes de integración. Los binarios nativos se resuelven al compilar con Gradle. Al redistribuir un APK, deben conservarse los avisos y cumplirse las condiciones de distribución de estos componentes, incluida la disponibilidad del código fuente correspondiente cuando sea exigida por su licencia.

- crypto (Dart): SHA-256 para PKCE, con su licencia original.
- Spotify Web API: metadatos y autorización, https://developer.spotify.com/. No se redistribuye audio ni carátulas de Spotify.

- flutter_secure_storage 10.x: almacenamiento seguro de sesión; licencia BSD-3-Clause. https://pub.dev/packages/flutter_secure_storage

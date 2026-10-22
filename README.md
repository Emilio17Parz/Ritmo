# Ritmo

Aplicación Android desarrollada con Flutter y Dart para organizar música, crear playlists y descargar audio de YouTube con conversión a MP3 directamente en el teléfono.

## Funcionalidades

- Campo único para enlaces de YouTube y Spotify.
- Descarga de canciones y playlists de YouTube.
- Conversión a MP3 con opciones de 128, 192 y 320 kbps.
- Importación de títulos y artistas desde Spotify.
- Búsqueda de versiones en YouTube y revisión de coincidencias.
- Sesión de Spotify almacenada de forma cifrada.
- Renovación automática mientras la autorización sea válida.
- Biblioteca de descargas y playlists locales.
- Música existente en el dispositivo en una sección independiente.
- Reproducción, exportación y uso compartido de archivos.
- Mensajes de progreso simplificados y detalles técnicos consultables.

## Funcionamiento de Spotify

Spotify proporciona los metadatos de las canciones y playlists. Ritmo busca versiones en YouTube para que el usuario revise las coincidencias antes de añadirlas a la cola.

El audio no se descarga desde los servidores de Spotify.

Se admiten enlaces completos de open.spotify.com y URI de canciones o playlists. Para enlaces cortos spotify.link, abre el enlace y copia la dirección completa.

El acceso depende de los permisos y restricciones vigentes de la API de Spotify.

## Tecnologías

- Flutter y Dart para la interfaz y la lógica.
- Kotlin para la integración Android.
- yt-dlp para la extracción y descarga.
- FFmpeg para la conversión a MP3.
- Spotify Web API con autorización PKCE.
- flutter_secure_storage para conservar la sesión.

## Requisitos de desarrollo

- Flutter con soporte para Android.
- Android SDK y Java compatibles con Flutter.
- Licencias del Android SDK aceptadas.
- Dispositivo Android con depuración USB o emulador compatible.

Las descargas y la conversión se realizan en el teléfono. La computadora se utiliza para desarrollar, compilar e instalar.

## Configuración de Spotify

Utiliza una aplicación en Spotify for Developers. Selecciona Web API y registra exactamente esta Redirect URI:

    http://127.0.0.1:8888/callback

El Client ID público se configura en el archivo:

    lib/spotify_build_config.dart

El archivo debe definir:

    const spotifyBuildClientId = 'TU_CLIENT_ID';

No incluyas un Client Secret.

Cada teléfono debe autorizar su cuenta la primera vez. La sesión se conserva cifrada y se renueva automáticamente. Puede ser necesario autorizar de nuevo si se revoca el permiso, caduca la autorización, se borran los datos o se cambia el Client ID.

Un perfil de GitHub no sustituye la dirección de retorno de la aplicación.

## Ejecutar

Desde la carpeta que contiene pubspec.yaml:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\Ejecutar.ps1

## Crear APK

    powershell -NoProfile -ExecutionPolicy Bypass -File .\Crear-APK.ps1

APK para teléfonos Android ARM de 64 bits:

    build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

Los APK publicados se encuentran en la sección Releases de este repositorio.

## Uso

1. Pega un enlace en la pantalla de descargas.
2. Pulsa Continuar.
3. Si es Spotify, autoriza la cuenta cuando se solicite.
4. Revisa las coincidencias encontradas en YouTube.
5. Añade las canciones y pulsa Descargar cola.

Mantén la aplicación abierta durante la autorización y las descargas. Esta versión no implementa un servicio de descarga en segundo plano.

## Actualizaciones

Instala las actualizaciones sobre la aplicación existente para conservar los datos. Deben mantener el identificador Android y la misma firma.

Identificador de la aplicación:

    dev.nube.nube_music

## Dependencias y licencias

Consulta THIRD_PARTY.md para revisar las dependencias utilizadas.

Utiliza la aplicación con contenido que tengas autorización para descargar.
package dev.nube.nube_music

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var bridge: YtdlpBridge? = null
    private var pendingExport: MethodChannel.Result? = null
    private var exportSource: File? = null
    private var pendingScan: MethodChannel.Result? = null
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = YtdlpBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nube_music/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepAwake" -> {
                        if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    "scanAudio" -> {
                        if (pendingScan != null) {
                            result.error("BUSY", "Ya se está leyendo la música.", null)
                        } else {
                            val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
                                else Manifest.permission.READ_EXTERNAL_STORAGE
                            if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
                                scanAudio(result)
                            } else {
                                pendingScan = result
                                requestPermissions(arrayOf(permission), 7302)
                            }
                        }
                    }
                    "pickAudio" -> {
                        if (pendingPick != null) result.error("BUSY", "Cierra el selector anterior.", null)
                        else {
                            pendingPick = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "audio/*"
                                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            }
                            try { startActivityForResult(intent, 7303) }
                            catch (e: Exception) { pendingPick = null; result.error("PICK", e.message, null) }
                        }
                    }
                    "export" -> {
                        if (pendingExport != null) result.error("BUSY", "Termina la exportación anterior.", null)
                        else {
                            val file = call.argument<String>("path")?.let { File(it).canonicalFile }
                            val root = File(applicationInfo.dataDir).canonicalPath + File.separator
                            if (file == null || !file.isFile || !file.path.startsWith(root)) {
                                result.error("FILE", "No se encontró el MP3.", null)
                            } else {
                                val name = (call.argument<String>("name") ?: "audio.mp3")
                                    .replace(Regex("[\\\\/:*?\"<>|]"), "_").take(180)
                                exportSource = file; pendingExport = result
                                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "audio/mpeg"
                                    putExtra(Intent.EXTRA_TITLE, if (name.endsWith(".mp3")) name else "$name.mp3")
                                }
                                try { startActivityForResult(intent, 7301) }
                                catch (e: Exception) {
                                    pendingExport = null; exportSource = null; result.error("EXPORT", e.message, null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        bridge?.close()
        super.onDestroy()
    }

    private fun scanAudio(result: MethodChannel.Result) {
        pendingScan = result
        Thread {
            try {
                val collection = if (Build.VERSION.SDK_INT >= 29)
                    MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                    else MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                val folderColumn = if (Build.VERSION.SDK_INT >= 29) MediaStore.Audio.Media.RELATIVE_PATH
                    else MediaStore.Audio.Media.DATA
                val columns = arrayOf(MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE,
                    MediaStore.Audio.Media.DISPLAY_NAME, MediaStore.Audio.Media.ARTIST, folderColumn)
                val items = mutableListOf<Map<String, Any>>()
                contentResolver.query(collection, columns, "${MediaStore.Audio.Media.SIZE} > 0", null,
                    "${MediaStore.Audio.Media.TITLE} ASC")?.use { cursor ->
                    val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                    val titleIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                    val nameIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                    val artistIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                    val folderIndex = cursor.getColumnIndexOrThrow(folderColumn)
                    while (cursor.moveToNext()) {
                        val uri = ContentUris.withAppendedId(collection, cursor.getLong(idIndex)).toString()
                        val title = cursor.getString(titleIndex)?.takeIf { it.isNotBlank() }
                            ?: cursor.getString(nameIndex) ?: "Audio"
                        val artist = cursor.getString(artistIndex)?.takeIf { it.isNotBlank() && it != "<unknown>" }
                            ?: "Artista desconocido"
                        val rawFolder = cursor.getString(folderIndex) ?: ""
                        val folder = if (Build.VERSION.SDK_INT >= 29) rawFolder.trimEnd('/')
                            else File(rawFolder).parentFile?.name ?: "Teléfono"
                        items.add(mapOf("id" to "device:$uri", "title" to title, "author" to artist,
                            "path" to uri, "state" to "done", "device" to true,
                            "folder" to folder.ifBlank { "Teléfono" }, "error" to ""))
                    }
                }
                runOnUiThread { pendingScan = null; result.success(items) }
            } catch (e: Exception) {
                runOnUiThread { pendingScan = null; result.error("AUDIO", e.message, null) }
            }
        }.start()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 7302) return
        val result = pendingScan ?: return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) scanAudio(result)
        else {
            pendingScan = null
            result.error("PERMISSION", "Permite Música y audio para explorar el teléfono. También puedes usar Elegir archivos sin ese permiso.", null)
        }
    }

    @Deprecated("Activity callback used by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 7303) {
            val result = pendingPick ?: return
            if (resultCode != Activity.RESULT_OK || data == null) {
                pendingPick = null; result.success(emptyList<Map<String, Any>>()); return
            }
            val uris = mutableListOf<Uri>()
            val clip = data.clipData
            if (clip != null) { for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
            else data.data?.let { uris.add(it) }
            Thread {
                try {
                    val records = uris.distinct().map { uri ->
                        try { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                        catch (_: SecurityException) { /* some providers only grant session access */ }
                        var name = "Audio del teléfono"
                        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                            if (c.moveToFirst()) name = c.getString(0) ?: name
                        }
                        mapOf("id" to "document:$uri", "title" to name, "author" to "Archivo del teléfono",
                            "path" to uri.toString(), "state" to "done", "device" to true,
                            "folder" to "Archivos elegidos", "error" to "")
                    }
                    runOnUiThread { pendingPick = null; result.success(records) }
                } catch (e: Exception) {
                    runOnUiThread { pendingPick = null; result.error("PICK", e.message, null) }
                }
            }.start()
            return
        }
        if (requestCode != 7301) return
        val result = pendingExport ?: return
        val file = exportSource
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || file == null) {
            pendingExport = null; exportSource = null; result.success(false); return
        }
        Thread {
            try {
                contentResolver.openOutputStream(uri, "wt").use { output ->
                    requireNotNull(output) { "No se pudo abrir el destino." }
                    file.inputStream().use { it.copyTo(output) }
                }
                runOnUiThread { pendingExport = null; exportSource = null; result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { pendingExport = null; exportSource = null; result.error("EXPORT", e.message, null) }
            }
        }.start()
    }
}

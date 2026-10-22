package dev.nube.nube_music

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.ffmpeg.FFmpeg
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class YtdlpBridge(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "ritmo/ytdlp")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val watchdog = Executors.newSingleThreadScheduledExecutor()
    private val busy = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    @Volatile private var closed = false
    @Volatile private var processId: String? = null
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "cancel" -> { cancelled.set(true); result.success(null) }
                "inspect", "search", "download", "update" -> {
                    if (!busy.compareAndSet(false, true)) {
                        result.error("BUSY", "Espera a que termine la operación actual.", null)
                    } else {
                        cancelled.set(false)
                        val operation = call.method
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        worker.execute {
                            val id = UUID.randomUUID().toString()
                            processId = id
                            val deadline = System.nanoTime() + TimeUnit.MINUTES.toNanos(if (operation == "download") 120L else 10L)
                            val timedOut = AtomicBoolean(false)
                            val monitor = watchdog.scheduleAtFixedRate({
                                if (System.nanoTime() > deadline) { timedOut.set(true); cancelled.set(true) }
                                if (cancelled.get()) YoutubeDL.destroyProcessById(id)
                            }, 100, 200, TimeUnit.MILLISECONDS)
                            var value: Any? = null
                            var failure: String? = null
                            try {
                                emit("Preparando yt-dlp y FFmpeg…")
                                YoutubeDL.init(context)
                                FFmpeg.init(context)
                                checkCancelled()
                                value = when (operation) {
                                    "inspect" -> inspect(args, id)
                                    "search" -> search(args, id)
                                    "download" -> download(args, id)
                                    else -> {
                                        emit("Actualizando yt-dlp…")
                                        YoutubeDL.updateYoutubeDL(context, YoutubeDL.UpdateChannel.STABLE)
                                        "yt-dlp ${YoutubeDL.versionName(context) ?: YoutubeDL.version(context) ?: "actualizado"}"
                                    }
                                }
                            } catch (e: Exception) {
                                failure = if (timedOut.get()) "Se agotó el tiempo de la operación."
                                    else if (cancelled.get()) "Operación cancelada."
                                    else clean(e.message ?: e.toString()).takeLast(6000)
                            } finally {
                                monitor.cancel(false)
                                processId = null
                                busy.set(false)
                            }
                            val error = failure
                            main.post { if (!closed) {
                                if (error == null) result.success(value)
                                else result.error("YTDLP", error, null)
                            } }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun clean(s: String) = s.replace(Regex("https?://\\S+"), "[enlace]")
    private fun checkCancelled() { check(!cancelled.get()) { "Operación cancelada." } }
    private fun emit(message: String, percent: Double = -1.0, received: Long = 0, total: Long = 0, converting: Boolean = false) {
        val event = mapOf("message" to clean(message).take(1000), "percent" to percent,
            "received" to received, "total" to total, "converting" to converting)
        main.post { if (!closed) channel.invokeMethod("progress", event) }
    }
    private fun request(url: String) = YoutubeDLRequest(url).apply {
        addOption("--ignore-config"); addOption("--no-color")
        addOption("--socket-timeout", "20"); addOption("--retries", "2")
        addOption("--extractor-retries", "2")
    }
    private fun inspect(args: Map<*, *>, id: String): List<Map<String, Any>> {
        val source = args["id"] as? String ?: error("Falta el enlace.")
        val playlist = args["playlist"] == true
        require(Regex(if (playlist) "[A-Za-z0-9_-]{10,100}" else "[A-Za-z0-9_-]{11}").matches(source))
        val url = if (playlist) "https://www.youtube.com/playlist?list=$source" else "https://www.youtube.com/watch?v=$source"
        val req = request(url).apply {
            addOption("--flat-playlist"); addOption("--dump-single-json"); addOption("--skip-download")
            if (!playlist) addOption("--no-playlist")
        }
        emit("Leyendo enlace con yt-dlp…")
        val response = YoutubeDL.execute(req, id, false, null)
        checkCancelled()
        val root = JSONObject(response.out)
        val entries = root.optJSONArray("entries")
        val records = mutableListOf<Map<String, Any>>()
        fun append(item: JSONObject) {
            val video = item.optString("id")
            if (!Regex("[A-Za-z0-9_-]{11}").matches(video)) return
            records.add(mapOf("id" to video, "title" to item.optString("title").ifBlank { video },
                "author" to item.optString("uploader").ifBlank { item.optString("channel").ifBlank { "YouTube" } }))
        }
        if (entries == null) append(root)
        else for (index in 0 until entries.length()) { checkCancelled(); entries.optJSONObject(index)?.let { append(it) } }
        require(records.isNotEmpty()) { "No se encontraron canciones accesibles." }
        return records
    }
    private fun search(args: Map<*, *>, id: String): List<Map<String, Any>> {
        val query = (args["query"] as? String)?.trim() ?: error("Falta la búsqueda.")
        require(query.isNotBlank() && query.length <= 500)
        val req = request("ytsearch5:$query").apply {
            addOption("--flat-playlist"); addOption("--dump-single-json"); addOption("--skip-download")
        }
        val response = YoutubeDL.execute(req, id, false, null)
        checkCancelled()
        val entries = JSONObject(response.out).optJSONArray("entries") ?: return emptyList()
        val found = mutableListOf<Map<String, Any>>()
        for (i in 0 until entries.length()) {
            val item = entries.optJSONObject(i) ?: continue
            val video = item.optString("id")
            if (!Regex("[A-Za-z0-9_-]{11}").matches(video)) continue
            found.add(mapOf("id" to video, "title" to item.optString("title"),
                "author" to item.optString("channel").ifBlank { item.optString("uploader") },
                "duration" to item.optDouble("duration", 0.0)))
        }
        return found
    }
    private fun download(args: Map<*, *>, id: String): String {
        val video = args["id"] as? String ?: error("Falta la canción.")
        require(Regex("[A-Za-z0-9_-]{11}").matches(video))
        val quality = (args["quality"] as? Number)?.toInt() ?: 192
        require(quality in listOf(128, 192, 256, 320))
        val dest = File(args["folder"] as? String ?: error("Falta el destino.")).canonicalFile
        require(dest.path.startsWith(File(context.applicationInfo.dataDir).canonicalPath + File.separator))
        dest.mkdirs()
        val stage = File(dest, ".yt-$id").apply { mkdirs() }
        try {
            val req = request("https://www.youtube.com/watch?v=$video").apply {
                addOption("--no-playlist"); addOption("--newline"); addOption("--progress")
                addOption("--progress-template", "download:RITMO:%(progress.downloaded_bytes)s|%(progress.total_bytes,progress.total_bytes_estimate)s")
                addOption("--fragment-retries", "2")
                addOption("-f", "bestaudio/best"); addOption("-x")
                addOption("--audio-format", "mp3"); addOption("--audio-quality", "${quality}K")
                addOption("--embed-metadata"); addOption("--no-mtime")
                addOption("-o", File(stage, "audio.%(ext)s").absolutePath)
            }
            emit("Buscando audio con yt-dlp…")
            var converting = false
            YoutubeDL.execute(req, id, true) { _, _, line ->
                if (line.contains("[ExtractAudio]")) converting = true
                if (line.startsWith("RITMO:")) {
                    val parts = line.removePrefix("RITMO:").trim().split('|')
                    val received = parts.getOrNull(0)?.toLongOrNull() ?: 0L
                    val total = parts.getOrNull(1)?.toLongOrNull() ?: 0L
                    emit("Descargando audio", if (total > 0) received * 100.0 / total else -1.0, received, total, converting)
                } else if (line.isNotBlank()) emit(if (converting) "Convirtiendo a MP3 · $line" else line, converting = converting)
            }
            checkCancelled()
            val output = File(stage, "audio.mp3")
            require(output.isFile && output.length() > 0) { "yt-dlp no generó un MP3 completo." }
            val target = File(dest, "$video.mp3")
            require(output.renameTo(target)) { "No se pudo guardar el MP3 final." }
            return target.absolutePath
        } finally { stage.deleteRecursively() }
    }
    fun close() {
        closed = true; cancelled.set(true)
        channel.setMethodCallHandler(null)
        worker.shutdown()
        Thread {
            worker.awaitTermination(15, TimeUnit.SECONDS)
            worker.shutdownNow(); watchdog.shutdownNow()
        }.start()
    }
}

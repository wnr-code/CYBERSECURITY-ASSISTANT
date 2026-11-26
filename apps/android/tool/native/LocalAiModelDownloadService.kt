package __ANDROID_PACKAGE__

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.StatFs
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Callable
import java.util.concurrent.CompletionService
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/** Internal foreground downloader. It is not a user-facing download manager. */
internal class LocalAiModelDownloadService : Service() {
    private data class Pin(
        val repository: String,
        val revision: String,
        val fileName: String,
        val license: String,
        val size: Long,
        val sha256: String,
        val licenseRepository: String,
        val licenseRevision: String,
    )
    private data class Request(
        val modelId: String,
        val repository: String,
        val revision: String,
        val fileName: String,
        val license: String,
        val size: Long,
        val sha256: String,
        val url: String,
        val licenseRepository: String,
        val licenseRevision: String,
        val publisherAuthor: String,
        val metadataVerified: Boolean,
    ) {
        fun toJson() = JSONObject().put("modelId", modelId).put("repository", repository).put("revision", revision)
            .put("fileName", fileName).put("license", license).put("size", size).put("sha256", sha256)
            .put("url", url).put("licenseRepository", licenseRepository).put("licenseRevision", licenseRevision)
            .put("publisherAuthor", publisherAuthor).put("metadataVerified", metadataVerified)
    }
    private data class Segment(val index: Int, val start: Long, val end: Long, var received: Long = 0)
    private data class SegmentResult(val etag: String?, val status: Int)
    private class RangeUnsupported : Exception()

    private val pins = mapOf(
        "qwen25-15b-q4km" to Pin("Qwen/Qwen2.5-1.5B-Instruct-GGUF", "dd26da440ef0330c47919d1ecae0966d24022222", "qwen2.5-1.5b-instruct-q4_k_m.gguf", "Apache-2.0", 1_117_320_736L,
            "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e", "Qwen/Qwen2.5-1.5B-Instruct", "989aa7980e4cf806f80c7fef2b1adb7bc71aa306"),
        "qwen25-05b-q4km" to Pin("Qwen/Qwen2.5-0.5B-Instruct-GGUF", "6dd44a1fb35d11b5d1b28902876ce3cc9e882d0e", "qwen2.5-0.5b-instruct-q4_k_m.gguf", "Apache-2.0", 491_400_032L,
            "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db", "Qwen/Qwen2.5-0.5B-Instruct", "7ae557604adf67be50417f59c2c2f167def9a775"),
        "smollm2-17b-q4km" to Pin("HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF", "6a7e79393ef2957e087f11fce1e50476799e313c", "smollm2-1.7b-instruct-q4_k_m.gguf", "Apache-2.0", 1_055_609_536L,
            "decd2598bc2c8ed08c19adc3c8fdd461ee19ed5708679d1c54ef54a5a30d4f33", "HuggingFaceTB/SmolLM2-1.7B-Instruct", "31b70e2e869a7173562077fd711b654946d38674"),
    )

    private val cancelled = AtomicBoolean(false)
    private val progressBytes = AtomicLong(0)
    private val currentConcurrency = AtomicLong(DEFAULT_CONCURRENCY.toLong())
    private val activeConnections = java.util.concurrent.ConcurrentHashMap.newKeySet<HttpURLConnection>()
    @Volatile private var worker: Thread? = null
    @Volatile private var currentRequest: Request? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            cancelAndClean()
            return START_NOT_STICKY
        }
        val request = if (intent != null && intent.action == ACTION_START) requestFrom(intent) else loadSavedRequest()
        if (request == null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        synchronized(this) {
            if (worker?.isAlive == true) {
                if (currentRequest?.modelId == request.modelId) return START_STICKY
                updateStatus("failed", request, 0, "", "Another pinned model download is already active.")
                return START_STICKY
            }
            cancelled.set(false)
            currentRequest = request
            currentConcurrency.set(DEFAULT_CONCURRENCY.toLong())
            saveRequest(request)
            startForegroundCompat(buildNotification("Preparing model download", 0, request.size))
            worker = Thread({ runDownload(request) }, "csa-local-ai-download").apply { isDaemon = true; start() }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        if (worker?.isAlive == true) {
            cancelled.set(true)
            activeConnections.forEach { it.disconnect() }
        }
        super.onDestroy()
    }

    private fun requestFrom(intent: Intent): Request? = runCatching {
        val request = Request(
            modelId = intent.getStringExtra("modelId") ?: return null,
            repository = intent.getStringExtra("repository") ?: return null,
            revision = intent.getStringExtra("revision") ?: return null,
            fileName = intent.getStringExtra("fileName") ?: return null,
            license = intent.getStringExtra("license") ?: return null,
            size = intent.getLongExtra("size", -1L),
            sha256 = intent.getStringExtra("sha256") ?: return null,
            url = intent.getStringExtra("url") ?: return null,
            licenseRepository = intent.getStringExtra("licenseRepository") ?: return null,
            licenseRevision = intent.getStringExtra("licenseRevision") ?: return null,
            publisherAuthor = intent.getStringExtra("publisherAuthor") ?: return null,
            metadataVerified = intent.getBooleanExtra("metadataVerified", false),
        )
        if (!matchesPin(request)) return null
        request
    }.getOrNull()

    private fun loadSavedRequest(): Request? = runCatching {
        val raw = preferences().getString(KEY_REQUEST, null) ?: return null
        val json = JSONObject(raw)
        val request = Request(
            json.getString("modelId"), json.getString("repository"), json.getString("revision"), json.getString("fileName"),
            json.getString("license"), json.getLong("size"), json.getString("sha256"), json.getString("url"),
            json.getString("licenseRepository"), json.getString("licenseRevision"), json.getString("publisherAuthor"),
            json.getBoolean("metadataVerified"),
        )
        if (matchesPin(request)) request else null
    }.getOrNull()

    private fun matchesPin(request: Request): Boolean {
        val pin = pins[request.modelId] ?: return false
        val expectedUrl = "https://huggingface.co/${pin.repository}/resolve/${pin.revision}/${pin.fileName}"
        return request.metadataVerified && request.repository == pin.repository && request.revision == pin.revision &&
            request.license.equals(pin.license, true) && request.size == pin.size && request.sha256.equals(pin.sha256, true) &&
            request.licenseRepository == pin.licenseRepository && request.licenseRevision == pin.licenseRevision &&
            request.publisherAuthor == pin.repository.substringBefore('/') && request.fileName == pin.fileName &&
            request.fileName.matches(Regex("[A-Za-z0-9._-]{1,180}\\.gguf")) && request.url == expectedUrl
    }

    private fun runDownload(request: Request) {
        val root = File(filesDir, "local_ai/models")
        val part = File(root, "${request.fileName}.part")
        val checkpoint = File(root, "${request.fileName}.segments.json")
        try {
            updateStatus("downloading", request, 0, "", null)
            root.mkdirs()
            val finalized = File(root, request.fileName)
            if (finalized.isFile && finalized.length() == request.size && sha256(finalized) == request.sha256) {
                updateStatus("completed", request, request.size, request.sha256, null)
                updateNotification("Model already verified on this phone", request.size, request.size, finished = true)
                return
            }
            val segments = restoreSegments(request, checkpoint, part)
            val remainingBytes = segments.sumOf { (it.end - it.start + 1 - it.received).coerceAtLeast(0) }
            val free = StatFs(root.absolutePath).availableBytes
            val requiredFree = if (part.isFile && part.length() == request.size) STORAGE_MARGIN_BYTES else remainingBytes + STORAGE_MARGIN_BYTES
            if (free < requiredFree) throw IllegalStateException("Insufficient free space for the remaining model bytes and safety margin.")
            progressBytes.set(segments.sumOf { it.received })
            updateStatus("downloading", request, progressBytes.get(), "", null)
            val identity = AtomicReference(readCheckpointIdentity(checkpoint, request))
            var unsupported = false
            val failures = HashMap<Int, Int>()
            val pool = Executors.newFixedThreadPool(MAX_CONCURRENCY)
            val writer = RandomAccessFile(part, "rw")
            try {
                if (part.length() != request.size) writer.setLength(request.size)
                while (segments.any { it.received < it.end - it.start + 1 }) {
                    ensureActive()
                    val pending = segments.filter { it.received < it.end - it.start + 1 }
                    val concurrency = currentConcurrency.get().toInt().coerceIn(1, MAX_CONCURRENCY)
                    val batch = pending.take(concurrency)
                    val batchStartBytes = batch.sumOf { it.received }
                    val completion: CompletionService<Pair<Segment, SegmentResult>> = ExecutorCompletionService(pool)
                    val started = System.nanoTime()
                    val futures = ArrayList<Future<Pair<Segment, SegmentResult>>>()
                    for (segment in batch) {
                        futures += completion.submit(Callable { segment to downloadRange(request, segment, part, writer, segments, checkpoint, identity) })
                    }
                    var rangeRejected = false
                    var limited = false
                    var successes = 0
                    var error: Throwable? = null
                    repeat(futures.size) {
                        try {
                            val (segment, result) = completion.take().get()
                            successes++
                            if (result.status == HttpURLConnection.HTTP_TOO_MANY_REQUESTS || result.status == HttpURLConnection.HTTP_UNAVAILABLE) limited = true
                            if (identity.get() == null && result.etag != null) identity.compareAndSet(null, result.etag)
                            failures.remove(segment.index)
                        } catch (failure: Throwable) {
                            val cause = failure.cause ?: failure
                            if (cause is RangeUnsupported) rangeRejected = true
                            else error = cause
                        }
                    }
                    if (rangeRejected) {
                        futures.forEach { it.cancel(true) }
                        unsupported = true
                        break
                    }
                    if (cancelled.get()) throw InterruptedException("Download cancelled.")
                    if (error != null) {
                        val failing = pending.firstOrNull { it.received < it.end - it.start + 1 } ?: pending.first()
                        val attempts = (failures[failing.index] ?: 0) + 1
                        failures[failing.index] = attempts
                        if (attempts >= MAX_SEGMENT_ATTEMPTS) throw error!!
                        currentConcurrency.set((currentConcurrency.get() / 2).coerceAtLeast(1))
                        Thread.sleep(backoffMillis(attempts))
                    } else if (!limited && successes == batch.size) {
                        val elapsedSeconds = ((System.nanoTime() - started).coerceAtLeast(1)) / 1_000_000_000.0
                        val bytes = batch.sumOf { it.received } - batchStartBytes
                        val rate = bytes.coerceAtLeast(0) / elapsedSeconds
                        if (rate >= MIN_RAMP_BYTES_PER_SECOND) {
                            currentConcurrency.set(when (currentConcurrency.get().toInt()) { in 1..4 -> 8L; in 5..8 -> 16L; else -> MAX_CONCURRENCY.toLong() })
                        }
                    } else if (limited) {
                        currentConcurrency.set((currentConcurrency.get() / 2).coerceAtLeast(1))
                    }
                }
            } finally {
                runCatching { writer.fd.sync() }
                runCatching { writer.close() }
                pool.shutdownNow()
            }
            ensureActive()
            if (unsupported) {
                // A 200 response to Range proves this origin ignored ranges. Never combine it with ranged bytes.
                part.delete()
                checkpoint.delete()
                progressBytes.set(0)
                updateStatus("downloading", request, 0, "", null)
                streamFallback(request, part)
            } else if (segments.any { it.received != it.end - it.start + 1 }) {
                throw IllegalStateException("One or more model byte segments were incomplete.")
            }
            if (part.length() != request.size) throw IllegalStateException("Final GGUF byte count did not match the app pin.")
            updateStatus("verifying", request, request.size, "", null)
            val actualSha = sha256(part)
            if (!MessageDigest.isEqual(actualSha.toByteArray(), request.sha256.toByteArray())) {
                part.delete(); checkpoint.delete()
                throw SecurityException("Final GGUF SHA-256 did not match the immutable publisher pin.")
            }
            val finalFile = File(root, request.fileName)
            val backup = File(root, "${request.fileName}.previous")
            if (finalFile.exists() && !finalFile.renameTo(backup)) throw IllegalStateException("Could not preserve the previously installed model during finalization.")
            if (!part.renameTo(finalFile)) {
                if (backup.exists()) backup.renameTo(finalFile)
                throw IllegalStateException("Verified download could not be atomically finalized.")
            }
            backup.delete(); checkpoint.delete()
            updateStatus("completed", request, request.size, identity.get() ?: request.sha256, null)
            updateNotification("Model verified on this phone", request.size, request.size, finished = true)
        } catch (failure: Throwable) {
            if (cancelled.get() || failure is InterruptedException) {
                part.delete(); checkpoint.delete()
                updateStatus("cancelled", request, 0, "", "Download cancelled; temporary data was removed.")
                updateNotification("Model download cancelled", 0, request.size, finished = true)
            } else {
                val safe = (failure.message ?: "Download failed safely.").replace(Regex("[\\r\\n\\t]"), " ").take(220)
                updateStatus("failed", request, progressBytes.get(), "", safe)
                updateNotification("Model download paused; retry from saved segments", progressBytes.get(), request.size, finished = true)
            }
        } finally {
            activeConnections.forEach { it.disconnect() }
            activeConnections.clear()
            stopForeground(STOP_FOREGROUND_DETACH)
            stopSelf()
        }
    }

    private fun restoreSegments(request: Request, checkpoint: File, part: File): MutableList<Segment> {
        val count = ((request.size + SEGMENT_BYTES - 1) / SEGMENT_BYTES).toInt()
        val fresh = (0 until count).map { index ->
            val start = index.toLong() * SEGMENT_BYTES
            Segment(index, start, minOf(request.size - 1, start + SEGMENT_BYTES - 1))
        }.toMutableList()
        if (!part.exists() || !checkpoint.exists()) {
            checkpoint.delete()
            if (part.exists() && !part.delete()) throw IllegalStateException("Could not discard an incomplete model file without a resumable checkpoint.")
            return fresh
        }
        val saved = runCatching { JSONObject(checkpoint.readText()) }.getOrNull() ?: run { part.delete(); checkpoint.delete(); return fresh }
        if (saved.optString("fileSha") != request.sha256 || saved.optString("revision") != request.revision ||
            saved.optLong("size", -1) != request.size || saved.optInt("count", -1) != count || part.length() != request.size) {
            part.delete(); checkpoint.delete(); return fresh
        }
        val values = saved.optJSONArray("segments") ?: return fresh
        if (values.length() != count) { part.delete(); checkpoint.delete(); return fresh }
        fresh.forEachIndexed { index, segment ->
            val max = segment.end - segment.start + 1
            segment.received = values.optLong(index, 0L).coerceIn(0L, max)
        }
        return fresh
    }

    private fun readCheckpointIdentity(checkpoint: File, request: Request): String? = runCatching {
        JSONObject(checkpoint.readText()).takeIf { it.optString("fileSha") == request.sha256 && it.optString("revision") == request.revision }
            ?.optString("etag")?.takeIf { it.isNotBlank() && it != "null" }
    }.getOrNull()

    private fun downloadRange(
        request: Request,
        segment: Segment,
        part: File,
        writer: RandomAccessFile,
        segments: List<Segment>,
        checkpoint: File,
        identity: AtomicReference<String?>,
    ): SegmentResult {
        var lastError: Throwable? = null
        for (attempt in 1..MAX_SEGMENT_ATTEMPTS) {
            ensureActive()
            val remainingStart = segment.start + segment.received
            if (remainingStart > segment.end) return SegmentResult(identity.get(), HttpURLConnection.HTTP_PARTIAL)
            var connection: HttpURLConnection? = null
            try {
                connection = openRequest(request.url, remainingStart, segment.end, identity.get()?.takeUnless { it == NO_ETAG_IDENTITY })
                activeConnections.add(connection)
                val status = connection.responseCode
                if (status == HttpURLConnection.HTTP_OK) throw RangeUnsupported()
                if (status != HttpURLConnection.HTTP_PARTIAL) throw IllegalStateException("Range request failed with HTTP $status.")
                val expectedRange = "bytes $remainingStart-${segment.end}/${request.size}"
                if (connection.getHeaderField("Content-Range") != expectedRange) throw SecurityException("Server returned a different Content-Range than requested.")
                val expectedLength = segment.end - remainingStart + 1
                if (connection.contentLengthLong >= 0 && connection.contentLengthLong != expectedLength) throw SecurityException("Server returned a different byte count than the requested segment.")
                val etag = connection.getHeaderField("ETag")?.trim()?.takeIf { it.isNotEmpty() }
                val knownIdentity = identity.get()
                if (knownIdentity != null && (knownIdentity == NO_ETAG_IDENTITY && etag != null || knownIdentity != NO_ETAG_IDENTITY && knownIdentity != etag)) {
                    throw SecurityException("ETag changed or disappeared while the model segments were downloading.")
                }
                val observedIdentity = etag ?: NO_ETAG_IDENTITY
                if (knownIdentity == null && !identity.compareAndSet(null, observedIdentity) && identity.get() != observedIdentity) {
                    throw SecurityException("ETag changed while the model segments were downloading.")
                }
                BufferedInputStream(connection.inputStream, STREAM_BUFFER_BYTES).use { input ->
                    val buffer = ByteArray(STREAM_BUFFER_BYTES)
                    var segmentBytes = 0L
                    var checkpointedAt = segment.received
                    while (true) {
                        ensureActive()
                        val read = input.read(buffer)
                        if (read < 0) break
                        segmentBytes += read
                        if (segmentBytes > expectedLength) throw SecurityException("Server sent more bytes than the requested segment.")
                        synchronized(writer) {
                            writer.seek(segment.start + segment.received)
                            writer.write(buffer, 0, read)
                            segment.received += read
                            val overall = progressBytes.addAndGet(read.toLong())
                            val complete = segment.received == segment.end - segment.start + 1
                            if (segment.received - checkpointedAt >= CHECKPOINT_INTERVAL_BYTES || complete) {
                                writer.fd.sync()
                                writeCheckpoint(checkpoint, request, segments, identity.get()?.takeUnless { it == NO_ETAG_IDENTITY })
                                checkpointedAt = segment.received
                            }
                            if (overall % PROGRESS_UPDATE_INTERVAL_BYTES < read) {
                                updateNotification(null, overall, request.size)
                                updateStatus("downloading", request, overall, identity.get() ?: request.sha256, null)
                            }
                        }
                    }
                    if (segmentBytes != expectedLength) throw IllegalStateException("The server closed a model segment early.")
                }
                return SegmentResult(identity.get() ?: etag, status)
            } catch (error: RangeUnsupported) {
                throw error
            } catch (error: Throwable) {
                lastError = error
                if (attempt < MAX_SEGMENT_ATTEMPTS) Thread.sleep(backoffMillis(attempt))
            } finally {
                connection?.let { activeConnections.remove(it); it.disconnect() }
            }
        }
        throw lastError ?: IllegalStateException("Model segment failed after retries.")
    }

    private fun streamFallback(request: Request, part: File) {
        var connection: HttpURLConnection? = null
        try {
            connection = openRequest(request.url, null, null, null)
            activeConnections.add(connection)
            if (connection.responseCode != HttpURLConnection.HTTP_OK) throw IllegalStateException("Non-range download fallback failed with HTTP ${connection.responseCode}.")
            val etag = connection.getHeaderField("ETag")
            FileOutputStream(part, false).use { output ->
                BufferedInputStream(connection.inputStream, STREAM_BUFFER_BYTES).use { input ->
                    val buffer = ByteArray(STREAM_BUFFER_BYTES)
                    var total = 0L
                    while (true) {
                        ensureActive()
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > request.size) throw SecurityException("Server sent more bytes than the pinned model size.")
                        output.write(buffer, 0, read)
                        progressBytes.set(total)
                        if (total % CHECKPOINT_INTERVAL_BYTES < read) {
                            output.fd.sync()
                            updateNotification(null, total, request.size)
                            updateStatus("downloading", request, total, etag ?: request.sha256, null)
                        }
                    }
                    output.fd.sync()
                    if (total != request.size) throw IllegalStateException("Non-range download ended before the pinned model size was received.")
                }
            }
        } finally {
            connection?.let { activeConnections.remove(it); it.disconnect() }
        }
    }

    private fun openRequest(url: String, start: Long?, end: Long?, ifRange: String?): HttpURLConnection {
        var current = URL(url)
        for (redirect in 0..MAX_REDIRECTS) {
            if (current.protocol != "https" || !isApprovedHost(current.host)) throw SecurityException("Model source redirected outside approved HTTPS Hugging Face hosts.")
            val connection = (current.openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                setRequestProperty("Accept-Encoding", "identity")
                setRequestProperty("User-Agent", "CybersecurityAssistant-LocalAI/1.0")
                if (start != null && end != null) {
                    setRequestProperty("Range", "bytes=$start-$end")
                    if (!ifRange.isNullOrBlank()) setRequestProperty("If-Range", ifRange)
                }
            }
            val status = connection.responseCode
            if (status in 300..399) {
                val location = connection.getHeaderField("Location") ?: throw IllegalStateException("Hugging Face redirect omitted Location.")
                connection.disconnect()
                if (redirect == MAX_REDIRECTS) throw IllegalStateException("Hugging Face redirect limit exceeded.")
                current = URL(current, location)
                continue
            }
            return connection
        }
        throw IllegalStateException("Hugging Face redirect limit exceeded.")
    }

    private fun isApprovedHost(host: String): Boolean =
        host == "huggingface.co" || host == "hf.co" || host.endsWith(".huggingface.co") || host.endsWith(".hf.co")

    private fun writeCheckpoint(file: File, request: Request, segments: List<Segment>, identity: String?) {
        val root = JSONObject().put("fileSha", request.sha256).put("revision", request.revision).put("size", request.size)
            .put("count", segments.size).put("etag", identity ?: JSONObject.NULL).put("segments", JSONArray().apply { segments.forEach { put(it.received) } })
        val temp = File(file.parentFile, file.name + ".tmp")
        FileOutputStream(temp, false).use { stream -> stream.write(root.toString().toByteArray(Charsets.UTF_8)); stream.fd.sync() }
        if (file.exists() && !file.delete()) throw IllegalStateException("Could not update the resumable segment checkpoint.")
        if (!temp.renameTo(file)) throw IllegalStateException("Could not finalize the resumable segment checkpoint.")
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) { val read = input.read(buffer); if (read < 0) break; digest.update(buffer, 0, read) }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private fun ensureActive() { if (cancelled.get() || Thread.currentThread().isInterrupted) throw InterruptedException("Download cancelled.") }
    private fun backoffMillis(attempt: Int): Long = minOf(MAX_BACKOFF_MS, BASE_BACKOFF_MS shl (attempt - 1).coerceIn(0, 6))
    private fun preferences() = getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private fun saveRequest(request: Request) {
        if (!preferences().edit().putString(KEY_REQUEST, request.toJson().toString()).commit()) {
            throw IllegalStateException("Could not persist the pinned model download request safely.")
        }
    }

    private fun updateStatus(state: String, request: Request, bytes: Long, identity: String, error: String?) {
        val json = JSONObject().put("state", state).put("modelId", request.modelId).put("fileName", request.fileName)
            .put("bytesReceived", bytes.coerceAtMost(request.size)).put("totalBytes", request.size)
            .put("concurrency", currentConcurrency.get()).put("identity", identity)
            .put("updatedAt", System.currentTimeMillis()).put("error", error)
        preferences().edit().putString(KEY_STATUS, json.toString()).apply()
    }

    private fun updateNotification(text: String?, bytes: Long, total: Long, finished: Boolean = false) {
        val request = currentRequest ?: return
        val percent = if (total <= 0) 0 else ((bytes * 100) / total).toInt().coerceIn(0, 100)
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(text ?: "Downloading ${request.fileName} · $percent%", bytes, total, finished))
    }

    private fun buildNotification(text: String, bytes: Long, total: Long, finished: Boolean = false): Notification {
        val request = currentRequest ?: loadSavedRequest()
        val cancelIntent = Intent(this, LocalAiModelDownloadService::class.java).setAction(ACTION_CANCEL)
        val pending = PendingIntent.getService(this, 0, cancelIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(if (finished) "Local AI model" else "Local AI model download")
            .setContentText(text)
            .setOngoing(!finished)
            .setOnlyAlertOnce(true)
        if (!finished) builder.addAction(Notification.Action.Builder(null, "Cancel", pending).build())
        if (total > 0) builder.setProgress(100, ((bytes * 100) / total).toInt().coerceIn(0, 100), false)
        return builder.build()
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Local AI model downloads", NotificationManager.IMPORTANCE_LOW).apply { description = "Overall progress for an explicitly selected on-device model." },
            )
        }
    }

    private fun cancelAndClean() {
        cancelled.set(true)
        activeConnections.forEach { it.disconnect() }
        worker?.interrupt()
        val request = currentRequest ?: loadSavedRequest()
        request?.let {
            val root = File(filesDir, "local_ai/models")
            File(root, "${it.fileName}.part").delete()
            File(root, "${it.fileName}.segments.json").delete()
            File(root, "${it.fileName}.segments.json.tmp").delete()
            updateStatus("cancelled", it, 0, "", "Download cancelled; temporary data was removed.")
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    companion object {
        private const val PREFERENCES = "local_ai_model_download"
        private const val KEY_REQUEST = "request"
        private const val KEY_STATUS = "status"
        private const val ACTION_START = "org.cybersecurityassistant.localai.START_DOWNLOAD"
        private const val ACTION_CANCEL = "org.cybersecurityassistant.localai.CANCEL_DOWNLOAD"
        private const val CHANNEL_ID = "local_ai_model_download"
        private const val NOTIFICATION_ID = 7842
        private const val NO_ETAG_IDENTITY = "__NO_ETAG__"
        private const val DEFAULT_CONCURRENCY = 4
        private const val MAX_CONCURRENCY = 16
        private const val SEGMENT_BYTES = 16L * 1024 * 1024
        private const val STREAM_BUFFER_BYTES = 256 * 1024
        private const val STORAGE_MARGIN_BYTES = 64L * 1024 * 1024
        private const val CHECKPOINT_INTERVAL_BYTES = 4L * 1024 * 1024
        private const val PROGRESS_UPDATE_INTERVAL_BYTES = 1L * 1024 * 1024
        private const val MIN_RAMP_BYTES_PER_SECOND = 512L * 1024
        private const val MAX_SEGMENT_ATTEMPTS = 5
        private const val MAX_REDIRECTS = 5
        private const val CONNECT_TIMEOUT_MS = 20_000
        private const val READ_TIMEOUT_MS = 60_000
        private const val BASE_BACKOFF_MS = 500L
        private const val MAX_BACKOFF_MS = 16_000L

        fun start(context: Context, values: Map<String, Any?>) {
            val intent = Intent(context, LocalAiModelDownloadService::class.java).setAction(ACTION_START)
            values.forEach { (key, value) ->
                when (value) {
                    is String -> intent.putExtra(key, value)
                    is Int -> if (key == "size") intent.putExtra(key, value.toLong()) else intent.putExtra(key, value)
                    is Long -> intent.putExtra(key, value)
                    is Boolean -> intent.putExtra(key, value)
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
        }

        fun cancel(context: Context) {
            context.startService(Intent(context, LocalAiModelDownloadService::class.java).setAction(ACTION_CANCEL))
        }

        fun status(context: Context): Map<String, Any?> {
            val raw = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getString(KEY_STATUS, null) ?: return mapOf("state" to "idle")
            return runCatching {
                val json = JSONObject(raw)
                mapOf(
                    "state" to json.optString("state", "idle"), "modelId" to json.optString("modelId"),
                    "fileName" to json.optString("fileName"), "bytesReceived" to json.optLong("bytesReceived"),
                    "totalBytes" to json.optLong("totalBytes"), "concurrency" to json.optLong("concurrency"),
                    "identity" to json.optString("identity"), "updatedAt" to json.optLong("updatedAt"), "error" to json.optString("error").takeIf { it.isNotBlank() },
                )
            }.getOrDefault(mapOf("state" to "unknown"))
        }
    }
}

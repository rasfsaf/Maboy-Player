package com.maboy.player

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import java.io.File
import android.util.Log

class MainActivity : FlutterActivity() {
    private val shareChannelName = "com.maboy.player/share"
    private val mediaChannelName = "com.maboy.player/media"
    private var shareChannel: MethodChannel? = null
    private var mediaChannel: MethodChannel? = null
    private var initialSharedText: String? = null

    private var permissionCallback: MethodChannel.Result? = null
    private val PERMISSION_REQUEST_CODE = 1002

    private var audioDeviceCallback: android.media.AudioDeviceCallback? = null

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (AudioManager.ACTION_AUDIO_BECOMING_NOISY == intent?.action) {
                mediaChannel?.invokeMethod("onAudioBecomingNoisy", null)
            }
        }
    }

    private val sleepEventsChannelName = "jigit.studio/sleep_events"
    private var sleepEventSink: EventChannel.EventSink? = null
    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var lastMovementSampleTime: Long = 0L
    private var lastShakeSampleTime: Long = 0L

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (Intent.ACTION_SCREEN_ON == intent?.action) {
                runOnUiThread {
                    sleepEventSink?.success(mapOf("type" to "screen_on"))
                }
            }
        }
    }

    private val sleepSegmentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return
            try {
                val hasSleepClass = try {
                    Class.forName("com.google.android.gms.location.SleepSegmentEvent")
                    true
                } catch (e: Throwable) {
                    false
                }
                if (hasSleepClass) {
                    val extractMethod = Class.forName("com.google.android.gms.location.SleepSegmentEvent")
                        .getMethod("extractEvents", Intent::class.java)
                    val events = extractMethod.invoke(null, intent) as? List<*>
                    if (events != null && events.isNotEmpty()) {
                        val getConfidence = events[0]::class.java.getMethod("getStatus")
                        val confidence = (getConfidence.invoke(events[0]) as? Number)?.toInt() ?: 100
                        runOnUiThread {
                            sleepEventSink?.success(mapOf("type" to "sleep_segment", "confidence" to confidence))
                        }
                        return
                    }
                }
                if (intent.hasExtra("confidence")) {
                    val conf = intent.getIntExtra("confidence", 80)
                    runOnUiThread {
                        sleepEventSink?.success(mapOf("type" to "sleep_segment", "confidence" to conf))
                    }
                }
            } catch (e: Exception) {
                Log.w("maboy", "Error extracting sleep segment", e)
            }
        }
    }

    private val accelerometerListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent?) {
            if (event == null || event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
            val x = event.values[0]
            val y = event.values[1]
            val z = event.values[2]
            val g = Math.sqrt((x * x + y * y + z * z).toDouble()).toFloat()
            val deltaG = Math.abs(g - 9.80665f)

            val now = System.currentTimeMillis()
            if (deltaG >= 2.5f) {
                if (now - lastShakeSampleTime >= 300) {
                    lastShakeSampleTime = now
                    runOnUiThread {
                        sleepEventSink?.success(mapOf("type" to "shake", "delta" to deltaG.toDouble()))
                    }
                }
            } else if (deltaG >= 0.4f) {
                if (now - lastMovementSampleTime >= 500) {
                    lastMovementSampleTime = now
                    runOnUiThread {
                        sleepEventSink?.success(mapOf("type" to "movement", "delta" to deltaG.toDouble()))
                    }
                }
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    private fun registerSleepSensors() {
        try {
            registerReceiver(screenReceiver, IntentFilter(Intent.ACTION_SCREEN_ON))
        } catch (e: Exception) {
            Log.w("maboy", "Unable to register screen_on receiver", e)
        }
        try {
            val filter = IntentFilter("com.google.android.gms.location.sleep.EXTRA_SLEEP_SEGMENT_RESULT").apply {
                addAction("jigit.studio.SLEEP_SEGMENT")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(sleepSegmentReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(sleepSegmentReceiver, filter)
            }
        } catch (e: Exception) {
            Log.w("maboy", "Unable to register sleep segment receiver", e)
        }
        try {
            sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
            accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            accelerometer?.let {
                sensorManager?.registerListener(accelerometerListener, it, 500_000)
            }
        } catch (e: Exception) {
            Log.w("maboy", "Unable to register accelerometer listener", e)
        }
    }

    private fun unregisterSleepSensors() {
        try {
            unregisterReceiver(screenReceiver)
        } catch (e: Exception) {
            // Ignored
        }
        try {
            unregisterReceiver(sleepSegmentReceiver)
        } catch (e: Exception) {
            // Ignored
        }
        try {
            sensorManager?.unregisterListener(accelerometerListener)
        } catch (e: Exception) {
            // Ignored
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerAudioMonitoring()
        handleIntent(intent)
    }

    private fun registerAudioMonitoring() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(
                    noisyReceiver,
                    IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
                    Context.RECEIVER_NOT_EXPORTED
                )
            } else {
                registerReceiver(
                    noisyReceiver,
                    IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
                )
            }
        } catch (error: Exception) {
            Log.w("maboy", "Unable to register noisy-audio receiver", error)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                if (audioManager != null) {
                    val callback = object : android.media.AudioDeviceCallback() {
                        override fun onAudioDevicesRemoved(removedDevices: Array<out android.media.AudioDeviceInfo>?) {
                            super.onAudioDevicesRemoved(removedDevices)
                            if (removedDevices == null) return
                            for (device in removedDevices) {
                                when (device.type) {
                                    android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET,
                                    android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                                    android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                                    android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                                    android.media.AudioDeviceInfo.TYPE_USB_HEADSET,
                                    android.media.AudioDeviceInfo.TYPE_USB_DEVICE,
                                    android.media.AudioDeviceInfo.TYPE_BLE_HEADSET,
                                    android.media.AudioDeviceInfo.TYPE_BLE_SPEAKER,
                                    android.media.AudioDeviceInfo.TYPE_HEARING_AID -> {
                                        Log.i("maboy", "Audio device disconnected (${device.type}), triggering pause")
                                        mediaChannel?.invokeMethod("onAudioBecomingNoisy", null)
                                        return
                                    }
                                }
                            }
                        }
                    }
                    audioDeviceCallback = callback
                    audioManager.registerAudioDeviceCallback(callback, null)
                }
            } catch (error: Exception) {
                Log.w("maboy", "Unable to register audio device callback", error)
            }
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(noisyReceiver)
        } catch (error: Exception) {
            Log.w("maboy", "Unable to unregister noisy-audio receiver", error)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && audioDeviceCallback != null) {
            try {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                audioDeviceCallback?.let { audioManager?.unregisterAudioDeviceCallback(it) }
            } catch (error: Exception) {
                Log.w("maboy", "Unable to unregister audio device callback", error)
            }
            audioDeviceCallback = null
        }
        unregisterSleepSensors()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val shareCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
        shareChannel = shareCh

        shareCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> {
                    val text = initialSharedText
                    initialSharedText = null
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }

        val mediaCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannelName)
        mediaChannel = mediaCh

        mediaCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    result.success(hasAudioPermission())
                }
                "requestPermission" -> {
                    requestAudioPermission(result)
                }
                "queryMediaStore" -> {
                    result.success(queryMediaStore())
                }
                "getDefaultAudioDirs" -> {
                    result.success(getDefaultAudioDirs())
                }
                "getStorageVolumes" -> {
                    result.success(getStorageVolumes())
                }
                else -> result.notImplemented()
            }
        }

        // If an intent arrived before engine configuration, dispatch it now
        initialSharedText?.let { text ->
            shareCh.invokeMethod("onSharedText", text)
        }

        val sleepChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, sleepEventsChannelName)
        sleepChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sleepEventSink = events
                registerSleepSensors()
            }

            override fun onCancel(arguments: Any?) {
                unregisterSleepSensors()
                sleepEventSink = null
            }
        })
    }

    private fun hasAudioPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(Manifest.permission.READ_MEDIA_AUDIO) == PackageManager.PERMISSION_GRANTED
        } else {
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestAudioPermission(result: MethodChannel.Result) {
        if (hasAudioPermission()) {
            result.success(true)
            return
        }
        permissionCallback = result
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.READ_MEDIA_AUDIO)
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        requestPermissions(permissions, PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            permissionCallback?.success(granted)
            permissionCallback = null
        }
    }

    private fun queryMediaStore(): List<Map<String, Any?>> {
        val tracks = mutableListOf<Map<String, Any?>>()
        try {
            val projection = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.TITLE,
                MediaStore.Audio.Media.ARTIST,
                MediaStore.Audio.Media.ALBUM,
                MediaStore.Audio.Media.DURATION,
                MediaStore.Audio.Media.DATA
            )
            val selection = "(${MediaStore.Audio.Media.IS_MUSIC} != 0) OR (${MediaStore.Audio.Media.MIME_TYPE} LIKE 'audio/%')"
            val sortOrder = "${MediaStore.Audio.Media.DATE_ADDED} DESC"

            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                null,
                sortOrder
            )?.use { cursor ->
                val titleCol = cursor.getColumnIndex(MediaStore.Audio.Media.TITLE)
                val artistCol = cursor.getColumnIndex(MediaStore.Audio.Media.ARTIST)
                val albumCol = cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM)
                val durationCol = cursor.getColumnIndex(MediaStore.Audio.Media.DURATION)
                val dataCol = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)

                while (cursor.moveToNext()) {
                    val path = if (dataCol != -1) cursor.getString(dataCol) else null
                    if (path != null && File(path).exists()) {
                        val title = if (titleCol != -1) cursor.getString(titleCol) else null
                        val artist = if (artistCol != -1) cursor.getString(artistCol) else null
                        val album = if (albumCol != -1) cursor.getString(albumCol) else null
                        val duration = if (durationCol != -1) cursor.getLong(durationCol) else null

                        tracks.add(
                            mapOf(
                                "path" to path,
                                "title" to title,
                                "artist" to artist,
                                "album" to album,
                                "duration_ms" to duration
                            )
                        )
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return tracks
    }

    private fun getDefaultAudioDirs(): List<String> {
        val dirs = mutableListOf<String>()
        try {
            val musicDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
            if (musicDir != null && musicDir.exists()) dirs.add(musicDir.absolutePath)

            val downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (downloadDir != null && downloadDir.exists()) dirs.add(downloadDir.absolutePath)

            val podcastsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PODCASTS)
            if (podcastsDir != null && podcastsDir.exists()) dirs.add(podcastsDir.absolutePath)

            val commonDirs = arrayOf("/storage/emulated/0/Audio", "/storage/emulated/0/Recordings")
            for (p in commonDirs) {
                val f = File(p)
                if (f.exists() && f.isDirectory && !dirs.contains(f.absolutePath)) {
                    dirs.add(f.absolutePath)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return dirs
    }

    private fun getStorageVolumes(): List<Map<String, Any?>> {
        val volumes = mutableListOf<Map<String, Any?>>()
        try {
            val dirs = getExternalFilesDirs(Environment.DIRECTORY_MUSIC)
            for (dir in dirs) {
                if (dir != null) {
                    val state = Environment.getExternalStorageState(dir)
                    if (state == Environment.MEDIA_MOUNTED) {
                        val isRemovable = Environment.isExternalStorageRemovable(dir)
                        val freeBytes = dir.usableSpace
                        val totalBytes = dir.totalSpace
                        volumes.add(
                            mapOf(
                                "path" to dir.absolutePath,
                                "isRemovable" to isRemovable,
                                "freeBytes" to freeBytes,
                                "totalBytes" to totalBytes,
                                "name" to if (isRemovable) "SD-карта" else "Внутренняя память"
                            )
                        )
                    }
                }
            }
        } catch (e: Exception) {
            Log.w("maboy", "Error querying storage volumes", e)
        }
        return volumes
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        if (Intent.ACTION_SEND == intent.action && "text/plain" == intent.type) {
            val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (!sharedText.isNullOrBlank()) {
                val channel = shareChannel
                if (channel != null) {
                    channel.invokeMethod("onSharedText", sharedText)
                } else {
                    initialSharedText = sharedText
                }
            }
        }
    }
}

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
import io.flutter.plugin.common.MethodChannel
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
                else -> result.notImplemented()
            }
        }

        // If an intent arrived before engine configuration, dispatch it now
        initialSharedText?.let { text ->
            shareCh.invokeMethod("onSharedText", text)
        }
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

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    afterEvaluate {
        val android = project.extensions.findByName("android")
        if (android is com.android.build.gradle.BaseExtension) {
            android.compileSdkVersion(36)
        }
        if (android is com.android.build.gradle.LibraryExtension) {
            android.compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    if (name == "mpv_audio_kit") {
        val patchMpvAudioKit = {
            try {
                val mediaMappersFile = file("src/main/kotlin/com/alesdrnz/mpv_audio_kit/media_session/MediaSessionMappers.kt")
                if (mediaMappersFile.exists()) {
                    var content = mediaMappersFile.readText()
                    if (!content.contains("Player.COMMAND_SEEK_TO_NEXT")) {
                        content = content.replace(
                            "if (\"next\" in actions) b.add(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)",
                            "if (\"next\" in actions) {\n            b.add(Player.COMMAND_SEEK_TO_NEXT)\n            b.add(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)\n        }"
                        ).replace(
                            "if (\"previous\" in actions) b.add(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)",
                            "if (\"previous\" in actions) {\n            b.add(Player.COMMAND_SEEK_TO_PREVIOUS)\n            b.add(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)\n        }"
                        )
                        mediaMappersFile.writeText(content)
                        println("[Maboy] Patched MediaSessionMappers.kt for Android 10 notification controls")
                    }
                }

                val mediaManagerFile = file("src/main/kotlin/com/alesdrnz/mpv_audio_kit/media_session/MediaSessionManager.kt")
                if (mediaManagerFile.exists()) {
                    var content = mediaManagerFile.readText()
                    if (!content.contains("headsetClickCount")) {
                        if (!content.contains("cancelHeadsetClicks")) {
                            content = content.replace(
                                "private val mainHandler = Handler(Looper.getMainLooper())",
                                """private val mainHandler = Handler(Looper.getMainLooper())

    private var headsetClickCount = 0
    private val headsetHandler = Handler(Looper.getMainLooper())
    private val headsetClickRunnable = Runnable {
        when (headsetClickCount) {
            1 -> forwardCommand(mapOf("type" to "playPause"))
            2 -> forwardCommand(mapOf("type" to "next"))
            3 -> forwardCommand(mapOf("type" to "previous"))
            else -> if (headsetClickCount > 3) forwardCommand(mapOf("type" to "previous"))
        }
        headsetClickCount = 0
    }

    private fun cancelHeadsetClicks() {
        headsetHandler.removeCallbacks(headsetClickRunnable)
        headsetClickCount = 0
    }"""
                            )
                        }

                        if (!content.contains("cancelHeadsetClicks()\n        enabled = false")) {
                            content = content.replace(
                                "private fun disable() = runOnMain {\n        enabled = false",
                                "private fun disable() = runOnMain {\n        cancelHeadsetClicks()\n        enabled = false"
                            )
                        }

                        val targetSnippet = """        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle,
        ): ListenableFuture<SessionResult> {
            if (customCommand.customAction == MediaSessionMappers.LIKE_ACTION) {
                forwardCommand(mapOf("type" to "like"))
                return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
            }
            return Futures.immediateFuture(
                SessionResult(SessionResult.RESULT_ERROR_NOT_SUPPORTED),
            )
        }"""
                        val replacementSnippet = """        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle,
        ): ListenableFuture<SessionResult> {
            if (customCommand.customAction == MediaSessionMappers.LIKE_ACTION) {
                forwardCommand(mapOf("type" to "like"))
                return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
            }
            return Futures.immediateFuture(
                SessionResult(SessionResult.RESULT_ERROR_NOT_SUPPORTED),
            )
        }

        override fun onMediaButtonEvent(
            session: MediaSession,
            controllerInfo: MediaSession.ControllerInfo,
            intent: Intent,
        ): Boolean {
            val keyEvent = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, android.view.KeyEvent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<android.view.KeyEvent>(Intent.EXTRA_KEY_EVENT)
            } ?: return false
            if (keyEvent.action != android.view.KeyEvent.ACTION_DOWN) return true
            if (keyEvent.repeatCount != 0) return true
            when (keyEvent.keyCode) {
                android.view.KeyEvent.KEYCODE_MEDIA_NEXT,
                android.view.KeyEvent.KEYCODE_MEDIA_SKIP_FORWARD,
                android.view.KeyEvent.KEYCODE_MEDIA_FAST_FORWARD,
                android.view.KeyEvent.KEYCODE_MEDIA_STEP_FORWARD -> {
                    cancelHeadsetClicks()
                    forwardCommand(mapOf("type" to "next"))
                    return true
                }
                android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS,
                android.view.KeyEvent.KEYCODE_MEDIA_SKIP_BACKWARD,
                android.view.KeyEvent.KEYCODE_MEDIA_REWIND,
                android.view.KeyEvent.KEYCODE_MEDIA_STEP_BACKWARD -> {
                    cancelHeadsetClicks()
                    forwardCommand(mapOf("type" to "previous"))
                    return true
                }
                android.view.KeyEvent.KEYCODE_MEDIA_PLAY -> {
                    cancelHeadsetClicks()
                    forwardCommand(mapOf("type" to "play"))
                    return true
                }
                android.view.KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                    cancelHeadsetClicks()
                    forwardCommand(mapOf("type" to "pause"))
                    return true
                }
                android.view.KeyEvent.KEYCODE_MEDIA_STOP -> {
                    cancelHeadsetClicks()
                    forwardCommand(mapOf("type" to "stop"))
                    return true
                }
                android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
                android.view.KeyEvent.KEYCODE_HEADSETHOOK -> {
                    headsetHandler.removeCallbacks(headsetClickRunnable)
                    headsetClickCount++
                    if (headsetClickCount >= 3) {
                        cancelHeadsetClicks()
                        forwardCommand(mapOf("type" to "previous"))
                    } else {
                        headsetHandler.postDelayed(headsetClickRunnable, 350L)
                    }
                    return true
                }
            }
            return false
        }"""
                        if (content.contains("override fun onMediaButtonEvent")) {
                            val pattern = Regex("""\s*override fun onMediaButtonEvent[\s\S]*?return false\s*\}""")
                            val newCallbackBlock = """

        override fun onMediaButtonEvent(
            session: MediaSession,
            controllerInfo: MediaSession.ControllerInfo,
            intent: Intent,
        ): Boolean {
            val keyEvent = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, android.view.KeyEvent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<android.view.KeyEvent>(Intent.EXTRA_KEY_EVENT)
            } ?: return false
            if (keyEvent.action != android.view.KeyEvent.ACTION_DOWN) return true
            if (keyEvent.repeatCount != 0) return true
            when (keyEvent.keyCode) {
                android.view.KeyEvent.KEYCODE_MEDIA_NEXT,
                android.view.KeyEvent.KEYCODE_MEDIA_SKIP_FORWARD,
                android.view.KeyEvent.KEYCODE_MEDIA_FAST_FORWARD,
                android.view.KeyEvent.KEYCODE_MEDIA_STEP_FORWARD -> {
                    cancelHeadsetClicks()
                    forwardCommand(mapOf("type" to "next"))
                    return true
                }
                android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS,
                android.view.KeyEvent.KEYCODE_MEDIA_SKIP_BACKWARD,
                android.view.KeyEvent.KEYCODE_MEDIA_REWIND,
                android.view.KeyEvent.KEYCODE_MEDIA_STEP_BACKWARD -> {
                    cancelHeadsetClicks()
                    forwardCommand(mapOf("type" to "previous"))
                    return true
                }
                android.view.KeyEvent.KEYCODE_MEDIA_PLAY -> {
                    cancelHeadsetClicks()
                    forwardCommand(mapOf("type" to "play"))
                    return true
                }
                android.view.KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                    cancelHeadsetClicks()
                    forwardCommand(mapOf("type" to "pause"))
                    return true
                }
                android.view.KeyEvent.KEYCODE_MEDIA_STOP -> {
                    cancelHeadsetClicks()
                    forwardCommand(mapOf("type" to "stop"))
                    return true
                }
                android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
                android.view.KeyEvent.KEYCODE_HEADSETHOOK -> {
                    headsetHandler.removeCallbacks(headsetClickRunnable)
                    headsetClickCount++
                    if (headsetClickCount >= 3) {
                        cancelHeadsetClicks()
                        forwardCommand(mapOf("type" to "previous"))
                    } else {
                        headsetHandler.postDelayed(headsetClickRunnable, 350L)
                    }
                    return true
                }
            }
            return false
        }"""
                            content = pattern.replace(content, newCallbackBlock)
                        } else {
                            content = content.replace(targetSnippet, replacementSnippet)
                        }
                        mediaManagerFile.writeText(content)
                        println("[Maboy] Patched MediaSessionManager.kt for headphone multi-click controls")
                    }
                }
            } catch (e: Exception) {
                println("[Maboy] Note: mpv_audio_kit patch check: " + e.message)
            }
        }
        patchMpvAudioKit()
        afterEvaluate {
            patchMpvAudioKit()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

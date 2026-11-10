# Reaplica patches Android no haishin_kit (texture id, H264 profile, connect guard,
# unregister stream, encoder FPS diagnostics).
# Correr na raiz do projeto: .\tool\patch_haishin_kit.ps1

$ErrorActionPreference = "Stop"

if ($env:PUB_CACHE -and (Test-Path $env:PUB_CACHE)) {
  $pubCache = $env:PUB_CACHE
} elseif (Test-Path "$env:LOCALAPPDATA\Pub\Cache") {
  $pubCache = "$env:LOCALAPPDATA\Pub\Cache"
} elseif (Test-Path "$env:USERPROFILE\.pub-cache") {
  $pubCache = "$env:USERPROFILE\.pub-cache"
} else {
  Write-Host "Pub Cache não encontrado. Define PUB_CACHE ou instala o Flutter."
  exit 1
}

Write-Host "Pub Cache: $pubCache"

$handlers = Get-ChildItem -Path (Join-Path $pubCache "hosted\pub.dev") -Recurse -Filter "StreamSessionHandler.kt" -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match "haishin_kit-" }

$plugins = Get-ChildItem -Path (Join-Path $pubCache "hosted\pub.dev") -Recurse -Filter "HaishinKitPlugin.kt" -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match "haishin_kit-" }

if (-not $handlers -or $handlers.Count -eq 0) {
  Write-Host "StreamSessionHandler.kt (haishin_kit) não encontrado. Corre: flutter pub get"
  exit 1
}

foreach ($handler in $handlers) {
  $content = Get-Content $handler.FullName -Raw
  $changed = $false

  if ($content -match 'ProfileLevel\.valueOf\(it\)') {
    $content = $content -replace '\(source\["profileLevel"\] as\? String\)\?\.let \{', '(source["profileLevel"] as? String)?.let { profileLevelName ->'
    $content = $content -replace 'ProfileLevel\.valueOf\(it\)', 'ProfileLevel.entries.find { it.rawValue == profileLevelName } ?: ProfileLevel.H264Baseline31'
    $changed = $true
  }

  if ($content -notmatch 'texture\.imageExtent = android\.util\.Size') {
    $content = $content -replace '(session\?\.stream\?\.registerOutput\(texture\))\s*\r?\n(\s+)result\.success\(texture\.id\)',
@'
$1
$2texture.imageExtent = android.util.Size(640, 360)
$2result.success(texture.id)
'@
    $changed = $true
  }

  if ($content -match '"\$TAG#connect"' -and $content -notmatch 'connect crash guard') {
    $oldConnect = @'
            "$TAG#connect" -> {
                scope.launch {
                    session?.connect()?.onSuccess {
                        result.success(null)
                    }?.onFailure {
                        result.error(CONNECT_FAILED, null, null)
                    }
                }
            }
'@
    $newConnect = @'
            "$TAG#connect" -> {
                // connect crash guard
                scope.launch {
                    try {
                        val deferred = session?.connect()
                        if (deferred == null) {
                            result.error(CONNECT_FAILED, "session.connect() null", null)
                            return@launch
                        }
                        deferred.onSuccess {
                            result.success(null)
                        }.onFailure { err ->
                            result.error(CONNECT_FAILED, err.message, null)
                        }
                    } catch (t: Throwable) {
                        Log.e(TAG, "connect exception", t)
                        result.error(CONNECT_FAILED, t.message, null)
                    }
                }
            }
'@
    if ($content.Contains($oldConnect)) {
      $content = $content.Replace($oldConnect, $newConnect)
      $changed = $true
    }
  }

  if ($content -notmatch 'encoder_video_fps') {
    if ($content -notmatch 'import com\.haishinkit\.rtmp\.RtmpStream') {
      $content = $content -replace 'import com\.haishinkit\.stream\.StreamSession', "import com.haishinkit.rtmp.RtmpConnection`r`nimport com.haishinkit.rtmp.RtmpStream`r`nimport com.haishinkit.stream.StreamSession"
      $changed = $true
    }
    if ($content -notmatch 'lastReportedEncoderFps') {
      $content = $content -replace 'private var readyStateOpen = false', "private var readyStateOpen = false`r`n    private var lastReportedEncoderFps = -1"
      $changed = $true
    }
    $oldReady = @'
            if (readyStateOpen) {
                emitDiagnostic("video_track_published", "readyState=open")
            }
        }?.launchIn(scope)
    }
'@
    $newReady = @'
            if (readyStateOpen) {
                emitDiagnostic("rtmp_session_open", "readyState=open")
            }
        }?.launchIn(scope)
        (session?.stream as? RtmpStream)?.listener = object : RtmpStream.Listener {
            override fun onStatics(stream: RtmpStream, connection: RtmpConnection) {
                val fps = stream.currentFPS
                if (fps != lastReportedEncoderFps) {
                    lastReportedEncoderFps = fps
                    emitDiagnostic("encoder_video_fps", "fps=$fps")
                }
                if (fps > 0 && !firstEncoderPacketLogged) {
                    firstEncoderPacketLogged = true
                    emitDiagnostic("encoder_producing_frames", "fps=$fps")
                }
            }
        }
    }
'@
    if ($content.Contains($oldReady)) {
      $content = $content.Replace($oldReady, $newReady)
      $changed = $true
    } elseif ($content -match 'RtmpStream\.Listener \{ stream') {
      $content = $content -replace '(?s)\(session\?\.stream as\? RtmpStream\)\?\.listener = RtmpStream\.Listener \{.*?\}\s*\}', @'
(session?.stream as? RtmpStream)?.listener = object : RtmpStream.Listener {
            override fun onStatics(stream: RtmpStream, connection: RtmpConnection) {
                val fps = stream.currentFPS
                if (fps != lastReportedEncoderFps) {
                    lastReportedEncoderFps = fps
                    emitDiagnostic("encoder_video_fps", "fps=$fps")
                }
                if (fps > 0 && !firstEncoderPacketLogged) {
                    firstEncoderPacketLogged = true
                    emitDiagnostic("encoder_producing_frames", "fps=$fps")
                }
            }
        }
'@
      $changed = $true
    } elseif ($content -match 'video_track_published' -and $content -notmatch 'encoder_video_fps') {
      $content = $content -replace 'emitDiagnostic\("video_track_published"', 'emitDiagnostic("rtmp_session_open"'
      $changed = $true
    }
  }

  if ($changed) {
    Set-Content -Path $handler.FullName -Value $content -NoNewline
    Write-Host "Patch aplicado: $($handler.FullName)"
  } else {
    Write-Host "Patch já presente: $($handler.FullName)"
  }
}

foreach ($plugin in $plugins) {
  $content = Get-Content $plugin.FullName -Raw
  if ($content -match 'unregisterStreamOutput') {
    Write-Host "Patch já presente: $($plugin.FullName)"
    continue
  }
  $needle = @'
            "getVideoSources" -> {
                val sources = deviceManager.getDeviceList()
                result.success(json.encodeToString(sources))
            }

            else -> {
'@
  $replacement = @'
            "getVideoSources" -> {
                val sources = deviceManager.getDeviceList()
                result.success(json.encodeToString(sources))
            }

            "unregisterStreamOutput" -> {
                val sessionMemory = call.argument<Int>("memory")
                if (sessionMemory == null) {
                    result.error(INVALID_ARGUMENTS, "memory is null", null)
                } else {
                    val handler = handlers[sessionMemory] as? StreamSessionHandler
                    val stream = handler?.session?.stream
                    if (stream != null) {
                        unregisterOutput(stream)
                        result.success(null)
                    } else {
                        result.error(ILLEGAL_STATE, "session stream not found", null)
                    }
                }
            }

            else -> {
'@
  if ($content.Contains($needle)) {
    $content = $content.Replace($needle, $replacement)
    Set-Content -Path $plugin.FullName -Value $content -NoNewline
    Write-Host "Patch aplicado: $($plugin.FullName)"
  } else {
    Write-Host "HaishinKitPlugin.kt: bloco getVideoSources não encontrado — verifica manualmente."
  }
}

Write-Host "Concluído."

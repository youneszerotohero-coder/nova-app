// NOVA PC app video surface (owner decision 2026-10-29).
//
// The Windows host (protected_player.cpp) loads this page in a WebView2 that
// sits in its own window, behind a transparent hole of the Flutter app: the
// app draws the controls and the moving watermark over it, exactly as on the
// phone. Same contract as Android's ProtectedPlayerView.kt:
//
//   window.nova.load(params)     manifest, clear, license, token, startMs,
//                                maxHeight, live, keySystem, robustness
//   window.nova.command({method, args})   play, pause, seekTo{ms},
//                                seekToLiveEdge, setSpeed{speed},
//                                setVolume{volume}, setQuality{height},
//                                renewToken{token}, softwareFallback, setFill{on},
//                                release
//   window.nova.probe()          which PlayReady level this PC has
//
// Messages to the host are strings: "ready", "probe:3000|2000|none",
// "hwfail" (hardware PlayReady failed here: software from now on) and
// "event:<json>" (forwarded as is to Dart: state, playing, position,
// firstFrame, tracks, error, drm; a `drm` event with `fallback: true` is a
// switch to software in this player).
'use strict';

(function () {
  const host = window.chrome && window.chrome.webview;
  const send = (message) => { if (host) host.postMessage(message); };
  const emit = (event) => send('event:' + JSON.stringify(event));

  const PLAYREADY = 'com.microsoft.playready.recommendation';
  const PLAYREADY_HARDWARE = 'com.microsoft.playready.recommendation.3000';
  const LICENSE = () => shaka.net.NetworkingEngine.RequestType.LICENSE;
  // Hardware PlayReady that shows no picture within this time, although
  // media is buffered, is retried in software (D-147: frames decoded,
  // picture black; Windows output path).
  const HARDWARE_START_TIMEOUT_MS = 12000;
  // Lives through Media Foundation: no playback-rate catch-up (D-136); a
  // jump to the edge when more than this far behind, at most every 30 s.
  const LIVE_SEEK_CATCHUP_SECONDS = 6;
  const LIVE_EDGE_JUMP_MIN_INTERVAL_MS = 30000;

  const video = document.getElementById('video');
  let player = null;
  let params = null;
  let token = '';
  let keySystem = PLAYREADY;
  let robustness = '2000';
  let licenseStatus = 0;
  let firstFrame = false;
  let startTime = 0;
  let ticker = 0;
  let startWatch = 0;
  let lastEdgeJump = 0;
  let released = false;

  // Capability ---------------------------------------------------------

  const capability = (level) => [{
    initDataTypes: ['cenc'],
    videoCapabilities: [{ contentType: 'video/mp4; codecs="avc1.4d401f"', robustness: level }],
    audioCapabilities: [{ contentType: 'audio/mp4; codecs="mp4a.40.2"', robustness: '' }],
    distinctiveIdentifier: 'optional',
    persistentState: 'optional',
    sessionTypes: ['temporary'],
  }];

  async function granted(system, level) {
    try {
      const access = await navigator.requestMediaKeySystemAccess(system, capability(level));
      await access.createMediaKeys();
      return true;
    } catch (error) {
      return false;
    }
  }

  async function probe() {
    let level = 'none';
    if (navigator.requestMediaKeySystemAccess) {
      if (await granted(PLAYREADY_HARDWARE, '3000')) level = '3000';
      else if (await granted(PLAYREADY, '2000')) level = '2000';
    }
    send('probe:' + level);
  }

  // Playback -----------------------------------------------------------

  function configure(p) {
    const live = p.live === true;
    const retry = { maxAttempts: 2, baseDelay: 500, backoffFactor: 2, fuzzFactor: 0.2, timeout: 12000, stallTimeout: 5000, connectionTimeout: 10000 };
    const config = {
      abr: { enabled: true, useNetworkInformation: false, defaultBandwidthEstimate: live ? 1000000 : 900000, restrictToElementSize: false, clearBufferSwitch: false },
      restrictions: typeof p.maxHeight === 'number' && p.maxHeight > 0 ? { maxHeight: p.maxHeight } : {},
      manifest: { retryParameters: retry },
      streaming: { retryParameters: Object.assign({}, retry, { maxAttempts: 3, timeout: 15000 }), rebufferingGoal: 2, bufferingGoal: live ? 14 : 18, bufferBehind: live ? 12 : 30, lowLatencyMode: false },
    };
    if (live) {
      config.manifest.defaultPresentationDelay = 12;
      config.abr.switchInterval = 6;
      config.abr.bandwidthUpgradeTarget = 0.85;
      config.abr.bandwidthDowngradeTarget = 0.95;
      // Clear stream: Android's 1.08× catch-up to 12 s behind. DRM goes
      // through Media Foundation, where rate changes stall (D-136).
      config.streaming.liveSync = p.clear
        ? { enabled: true, targetLatency: 12, targetLatencyTolerance: 2, maxPlaybackRate: 1.08, minPlaybackRate: 1, panicMode: false }
        : { enabled: false };
    }
    if (!p.clear) {
      config.drm = {
        servers: { 'com.microsoft.playready': p.license },
        keySystemsMapping: { 'com.microsoft.playready': keySystem },
        preferredKeySystems: [keySystem],
        advanced: { 'com.microsoft.playready': { videoRobustness: [robustness], audioRobustness: [] } },
        retryParameters: { maxAttempts: 2, baseDelay: 500, backoffFactor: 2, fuzzFactor: 0.2, timeout: 12000 },
      };
    }
    player.configure(config);
  }

  async function start(p) {
    clearTimeout(startWatch);
    firstFrame = false;
    licenseStatus = 0;
    if (player) {
      try { await player.destroy(); } catch (error) { /* replaced below */ }
    }
    if (released) return;
    player = new shaka.Player();
    await player.attach(video);
    configure(p);
    const networking = player.getNetworkingEngine();
    networking.registerRequestFilter((type, request) => {
      // The Axinom entitlement on every licence request, as on the website.
      if (type === LICENSE() && token) request.headers['X-AxDRM-Message'] = token;
    });
    networking.registerResponseFilter((type, response) => {
      if (type === LICENSE()) licenseStatus = response.status || 200;
    });
    player.addEventListener('error', (event) => onError(event.detail));
    player.addEventListener('buffering', (event) => {
      if (event.buffering) emit({ event: 'state', state: 'buffering' });
      else if (!video.ended) emit({ event: 'state', state: 'ready' });
    });
    player.addEventListener('trackschanged', emitTracks);
    player.addEventListener('variantchanged', emitTracks);
    player.addEventListener('adaptation', emitTracks);

    startTime = p.live ? 0 : Math.max(0, (Number(p.startMs) || 0) / 1000);
    emit({ event: 'state', state: 'buffering' });
    await player.load(p.manifest, p.live ? null : startTime, p.clear ? 'application/x-mpegurl' : 'application/dash+xml');
    if (released) return;
    emitTracks();
    emit({ event: 'drm', keySystem: p.clear ? null : keySystem, robustness: p.clear ? null : robustness });
    if (!p.clear && robustness === '3000') watchHardwareStart();
    try {
      await video.play();
    } catch (error) {
      // Autoplay refused: the app's play button starts it.
      emit({ event: 'playing', value: false });
    }
  }

  async function load(p) {
    params = p;
    token = typeof p.token === 'string' ? p.token : '';
    keySystem = typeof p.keySystem === 'string' && p.keySystem ? p.keySystem : PLAYREADY;
    robustness = typeof p.robustness === 'string' && p.robustness ? p.robustness : '2000';
    if (robustness !== '3000' && keySystem === PLAYREADY_HARDWARE) keySystem = PLAYREADY;
    shaka.polyfill.installAll();
    if (!shaka.Player.isBrowserSupported()) {
      return emit({ event: 'error', category: 'capability', kind: 'other', code: 0, licenseStatus: 0, message: 'UNSUPPORTED' });
    }
    ticker = setInterval(tick, 500);
    start(p).catch(onError);
  }

  // Hardware PlayReady failed on this PC: the same entitlement plays in
  // software (the PC app's licence allows SL2000), so the Student sees the
  // video instead of an error, and later videos start in software.
  function hardwareFailed() {
    if (released || params === null || params.clear || robustness !== '3000') return false;
    send('hwfail');
    keySystem = PLAYREADY;
    robustness = '2000';
    // The app's Live watch starts counting again for the software start.
    emit({ event: 'drm', keySystem, robustness, fallback: true });
    const resume = Object.assign({}, params, { startMs: Math.round((video.currentTime || startTime) * 1000) });
    start(resume).catch(onError);
    return true;
  }

  function watchHardwareStart() {
    clearTimeout(startWatch);
    startWatch = setTimeout(() => {
      if (firstFrame || released || video.paused) return;
      if (bufferedAhead() >= 2) hardwareFailed();
    }, HARDWARE_START_TIMEOUT_MS);
  }

  // Events --------------------------------------------------------------

  function emitTracks() {
    if (!player) return;
    const heights = [...new Set(player.getVariantTracks().map((track) => track.height).filter((height) => height > 0))]
      .sort((a, b) => b - a);
    emit({ event: 'tracks', heights });
  }

  function bufferedAhead() {
    const ranges = video.buffered;
    for (let i = 0; i < ranges.length; i += 1) {
      if (ranges.start(i) <= video.currentTime + 0.25 && ranges.end(i) >= video.currentTime) return ranges.end(i) - video.currentTime;
    }
    return 0;
  }

  function markFirstFrame() {
    if (firstFrame || released) return;
    firstFrame = true;
    pictureSize = pageSize();
    clearTimeout(startWatch);
    emit({ event: 'firstFrame' });
  }

  // Picture size --------------------------------------------------------

  // D-193 (owner report: full screen showed the video in a rectangle, the
  // rest black, until a quality change): Media Foundation (PlayReady) keeps
  // drawing at the size the picture had before the window grew. Once a size
  // change settles, the playing rendition is fed again from the current
  // second, as a quality change does (a short rebuffer). Clear streams do not
  // go through Media Foundation and are left alone.
  const RESIZE_SETTLE_MS = 350;
  const RESIZE_MIN_CHANGE = 0.05;
  let pictureSize = null;
  let resizeTimer = 0;

  const pageSize = () => ({ width: window.innerWidth, height: window.innerHeight });

  function refreshPicture() {
    const before = pictureSize;
    const now = pageSize();
    if (!firstFrame || released || !player || params === null || params.clear || before === null) return;
    pictureSize = now;
    const changed = (a, b) => Math.abs(a - b) > RESIZE_MIN_CHANGE * Math.max(1, a);
    if (!changed(before.width, now.width) && !changed(before.height, now.height)) return;
    const active = player.getVariantTracks().find((track) => track.active);
    if (!active) return;
    const abr = player.getConfiguration().abr.enabled;
    player.selectVariantTrack(active, true, 0);
    if (abr) player.configure({ abr: { enabled: true } });
  }

  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(refreshPicture, RESIZE_SETTLE_MS);
  });

  function tick() {
    if (released || !player) return;
    const live = params !== null && params.live === true;
    const position = video.currentTime || 0;
    let offset = -1;
    if (live) {
      const range = player.seekRange();
      if (Number.isFinite(range.end)) {
        offset = Math.max(0, range.end - position);
        if (!params.clear && offset > LIVE_SEEK_CATCHUP_SECONDS && !video.paused && Date.now() - lastEdgeJump >= LIVE_EDGE_JUMP_MIN_INTERVAL_MS) {
          lastEdgeJump = Date.now();
          video.currentTime = range.end;
        }
      }
    }
    // Frames presented through Media Foundation never reach the page: the
    // first frame is the decoder's first frame with the playhead moving.
    if (!firstFrame && !video.paused && position - startTime >= 0.5) {
      const quality = video.getVideoPlaybackQuality ? video.getVideoPlaybackQuality() : null;
      if (!quality || quality.totalVideoFrames > 0 || position - startTime >= 1.5) markFirstFrame();
    }
    emit({
      event: 'position',
      position: Math.round(position * 1000),
      duration: !live && Number.isFinite(video.duration) ? Math.round(video.duration * 1000) : 0,
      buffered: Math.round((position + bufferedAhead()) * 1000),
      liveOffset: offset < 0 ? -1 : Math.round(offset * 1000),
    });
  }

  video.addEventListener('playing', () => emit({ event: 'playing', value: true }));
  video.addEventListener('pause', () => emit({ event: 'playing', value: false }));
  video.addEventListener('waiting', () => emit({ event: 'state', state: 'buffering' }));
  video.addEventListener('canplay', () => emit({ event: 'state', state: 'ready' }));
  video.addEventListener('ended', () => {
    emit({ event: 'playing', value: false });
    emit({ event: 'state', state: 'ended' });
  });
  if (video.requestVideoFrameCallback) video.requestVideoFrameCallback(() => markFirstFrame());

  // Same failure categories as the Android player and the website
  // (protected-playback.ts): capability, drm_init, license, expired,
  // output, decode, timeout, delivery.
  function category(code) {
    if (code === 6001 || code === 6020 || code === 4032) return 'capability';
    if (code === 6002 || code === 6003 || code === 6005 || code === 6006) return 'drm_init';
    if (code === 6014) return 'expired';
    if (code === 6018 || code === 6019 || code === 4012) return 'output';
    if (code >= 6000 && code < 7000) return 'license';
    if (code === 1003) return 'timeout';
    if (code >= 3000 && code < 5000) return 'decode';
    return 'delivery';
  }

  function nestedStatus(error) {
    const nested = error && Array.isArray(error.data) ? error.data[0] : null;
    if (nested && Array.isArray(nested.data) && typeof nested.data[1] === 'number') return nested.data[1];
    return 0;
  }

  function onError(error) {
    if (released || !error) return;
    const code = typeof error.code === 'number' ? error.code : 0;
    if (code === 7000) return; // LOAD_INTERRUPTED: replaced by a newer load.
    const recoverable = shaka.util && shaka.util.Error && error.severity === shaka.util.Error.Severity.RECOVERABLE;
    if (recoverable) return;
    const kind = (code >= 6000 && code < 7000) || code === 4012 ? 'drm' : (code >= 3000 && code < 4000 ? 'decoder' : 'other');
    // A hardware DRM or decoder failure before the picture: software next.
    if (!firstFrame && (kind === 'drm' || kind === 'decoder') && hardwareFailed()) return;
    if (kind === 'drm') licenseStatus = nestedStatus(error) || licenseStatus;
    clearTimeout(startWatch);
    emit({ event: 'error', category: category(code), kind, code, licenseStatus, message: String(code) });
  }

  // Commands ------------------------------------------------------------

  async function setQuality(height) {
    if (!player) return;
    if (!(height > 0)) {
      player.configure({ abr: { enabled: true } });
      return;
    }
    const track = player.getVariantTracks().filter((candidate) => candidate.height === height)
      .sort((left, right) => right.bandwidth - left.bandwidth)[0];
    if (!track) return;
    player.configure({ abr: { enabled: false } });
    player.selectVariantTrack(track, true, 2);
  }

  async function release() {
    released = true;
    clearInterval(ticker);
    clearTimeout(resizeTimer);
    clearTimeout(startWatch);
    try { video.pause(); } catch (error) { /* nothing to stop */ }
    if (player) {
      try { await player.destroy(); } catch (error) { /* already gone */ }
      player = null;
    }
  }

  function command(message) {
    const method = message && message.method;
    const args = (message && message.args) || {};
    if (released && method !== 'release') return;
    switch (method) {
      case 'play': video.play().catch(() => emit({ event: 'playing', value: false })); break;
      case 'pause': video.pause(); break;
      case 'seekTo': video.currentTime = Math.max(0, (Number(args.ms) || 0) / 1000); break;
      case 'seekToLiveEdge': if (player) { const range = player.seekRange(); if (Number.isFinite(range.end)) video.currentTime = range.end; } break;
      case 'setSpeed': video.playbackRate = Number(args.speed) || 1; break;
      case 'setVolume': video.volume = Math.min(1, Math.max(0, Number(args.volume))); break;
      case 'setQuality': setQuality(Number(args.height) || 0); break;
      // Owner 2026-11-21: in full screen the picture fills the window (cropped, never stretched).
      case 'setFill': video.style.objectFit = args.on === true ? 'cover' : 'contain'; break;
      // A renewed Live entitlement: future licence requests only.
      case 'renewToken': token = typeof args.token === 'string' ? args.token : token; break;
      // The app saw no picture on hardware PlayReady (2026-11-19, D-212):
      // software now, without waiting for this page's own start watch.
      case 'softwareFallback': hardwareFailed(); break;
      case 'release': release(); break;
      default: break;
    }
  }

  window.nova = { load, command, probe };
  // Keyboard and mouse belong to the app: nothing here takes focus.
  document.addEventListener('contextmenu', (event) => event.preventDefault());
  send('ready');
})();

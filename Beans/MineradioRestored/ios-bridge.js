(function(){
  window.__mineradioIOS = true;
  document.documentElement.classList.add('ios-shell-root');
  window.addEventListener('error', function(event){
    try { window.webkit.messageHandlers.iosBridge.postMessage({ type:'error', message:String(event.message || ''), source:String(event.filename || ''), line:event.lineno || 0 }); } catch(e) {}
  });
  window.addEventListener('unhandledrejection', function(event){
    try { window.webkit.messageHandlers.iosBridge.postMessage({ type:'rejection', message:String(event.reason && (event.reason.message || event.reason) || '') }); } catch(e) {}
  });
  try {
    localStorage.setItem('mineradio-diy-player-mode-v1', '1');
    localStorage.setItem('mineradio-visual-guide-seen-v1', '1');
  } catch (e) {}

  window.desktopWindow = {
    isDesktop: false,
    isIOS: true,
    platform: 'ios',
    getLoginItemSettings: function(){ return Promise.resolve({ openAtLogin: false, unavailable: 'ios' }); },
    setLoginItemSettings: function(){ return Promise.resolve({ ok: false, unavailable: 'ios' }); },
    minimize: function(){ return Promise.resolve({ ok: false, unavailable: 'ios' }); },
    toggleMaximize: function(){ return Promise.resolve({ ok: false, unavailable: 'ios' }); },
    getWindowState: function(){ return Promise.resolve({ isFullScreen: true, isPrimaryDisplay: true }); },
    getState: function(){ return Promise.resolve({ isFullScreen: true, isPrimaryDisplay: true, platform: 'ios' }); },
    onWindowState: function(){ return function(){}; },
    onStateChange: function(){ return function(){}; },
    toggleFullscreen: function(){ return Promise.resolve({ ok: true }); },
    exitFullscreenWindowed: function(){ return Promise.resolve({ ok: true }); },
    close: function(){ return Promise.resolve({ ok: false, unavailable: 'ios' }); },
    setDesktopLyricsEnabled: function(){ return Promise.resolve({ ok: false, unavailable: 'ios' }); },
    updateDesktopLyrics: function(){ return Promise.resolve({ ok: false, unavailable: 'ios' }); },
    onDesktopLyricsLockState: function(){ return function(){}; },
    onDesktopLyricsEnabledState: function(){ return function(){}; },
    setWallpaperMode: function(){ return Promise.resolve({ ok: false, unavailable: 'ios' }); },
    updateWallpaperMode: function(){ return Promise.resolve({ ok: false, unavailable: 'ios' }); },
    clearNeteaseMusicLogin: function(){ return fetch('/api/logout').then(function(r){ return r.json(); }).catch(function(){ return { ok:true }; }); },
    clearQQMusicLogin: function(){ return fetch('/api/qq/logout').then(function(r){ return r.json(); }).catch(function(){ return { ok:true }; }); },
    clearKugouMusicLogin: function(){ return fetch('/api/kugou/logout').then(function(r){ return r.json(); }).catch(function(){ return { ok:true }; }); },
    openNeteaseMusicLogin: null,
    openQQMusicLogin: function(){ return nativeIOSRequest('qq-web-login', {}).then(function(r){ return (r && r.data) || {}; }); },
    openKugouMusicLogin: function(){ return nativeIOSRequest('kugou-web-login', {}).then(function(r){ return (r && r.data) || {}; }); },
    openUpdateInstaller: function(){ return Promise.resolve({ ok: false, unavailable: 'ios' }); },
    restartApp: function(){ return Promise.resolve({ ok: false, unavailable: 'ios' }); },
    configureGlobalHotkeys: function(){ return Promise.resolve({ ok: false, unavailable: 'ios' }); },
    exportJsonFile: function(payload){ return Promise.resolve({ ok: false, unavailable: 'ios', payload: payload || {} }); },
    importJsonFile: function(){ return Promise.resolve({ ok: false, unavailable: 'ios' }); },
    onGlobalHotkey: function(){ return function(){}; }
  };

  var IOS_STATE_KEY = 'mineradio-ios-native-api-state-v2';
  var IOS_SONG_CACHE_KEY = 'mineradio-ios-native-song-cache-v2';
  var IOS_DESKTOP_API_ORIGIN = '';
  var lyrics = '[00:00.00]这首歌暂无在线歌词\n[00:08.00]iOS 版会继续保持播放器、粒子和控制台同步\n[00:18.00]正在播放官方试听音源\n[00:28.00]完整歌词可在后续接入授权歌词源后同步';
  var originalFetch = window.fetch ? window.fetch.bind(window) : null;
  var nativeRequestSeq = 0;
  var nativePending = {};

  window.__mineradioResolveNativeAPI = function(id, payload) {
    var pending = nativePending[id];
    if (!pending) return;
    delete nativePending[id];
    clearTimeout(pending.timer);
    if (payload && payload.ok === false) pending.reject(new Error(payload.error || 'NATIVE_API_FAILED'));
    else pending.resolve(payload || {});
  };

  function nativeIOSRequest(action, payload) {
    return new Promise(function(resolve, reject) {
      if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.iosBridge) {
        reject(new Error('NATIVE_BRIDGE_UNAVAILABLE'));
        return;
      }
      var id = 'ios-native-' + (++nativeRequestSeq) + '-' + Date.now();
      nativePending[id] = {
        resolve: resolve,
        reject: reject,
        timer: setTimeout(function() {
          if (!nativePending[id]) return;
          delete nativePending[id];
          reject(new Error('NATIVE_API_TIMEOUT'));
        }, 14000)
      };
      try {
        window.webkit.messageHandlers.iosBridge.postMessage({ type:'native-api', id:id, action:action, payload:payload || {} });
      } catch (e) {
        clearTimeout(nativePending[id].timer);
        delete nativePending[id];
        reject(e);
      }
    });
  }

  var lastNeteaseQr = null;
  function neteaseNative(action, payload) {
    payload = payload || {};
    var desktop = neteaseDesktopAPI(action, payload);
    if (desktop) {
      return desktop.catch(function(error) {
        try {
          window.webkit.messageHandlers.iosBridge.postMessage({
            type:'desktop-api-fallback',
            action:action,
            message:String(error && error.message || error)
          });
        } catch (_) {}
        return nativeIOSRequest(action, payload).then(function(res){ return (res && res.data) || {}; });
      });
    }
    return nativeIOSRequest(action, payload).then(function(res){ return (res && res.data) || {}; });
  }
  try { window.__mineradioNativeReq = nativeIOSRequest; } catch (e) {}
  function jsonResponse(body) {
    return new Response(JSON.stringify(body), { status:200, headers:{ 'Content-Type':'application/json' } });
  }
  function neteaseResponse(promise, fallback) {
    return promise.then(jsonResponse).catch(function(e){
      var f = (typeof fallback === 'function') ? fallback(e) : (fallback || {});
      return Promise.resolve(f).then(jsonResponse);
    });
  }

  function desktopAPIJSON(path, options) {
    if (!originalFetch) return Promise.reject(new Error('FETCH_UNAVAILABLE'));
    if (!IOS_DESKTOP_API_ORIGIN) return Promise.reject(new Error('DESKTOP_API_DISABLED'));
    var target = IOS_DESKTOP_API_ORIGIN + path;
    var opts = Object.assign({ cache:'no-store' }, options || {});
    opts.headers = Object.assign({ 'Accept':'application/json' }, opts.headers || {});
    return originalFetch(target, opts).then(function(resp) {
      if (!resp || !resp.ok) throw new Error('DESKTOP_API_HTTP_' + (resp ? resp.status : 0));
      return resp.json();
    }).then(normalizeDesktopMediaPayload);
  }

  function qs(params) {
    var parts = [];
    Object.keys(params || {}).forEach(function(key) {
      var value = params[key];
      if (value === undefined || value === null || value === '') return;
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(String(value)));
    });
    return parts.length ? ('?' + parts.join('&')) : '';
  }

  function neteaseDesktopAPI(action, payload) {
    if (!originalFetch) return null;
    switch (action) {
    case 'netease-search':
      return desktopAPIJSON('/api/search' + qs({ keywords:payload.keywords || payload.term || '', limit:payload.limit || 20 }));
    case 'netease-song-url':
      return desktopAPIJSON('/api/song/url' + qs({ id:payload.id || '', quality:payload.quality || payload.level || '' }));
    case 'netease-lyric':
      return desktopAPIJSON('/api/lyric' + qs({ id:payload.id || '' }));
    case 'netease-login-qr-key':
      return desktopAPIJSON('/api/login/qr/key').then(function(keyData) {
        var key = keyData && keyData.key ? String(keyData.key) : '';
        if (!key) return keyData || {};
        return desktopAPIJSON('/api/login/qr/create' + qs({ key:key })).then(function(qrData) {
          return { key:key, img:(qrData && qrData.img) || '', qrurl:(qrData && (qrData.url || qrData.qrurl)) || '' };
        });
      });
    case 'netease-login-qr-check':
      return desktopAPIJSON('/api/login/qr/check' + qs({ key:payload.key || '' }));
    case 'netease-login-status':
      return desktopAPIJSON('/api/login/status?t=' + Date.now());
    case 'netease-login-cookie':
      return desktopAPIJSON('/api/login/cookie', {
        method:'POST',
        headers:{ 'Content-Type':'application/json' },
        body:JSON.stringify({ cookie:payload.cookie || '' })
      });
    case 'netease-logout':
      return desktopAPIJSON('/api/logout');
    case 'netease-user-playlists':
      return desktopAPIJSON('/api/user/playlists');
    case 'netease-playlist-tracks':
      return desktopAPIJSON('/api/playlist/tracks' + qs({ id:payload.id || '' }));
    case 'netease-like':
      return desktopAPIJSON('/api/song/like' + qs({ id:payload.id || '', like:payload.like !== false }));
    case 'netease-likelist':
      return Promise.resolve({ ids:[] });
    default:
      return null;
    }
  }

  function iosHttpsMediaUrl(value) {
    var text = String(value || '');
    if (!/^http:\/\//i.test(text)) return value;
    try {
      var u = new URL(text);
      if (/(^|\.)music\.126\.net$/i.test(u.hostname)) {
        u.protocol = 'https:';
        return u.href;
      }
    } catch (e) {}
    return value;
  }

  function normalizeDesktopMediaPayload(value) {
    if (typeof value === 'string') return iosHttpsMediaUrl(value);
    if (!value || typeof value !== 'object') return value;
    if (Array.isArray(value)) return value.map(normalizeDesktopMediaPayload);
    Object.keys(value).forEach(function(key) {
      value[key] = normalizeDesktopMediaPayload(value[key]);
    });
    return value;
  }

  function decodeProxyUrl(value) {
    var text = String(value || '');
    if (!text) return text;
    try {
      var u = new URL(text, location.href);
      if (u.pathname === '/api/audio' || u.pathname === '/api/cover') {
        var target = u.searchParams.get('url');
        if (target) return iosHttpsMediaUrl(target);
      }
    } catch (e) {}
    return iosHttpsMediaUrl(text);
  }

  try {
    var mediaSrc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
    if (mediaSrc && mediaSrc.set && mediaSrc.get) {
      Object.defineProperty(HTMLMediaElement.prototype, 'src', {
        configurable: true,
        enumerable: mediaSrc.enumerable,
        get: function(){ return mediaSrc.get.call(this); },
        set: function(value){ mediaSrc.set.call(this, decodeProxyUrl(value)); }
      });
    }
  } catch (e) {}

  function readJSONStorage(key, fallback) {
    try {
      var raw = localStorage.getItem(key);
      return raw ? JSON.parse(raw) : fallback;
    } catch (e) {
      return fallback;
    }
  }

  function writeJSONStorage(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch (e) {}
  }

  function emptyState() {
    return {
      liked: {},
      playlists: [
        { id:'ios-liked', name:'我喜欢的音乐', specialType:5, subscribed:false, tracks:[] },
        { id:'ios-favorites', name:'iOS 收藏歌单', specialType:0, subscribed:false, tracks:[] }
      ]
    };
  }

  function readIOSState() {
    var state = readJSONStorage(IOS_STATE_KEY, null) || emptyState();
    if (!state.liked) state.liked = {};
    if (!Array.isArray(state.playlists)) state.playlists = emptyState().playlists;
    if (!state.playlists.some(function(p){ return String(p.id) === 'ios-liked'; })) {
      state.playlists.unshift({ id:'ios-liked', name:'我喜欢的音乐', specialType:5, subscribed:false, tracks:[] });
    }
    return state;
  }

  function saveIOSState(state) {
    writeJSONStorage(IOS_STATE_KEY, state || emptyState());
  }

  function readSongCache() {
    return readJSONStorage(IOS_SONG_CACHE_KEY, {}) || {};
  }

  function saveSongCache(cache) {
    writeJSONStorage(IOS_SONG_CACHE_KEY, cache || {});
  }

  function rememberSong(song) {
    if (!song || !song.id) return song;
    var cache = readSongCache();
    cache[String(song.id)] = song;
    if (song.trackId) cache[String(song.trackId)] = song;
    if (song.mid) cache[String(song.mid)] = song;
    if (song.artistId) cache['artist:' + String(song.artistId)] = song;
    saveSongCache(cache);
    return song;
  }

  function rememberSongs(list) {
    var cache = readSongCache();
    (list || []).forEach(function(song) {
      if (!song || !song.id) return;
      cache[String(song.id)] = song;
      if (song.trackId) cache[String(song.trackId)] = song;
      if (song.mid) cache[String(song.mid)] = song;
      if (song.artistId) cache['artist:' + String(song.artistId)] = song;
    });
    saveSongCache(cache);
    return list || [];
  }

  function cachedSong(id) {
    var cache = readSongCache();
    return cache[String(id || '')] || null;
  }

  function appleCover(url, size) {
    url = String(url || '');
    if (!url) return '';
    size = size || 600;
    return url.replace(/\/\d+x\d+bb\.(jpg|png)$/i, '/' + size + 'x' + size + 'bb.$1');
  }

  function mapItunesTrack(track, provider) {
    provider = provider || 'apple';
    var trackId = String(track.trackId || track.collectionId || '');
    var idPrefix = provider === 'qq' ? 'ios-qq-' : (provider === 'netease' ? 'ios-ne-' : 'ios-apple-');
    var id = idPrefix + trackId;
    var song = {
      provider: provider,
      source: provider,
      type: 'song',
      id: id,
      trackId: trackId,
      mid: provider === 'qq' ? id : '',
      songmid: provider === 'qq' ? id : '',
      name: track.trackName || track.collectionName || '',
      title: track.trackName || track.collectionName || '',
      artist: track.artistName || '',
      artists: [{ name: track.artistName || '', id: track.artistId || '' }],
      artistId: track.artistId || '',
      album: track.collectionName || '',
      cover: appleCover(track.artworkUrl100 || track.artworkUrl60 || '', 600),
      duration: track.trackTimeMillis || 30000,
      previewUrl: track.previewUrl || '',
      playable: !!track.previewUrl,
      fee: 0,
      trial: true,
      quality: '30s 试听'
    };
    return rememberSong(song);
  }

  function fallbackSongs(provider) {
    provider = provider || 'apple';
    return rememberSongs([
      { provider:provider, source:provider, type:'song', id:'ios-fallback-night-radio-' + provider, trackId:'fallback-1-' + provider, name:'Night Radio', title:'Night Radio', artist:'Mineradio', artists:[{name:'Mineradio'}], album:'Voice of the Heart', cover:'', duration:218000, previewUrl:'', playable:false, fee:0, trial:true },
      { provider:provider, source:provider, type:'song', id:'ios-fallback-glass-console-' + provider, trackId:'fallback-2-' + provider, name:'Glass Console', title:'Glass Console', artist:'YUI7W', artists:[{name:'YUI7W'}], album:'Particle Room', cover:'', duration:196000, previewUrl:'', playable:false, fee:0, trial:true }
    ]);
  }

  async function searchItunesSongs(keywords, limit, provider) {
    var kw = String(keywords || '').trim();
    if (!kw) return [];
    var lim = Math.max(1, Math.min(25, parseInt(limit, 10) || 12));
    try {
      var nativeResult = await nativeIOSRequest('itunes-search', { keywords:kw, limit:lim });
      var nativeData = nativeResult && nativeResult.data;
      var nativeList = (nativeData && nativeData.results || []).filter(function(track){ return track && track.kind === 'song' && track.previewUrl; }).map(function(track){ return mapItunesTrack(track, provider); });
      if (nativeList.length) return rememberSongs(nativeList);
    } catch (nativeError) {
      try { window.webkit.messageHandlers.iosBridge.postMessage({ type:'native-search-fallback', message:String(nativeError && nativeError.message || nativeError) }); } catch (_) {}
    }
    if (!originalFetch) return fallbackSongs(provider);
    var endpoint = 'https://itunes.apple.com/search?media=music&entity=song&limit=' + encodeURIComponent(String(lim)) + '&term=' + encodeURIComponent(kw);
    var resp = await originalFetch(endpoint, { cache:'force-cache', headers:{ 'Accept':'application/json' } });
    if (!resp.ok) throw new Error('ITUNES_HTTP_' + resp.status);
    var data = await resp.json();
    var list = (data.results || []).filter(function(track){ return track && track.kind === 'song' && track.previewUrl; }).map(function(track){ return mapItunesTrack(track, provider); });
    return list.length ? rememberSongs(list) : [];
  }

  function songUrlPayload(song) {
    if (!song || !song.previewUrl) return { url:'', playable:false, provider:(song && song.provider) || 'ios', error:'NO_PLAYABLE_PREVIEW', preventAutoFallback:true, iosNoAutoSwitch:true, message:'当前歌曲没有可用试听地址' };
    return {
      provider: song.provider || 'apple',
      url: song.previewUrl,
      playable: true,
      trial: true,
      level: 'preview',
      quality: '30s 试听',
      loggedIn: true,
      vipType: 11,
      vipLevel: 'svip',
      isVip: true,
      isSvip: true,
      vipLabel: 'iOS'
    };
  }

  async function parseBody(init) {
    if (!init || init.body == null) return {};
    if (typeof init.body === 'string') {
      try { return JSON.parse(init.body); } catch (e) { return { text:init.body }; }
    }
    return {};
  }

  window.fetch = function(input, init){
    var url = String(input && input.url ? input.url : input);
    var path = url;
    var parsed = null;
    try { parsed = new URL(url, location.href); path = parsed.pathname; } catch(e) {}
    function json(body){ return Promise.resolve(new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } })); }
    function query(name){ return parsed ? (parsed.searchParams.get(name) || '') : ''; }
    if ((path === '/api/audio' || path === '/api/cover') && query('url') && originalFetch) {
      return originalFetch(query('url'), init || {});
    }
    if (path === '/api/app/version') return json({ version:'ios-desktop-shell', platform:'ios' });
    if (path === '/api/login/status') return neteaseResponse(neteaseNative('netease-login-status', {}).then(function(d){ d.provider='netease'; return d; }), { loggedIn:false, provider:'netease' });
    if (path === '/api/qq/login/status') return neteaseResponse(nativeIOSRequest('qq-login-status', {}).then(function(res){ return (res && res.data) || {}; }), { loggedIn:false, provider:'qq' });
    if (path === '/api/kugou/login/status') return neteaseResponse(nativeIOSRequest('kugou-login-status', {}).then(function(res){ return (res && res.data) || {}; }), { loggedIn:false, provider:'kugou' });
    if (path === '/api/login/cookie') return neteaseResponse(parseBody(init).then(function(body){ return neteaseNative('netease-login-cookie', { cookie:String((body && (body.cookie||body.data||body.text)) || '') }); }).then(function(d){ d.provider='netease'; return d; }), function(e){ return { loggedIn:false, provider:'netease', error:String(e&&e.message||e) }; });
    if (path === '/api/qq/login/cookie') return neteaseResponse(parseBody(init).then(function(body){ return nativeIOSRequest('qq-login-cookie', { cookie:String((body && (body.cookie||body.data||body.text)) || '') }); }).then(function(res){ return (res && res.data) || {}; }), function(e){ return { provider:'qq', loggedIn:false, saved:false, error:String(e&&e.message||e) }; });
    if (path === '/api/kugou/login/cookie') return neteaseResponse(parseBody(init).then(function(body){ return nativeIOSRequest('kugou-login-cookie', { cookie:String((body && (body.cookie||body.data||body.text)) || '') }); }).then(function(res){ return (res && res.data) || {}; }), function(e){ return { provider:'kugou', loggedIn:false, saved:false, error:String(e&&e.message||e) }; });
    if (path === '/api/login/qr/key') return neteaseResponse(neteaseNative('netease-login-qr-key', {}).then(function(d){ lastNeteaseQr = d; return { key:d.key }; }), function(e){ return { error:String(e&&e.message||e) }; });
    if (path === '/api/login/qr/create') {
      var ck = query('key');
      if (lastNeteaseQr && lastNeteaseQr.key === ck && lastNeteaseQr.img) return json({ img:lastNeteaseQr.img, url:lastNeteaseQr.qrurl });
      return neteaseResponse(neteaseNative('netease-login-qr-key', {}).then(function(d){ lastNeteaseQr = d; return { img:d.img, url:d.qrurl }; }), function(e){ return { error:String(e&&e.message||e) }; });
    }
    if (path === '/api/login/qr/check') return neteaseResponse(neteaseNative('netease-login-qr-check', { key:query('key') }), function(e){ return { code:0, error:String(e&&e.message||e) }; });
    if (path === '/api/logout') return neteaseResponse(neteaseNative('netease-logout', {}), { ok:true, loggedIn:false });
    if (path === '/api/qq/logout') return neteaseResponse(nativeIOSRequest('qq-logout', {}).then(function(res){ return (res && res.data) || {}; }), { provider:'qq', ok:true, loggedIn:false });
    if (path === '/api/kugou/logout') return neteaseResponse(nativeIOSRequest('kugou-logout', {}).then(function(res){ return (res && res.data) || {}; }), { provider:'kugou', ok:true, loggedIn:false });
    if (path === '/api/beatmap/cache/status') return json({ ok:true, enabled:false, platform:'ios', count:0, bytes:0 });
    if (path === '/api/beatmap/cache') {
      if ((init && String(init.method || '').toUpperCase() === 'POST')) return json({ ok:false, platform:'ios', cached:false });
      return json({ ok:false, platform:'ios', hit:false, beatMap:null });
    }
    if (path === '/api/lx/source/status') {
      return json({
        provider:'lx',
        enabled:false,
        platform:'ios',
        sourceCount:0,
        loadedCount:0,
        sources:[],
        message:'iOS 版保留 LX 入口；自定义 LX JS 源在桌面端本地运行，iOS 端会自动回落到原平台。'
      });
    }
    if (path === '/api/lx/source/import' || path === '/api/lx/source/remove' || path === '/api/lx/source/reload') {
      return json({ provider:'lx', ok:false, platform:'ios', error:'LX_SOURCE_IOS_UNSUPPORTED', message:'iOS 端不执行本地自定义源脚本。' });
    }
    if (path === '/api/lx/song/url') {
      return json({ provider:'lx', url:'', playable:false, platform:'ios', error:'LX_SOURCE_IOS_UNSUPPORTED', message:'iOS 端会回落到原平台播放。' });
    }
    if (path === '/api/lx/lyric') {
      return json({ provider:'lx', lyric:'', tlyric:'', rlyric:'', lxlyric:'' });
    }
    if (path === '/api/search') {
      return neteaseResponse(
        neteaseNative('netease-search', { keywords:(query('keywords') || query('term')), limit:(parseInt(query('limit'), 10) || 20) }).then(function(d){
          var songs = rememberSongs(d.songs || []);
          return { provider:'netease', songs:songs, result:{ songs:songs, songCount:songs.length } };
        }),
        function(error){
          return searchItunesSongs(query('keywords') || query('term'), query('limit') || '12', 'netease').then(function(songs){
            return { provider:'netease', degraded:true, error:String(error && error.message || error), songs:songs, result:{ songs:songs, songCount:songs.length } };
          });
        }
      );
    }
    if (path === '/api/qq/search') {
      return neteaseResponse(
        nativeIOSRequest('qq-search', { keywords:(query('keywords') || query('term')), limit:(parseInt(query('limit'), 10) || 20) }).then(function(res){
          var d = (res && res.data) || {};
          var songs = rememberSongs(d.songs || []);
          return { provider:'qq', songs:songs, result:{ songs:songs, songCount:songs.length } };
        }),
        function(error){ return { provider:'qq', error:String(error && error.message || error), songs:[], result:{ songs:[], songCount:0 } }; }
      );
    }
    if (path === '/api/apple/search') {
      var provider = 'apple';
      return searchItunesSongs(query('keywords') || query('term'), query('limit') || '12', provider).then(function(songs){
        return new Response(JSON.stringify({ provider:provider, songs:songs, result:{ songs:songs, songCount:songs.length } }), { status:200, headers:{ 'Content-Type':'application/json' } });
      }).catch(function(error){
        var songs = fallbackSongs(provider);
        return new Response(JSON.stringify({ provider:provider, error:String(error && error.message || error), songs:songs, result:{ songs:songs, songCount:songs.length } }), { status:200, headers:{ 'Content-Type':'application/json' } });
      });
    }
    if (path === '/api/kugou/search') {
      return neteaseResponse(
        nativeIOSRequest('kugou-search', { keywords:(query('keywords') || query('term')), limit:(parseInt(query('limit'), 10) || 20) }).then(function(res){
          var d = (res && res.data) || {};
          var songs = rememberSongs(d.songs || []);
          return { provider:'kugou', songs:songs, result:{ songs:songs, songCount:songs.length } };
        }),
        function(error){ return { provider:'kugou', error:String(error && error.message || error), songs:[], result:{ songs:[], songCount:0 } }; }
      );
    }
    if (path === '/api/song/url') {
      var neId = query('id');
      if (neId && String(neId).indexOf('ios-') !== 0) {
        return neteaseResponse(
          neteaseNative('netease-song-url', { id:String(neId), quality:(query('quality') || query('level') || '') }).then(function(d){
            var restriction = d && d.restriction || {};
            var action = d && (d.action || restriction.action);
            if (!d || d.url || d.playable !== false) return d;
            d.preventAutoFallback = true;
            d.iosNoAutoSwitch = true;
            if (!action) restriction.action = 'show_reason';
            d.restriction = restriction;
            return d;
          }),
          function(error){
            var fb = songUrlPayload(cachedSong(neId));
            fb.provider = 'netease';
            fb.preventAutoFallback = true;
            fb.iosNoAutoSwitch = true;
            fb.message = fb.message || String(error && error.message || error || '网易云暂未返回可播放地址');
            return fb;
          }
        );
      }
      return json(songUrlPayload(cachedSong(neId)));
    }
    if (path === '/api/qq/song/url') {
      return neteaseResponse(
        nativeIOSRequest('qq-song-url', { mid:String(query('mid') || query('songmid') || query('id') || ''), mediaMid:String(query('mediaMid') || query('media_mid') || ''), quality:(query('quality') || query('level') || '') }).then(function(res){ return (res && res.data) || {}; }),
        function(error){ return { provider:'qq', url:'', playable:false, error:String(error && error.message || error), message:'QQ 音乐暂未返回可播放地址' }; }
      );
    }
    if (path === '/api/kugou/song/url') {
      var kgHash = query('hash') || query('id');
      return neteaseResponse(
        nativeIOSRequest('kugou-song-url', { hash:String(kgHash || '') }).then(function(res){ return (res && res.data) || {}; }),
        function(error){ return { provider:'kugou', url:'', playable:false, error:String(error && error.message || error), message:'酷狗暂未返回可播放地址' }; }
      );
    }
    if (path === '/api/apple/song/url') {
      var preview = query('previewUrl') || query('url');
      return json(preview ? { provider:'apple', url:preview, playable:true, trial:true, level:'preview', quality:'30s 试听' } : { provider:'apple', url:'', playable:false, error:'NO_PREVIEW' });
    }
    if (path === '/api/user/playlists') {
      var localState = readIOSState();
      var localPlaylists = localState.playlists.map(function(p){
        return { id:p.id, name:p.name, trackCount:(p.tracks || []).length, count:(p.tracks || []).length, cover:p.cover || '', coverImgUrl:p.cover || '', subscribed:!!p.subscribed, specialType:p.specialType || 0 };
      });
      return neteaseResponse(
        neteaseNative('netease-user-playlists', {}).then(function(d){
          var ne = (d && d.playlists) || [];
          return { loggedIn:!!(d && d.loggedIn), provider:'netease', playlists:ne.concat(localPlaylists) };
        }),
        { loggedIn:false, provider:'ios', playlists:localPlaylists }
      );
    }
    if (path === '/api/qq/user/playlists' || path === '/api/kugou/user/playlists' || path === '/api/apple-local/playlists') {
      var state = readIOSState();
      var listProvider = path.indexOf('/kugou/') >= 0 ? 'kugou' : (path.indexOf('/qq/') >= 0 ? 'qq' : 'ios');
      return json({ loggedIn:true, provider:listProvider, playlists:state.playlists.map(function(p){
        return { id:p.id, name:p.name, trackCount:(p.tracks || []).length, count:(p.tracks || []).length, cover:p.cover || '', coverImgUrl:p.cover || '', subscribed:!!p.subscribed, specialType:p.specialType || 0 };
      }) });
    }
    if (path === '/api/playlist/create') {
      var stateCreate = readIOSState();
      var name = String(query('name') || '新歌单').trim() || '新歌单';
      var playlist = { id:'ios-pl-' + Date.now(), name:name, specialType:0, subscribed:false, tracks:[] };
      stateCreate.playlists.push(playlist);
      saveIOSState(stateCreate);
      return json({ success:true, playlist:{ id:playlist.id, name:playlist.name, trackCount:0, subscribed:false } });
    }
    if (path === '/api/playlist/add-song') {
      return parseBody(init).then(function(body){
        var stateAdd = readIOSState();
        var pid = String((body && body.pid) || query('pid') || '');
        var sid = String((body && body.id) || query('id') || '');
        var target = stateAdd.playlists.find(function(p){ return String(p.id) === pid; });
        var song = cachedSong(sid);
        if (!target || !song) return new Response(JSON.stringify({ success:false, error: target ? 'SONG_NOT_FOUND' : 'PLAYLIST_NOT_FOUND' }), { status:200, headers:{ 'Content-Type':'application/json' } });
        target.tracks = target.tracks || [];
        if (!target.tracks.some(function(item){ return String(item.id) === String(song.id); })) target.tracks.unshift(song);
        if (!target.cover && song.cover) target.cover = song.cover;
        saveIOSState(stateAdd);
        return new Response(JSON.stringify({ success:true, playlist:{ id:target.id, name:target.name, trackCount:target.tracks.length } }), { status:200, headers:{ 'Content-Type':'application/json' } });
      });
    }
    if (path === '/api/playlist/tracks') {
      var pidTracks = query('id') || query('name') || 'ios-liked';
      var stateTracks = readIOSState();
      var localPl = stateTracks.playlists.find(function(p){ return String(p.id) === String(pidTracks) || String(p.name) === String(pidTracks); });
      if (!localPl && String(pidTracks).indexOf('ios-') !== 0 && /^[0-9]+$/.test(String(pidTracks))) {
        return neteaseResponse(
          neteaseNative('netease-playlist-tracks', { id:String(pidTracks) }).then(function(d){
            var tks = rememberSongs((d && d.songs) || []);
            return { provider:'netease', tracks:tks, songs:tks, playlist:{ id:pidTracks, tracks:tks } };
          }),
          { provider:'netease', tracks:[], songs:[] }
        );
      }
      var tracks = localPl ? (localPl.tracks || []) : [];
      return json({ provider:'ios', tracks:tracks, songs:tracks, playlist:{ id:localPl && localPl.id, name:localPl && localPl.name, tracks:tracks } });
    }
    if (path === '/api/qq/playlist/tracks' || path === '/api/kugou/playlist/tracks' || path === '/api/apple-local/playlist-tracks') {
      var stateTracksQ = readIOSState();
      var pidTracksQ = query('id') || query('name') || 'ios-liked';
      var plQ = stateTracksQ.playlists.find(function(p){ return String(p.id) === String(pidTracksQ) || String(p.name) === String(pidTracksQ); });
      var tracksQ = plQ ? (plQ.tracks || []) : [];
      return json({ provider:'ios', tracks:tracksQ, songs:tracksQ, playlist:{ id:plQ && plQ.id, name:plQ && plQ.name, tracks:tracksQ } });
    }
    if (path === '/api/song/like/check') {
      var likedState = readIOSState();
      var out = {};
      String(query('ids') || '').split(',').forEach(function(id){ if (id) out[id] = !!likedState.liked[id]; });
      return json({ liked:out });
    }
    if (path === '/api/song/like') {
      var stateLike = readIOSState();
      var likeId = String(query('id') || '');
      var likeNext = query('like') !== 'false';
      var likeSong = cachedSong(likeId);
      stateLike.liked[likeId] = likeNext;
      var likedPl = stateLike.playlists.find(function(p){ return String(p.id) === 'ios-liked'; });
      if (likedPl && likeSong) {
        likedPl.tracks = likedPl.tracks || [];
        likedPl.tracks = likedPl.tracks.filter(function(item){ return String(item.id) !== likeId; });
        if (likeNext) likedPl.tracks.unshift(likeSong);
        if (!likedPl.cover && likeSong.cover) likedPl.cover = likeSong.cover;
      }
      saveIOSState(stateLike);
      if (likeId && likeId.indexOf('ios-') !== 0 && /^[0-9]+$/.test(likeId)) {
        try { neteaseNative('netease-like', { id:likeId, like:likeNext }); } catch (e) {}
      }
      return json({ success:true, liked:likeNext });
    }
    if (path === '/api/lyric') {
      var lid = query('id');
      if (lid && String(lid).indexOf('ios-') !== 0) {
        return neteaseResponse(neteaseNative('netease-lyric', { id:String(lid) }).then(function(d){
          var lrc = (d && d.lyric) || lyrics;
          return { lrc:{ lyric:lrc }, lyric:lrc, tlyric:{ lyric:(d && d.tlyric) || '' } };
        }), { lrc:{ lyric:lyrics }, lyric:lyrics });
      }
      return json({ lrc:{ lyric:lyrics }, lyric:lyrics });
    }
    if (path === '/api/qq/lyric') return json({ lrc:{ lyric:lyrics }, lyric:lyrics });
    if (path === '/api/song/comments' || path === '/api/qq/song/comments') return json({ provider:path.indexOf('/qq/') >= 0 ? 'qq' : 'netease', comments:[], hotComments:[], total:0 });
    if (path === '/api/artist/detail') {
      var artistId = query('id') || query('mid') || query('artistId');
      var cacheArtist = cachedSong('artist:' + artistId) || cachedSong(artistId);
      var artistName = (cacheArtist && cacheArtist.artist) || 'Artist';
      return neteaseResponse(
        neteaseNative('netease-search', { keywords:artistName, limit:(parseInt(query('limit'),10) || 18) }).then(function(d){
          var songs = rememberSongs((d && d.songs) || []);
          return { provider:'netease', artist:{ id:artistId, name:artistName, avatar:(songs[0] && songs[0].cover) || '' }, songs:songs };
        }),
        function(){ return searchItunesSongs(artistName, query('limit') || 18, 'netease').then(function(songs){ return { provider:'netease', artist:{ id:artistId, name:artistName, avatar:(songs[0] && songs[0].cover) || '' }, songs:songs }; }); }
      );
    }
    if (path === '/api/qq/artist/detail') {
      var artistIdQ = query('id') || query('mid') || query('artistId');
      var cacheArtistQ = cachedSong('artist:' + artistIdQ) || cachedSong(artistIdQ);
      var artistNameQ = (cacheArtistQ && cacheArtistQ.artist) || 'Artist';
      return searchItunesSongs(artistNameQ, query('limit') || 18, 'qq').then(function(songs){
        return new Response(JSON.stringify({ provider:'qq', artist:{ id:artistIdQ, name:artistNameQ, avatar:(songs[0] && songs[0].cover) || '' }, songs:songs }), { status:200, headers:{ 'Content-Type':'application/json' } });
      }).catch(function(){
        return new Response(JSON.stringify({ provider:'ios', artist:{ id:artistIdQ, name:artistNameQ, avatar:'' }, songs:[] }), { status:200, headers:{ 'Content-Type':'application/json' } });
      });
    }
    if (path === '/api/discover/home') return searchItunesSongs('today hits', 8, 'apple').then(function(songs){ return new Response(JSON.stringify({ ok:true, loggedIn:true, dailySongs:songs, playlists:readIOSState().playlists, podcasts:[] }), { status:200, headers:{ 'Content-Type':'application/json' } }); });
    if (path === '/api/weather/ip-location') return json({ ok:true, location:{ city:'当前位置', country:'', latitude:null, longitude:null } });
    if (path === '/api/weather/radio') return searchItunesSongs(query('city') || 'rainy day music', 10, 'apple').then(function(songs){ return new Response(JSON.stringify({ ok:true, weather:null, radio:{ title:'天气电台', subtitle:'iOS 本地推荐', seedQueries:[], songs:songs } }), { status:200, headers:{ 'Content-Type':'application/json' } }); });
    if (path === '/api/podcast/search' || path === '/api/podcast/hot' || path === '/api/podcast/programs' || path === '/api/podcast/my' || path === '/api/podcast/my/items') return json({ podcasts:[], programs:[], collections:[], items:[], loggedIn:true });
    if (path === '/api/apple-local/state') return json({ running:false, state:'stopped', available:false, iosNativeRequired:true });
    if (path === '/api/apple-local/control' || path === '/api/apple-local/play-track' || path === '/api/apple-local/play-playlist-track') return json({ ok:false, iosNativeRequired:true, error:'APPLE_LOCAL_DESKTOP_ONLY' });
    if (path === '/api/apple-local/library/search') return json({ provider:'apple-local', songs:[] });
    if (path === '/api/apple-local/audio-devices') return json({ available:false, devices:[], iosNativeRequired:true });
    if (path.indexOf('/api/update/') === 0) return json({ configured:false, updateAvailable:false, platform:'ios' });
    if (originalFetch) return originalFetch(input, init);
    return Promise.reject(new Error('fetch unavailable'));
  };

  window.__mineradioIOSDidFinish = function(){
    document.documentElement.classList.add('ios-shell-ready');
    document.body && document.body.classList.add('ios-shell', 'desktop-shell');
    // iOS 走 DIY 完整模式（与桌面一致），不再强制 simple-mode 裁剪 UI。
    try {
      if (typeof applyDiyMode === 'function') applyDiyMode(true, { save: true });
      else if (document.body) { document.body.classList.add('diy-mode'); document.body.classList.remove('simple-mode'); }
    } catch (e) {}
    var reveal = function(){
      try {
        if (typeof dismissSplash === 'function') dismissSplash();
      } catch (e) {}
      var splash = document.getElementById('splash');
      if (splash) {
        splash.classList.add('ready');
        splash.click();
        setTimeout(function(){ splash.classList.add('hide', 'exiting'); }, 260);
      }
      var search = document.getElementById('search-area');
      if (search) search.classList.add('peek');
      var login = document.getElementById('login-modal');
      if (login) login.classList.remove('show');
      disableEmbeddedLoginUI();
      // iOS：封面/头像直接用 https 直链（file:// 下 /api/cover 这种 img 加载会失败）。
      try {
        if (typeof coverProxySrc === 'function' && !window.__iosCoverPatched) {
          window.__iosCoverPatched = true;
          window.coverProxySrc = function(url){
            if (!url) return '';
            var s = String(url);
            if (s.indexOf('data:') === 0 || s.indexOf('blob:') === 0) return s;
            return s.replace(/^http:\/\//i, 'https://');
          };
        }
      } catch (e) {}
      // iOS：抑制启动时自动强弹的登录引导（登录入口仍在账号按钮/控制中枢，按需打开）。
      try {
        window.startupLoginGuideShown = true;
        document.body && document.body.classList.remove('login-guide-active');
        if (typeof showLoginModal === 'function' && !window.__iosLoginWrapped) {
          window.__iosLoginWrapped = true;
          var _iosOrigShowLogin = showLoginModal;
          window.showLoginModal = function(opts){
            if (opts && opts.guided) { try { if (typeof stopQrPoll === 'function') stopQrPoll(); } catch(e){} return; }
            return _iosOrigShowLogin.apply(this, arguments);
          };
        }
      } catch (e) {}
      var loginGuide = document.getElementById('login-guide-canvas');
      if (loginGuide) loginGuide.style.opacity = '0';
      document.body && document.body.classList.remove('login-guide-active');
      var bottom = document.getElementById('bottom-bar');
      if (bottom) bottom.classList.add('visible');
      var playlist = document.getElementById('playlist-panel');
      if (playlist) playlist.classList.add('ios-ready');
      var hint = document.getElementById('hint');
      if (hint) hint.classList.remove('hidden');
      try {
        if (typeof updateEmptyHomeVisibility === 'function') updateEmptyHomeVisibility({ forceLoad: true });
        if (typeof refreshLoginStatus === 'function') refreshLoginStatus(true);
        if (typeof updateControlGlassDisplacementMap === 'function') updateControlGlassDisplacementMap();
        installIOSPerformancePanel();
        installIOSControlHub();
        installIOSPanelClosers();
        installIOSLoginLimits();
        installIOSTabBar();
        installIOSCanvasGestures();
        installIOSPlayerShell();
        installIOSNowPlayingBridge();
        var toast = document.getElementById('toast');
        if (toast) toast.classList.remove('show');
      } catch (e) {
        try { window.webkit.messageHandlers.iosBridge.postMessage({ type:'boot-adapt-error', message:String(e && e.message || e) }); } catch(_) {}
      }
      try { window.webkit.messageHandlers.iosBridge.postMessage({ type:'ready', title:document.title, bodyClass:document.body ? document.body.className : '' }); } catch(e) {}
    };
    setTimeout(reveal, 900);
    setTimeout(reveal, 2100);
  };

  function installIOSLoginLimits() {
    ['login-provider-qq','user-provider-qq','account-add-qq','login-both-btn','qq-cookie-toggle-btn','qq-web-login-card','login-provider-kugou','user-provider-kugou','account-add-kugou'].forEach(function(id){
      var el = document.getElementById(id);
      if (!el) return;
      el.disabled = false;
      el.removeAttribute('aria-disabled');
      el.setAttribute('title', 'iOS 版支持自用会话导入，保存后用于搜索和播放授权');
      el.style.opacity = '';
      el.style.pointerEvents = '';
    });
    var hint = document.getElementById('account-hint');
    if (hint) hint.textContent = 'iOS 版支持网易云扫码，也支持 QQ 音乐 / 酷狗音乐自用会话导入。';
    var desc = document.getElementById('login-modal-desc');
    if (desc && /QQ/.test(desc.textContent || '')) {
      desc.innerHTML = 'QQ 音乐和酷狗音乐可手动导入网页登录会话，用于自用播放授权。';
    }
  }

  function disableEmbeddedLoginUI() {
    if (window.__mineradioEmbeddedLoginDisabled) return;
    window.__mineradioEmbeddedLoginDisabled = true;
    var style = document.createElement('style');
    style.textContent = [
      '#login-modal, #user-modal, #login-guide-canvas, #trial-login-btn { display:none !important; }',
      '#user-btn, #top-right .top-account-pill { pointer-events:none !important; }',
      '#login-provider-netease, #login-provider-qq, #login-provider-kugou, #login-both-btn,',
      '#qq-cookie-toggle-btn, #qq-cookie-panel, #refresh-qr-btn, #account-add-netease,',
      '#account-add-qq, #account-add-kugou, #account-logout-btn { display:none !important; }'
    ].join('');
    document.head.appendChild(style);
    [
      'showLoginModal',
      'openProviderLogin',
      'openProviderWebLogin',
      'openNeteaseWebLogin',
      'openQQWebLogin',
      'openKugouWebLogin',
      'refreshQr',
      'submitQQCookieLogin',
      'logoutActiveAccount'
    ].forEach(function(name) {
      window[name] = function() {
        var modal = document.getElementById('login-modal');
        if (modal) modal.classList.remove('show');
        return Promise.resolve({ ok:false, disabled:true });
      };
    });
    if (window.desktopWindow) {
      window.desktopWindow.openNeteaseMusicLogin = null;
      window.desktopWindow.openQQMusicLogin = null;
      window.desktopWindow.openKugouMusicLogin = null;
    }
  }

  function iosPerfLabel(mode) {
    return ({ eco:'低', balanced:'中', high:'高', ultra:'超高' })[mode] || '高';
  }

  function applyIOSPerformanceMode(mode, powerSave) {
    mode = ({ eco:1, balanced:1, high:1, ultra:1 })[mode] ? mode : 'high';
    try {
      if (typeof setPerformanceQualityMode === 'function') setPerformanceQualityMode(mode);
      else if (window.fx) fx.performanceQuality = mode;
      if (window.fx) {
        fx.performanceBackground = powerSave ? 'release' : 'auto';
        fx.liveBackgroundKeep = false;
        if (powerSave) {
          fx.bloom = false;
          fx.edge = false;
          fx.lyricGlowParticles = false;
          fx.photoDeckAuto = false;
          fx.performanceQuality = 'eco';
        }
      }
      document.body.classList.toggle('ios-power-save', !!powerSave);
      document.body.classList.toggle('ios-perf-eco', mode === 'eco' || !!powerSave);
      try { localStorage.setItem('mineradio-ios-performance-v1', JSON.stringify({ mode: powerSave ? 'eco' : mode, powerSave: !!powerSave })); } catch(e) {}
      if (typeof saveLyricLayout === 'function') saveLyricLayout();
      if (typeof updateFxInputs === 'function') updateFxInputs();
      var label = document.getElementById('ios-perf-current');
      if (label) label.textContent = powerSave ? '省电' : iosPerfLabel(mode);
    } catch (e) {
      try { window.webkit.messageHandlers.iosBridge.postMessage({ type:'perf-error', message:String(e && e.message || e) }); } catch(_) {}
    }
  }

  window.__mineradioIOSApplyPerformance = applyIOSPerformanceMode;

  function installIOSPerformancePanel() {
    if (document.getElementById('ios-performance-panel')) return;
    var saved = null;
    try { saved = JSON.parse(localStorage.getItem('mineradio-ios-performance-v1') || 'null'); } catch(e) {}
    var panel = document.createElement('div');
    panel.id = 'ios-performance-panel';
    panel.innerHTML = '<button class="ios-perf-main" type="button">视效 <b id="ios-perf-current">' + (saved && saved.powerSave ? '省电' : iosPerfLabel(saved && saved.mode || 'balanced')) + '</b></button>' +
      '<div class="ios-perf-pop">' +
      '<button data-ios-perf="eco">低</button><button data-ios-perf="balanced">中</button><button data-ios-perf="high">高</button><button data-ios-perf="ultra">超高</button>' +
      '<button data-ios-power="1">省电模式</button>' +
      '</div>';
    document.body.appendChild(panel);
    panel.querySelector('.ios-perf-main').addEventListener('click', function(e){ e.stopPropagation(); panel.classList.toggle('open'); });
    document.addEventListener('click', function(){ panel.classList.remove('open'); });
    panel.querySelectorAll('[data-ios-perf]').forEach(function(btn){
      btn.addEventListener('click', function(){
        applyIOSPerformanceMode(btn.getAttribute('data-ios-perf'), false);
        panel.classList.remove('open');
      });
    });
    panel.querySelector('[data-ios-power]').addEventListener('click', function(){
      applyIOSPerformanceMode('eco', true);
      panel.classList.remove('open');
    });
    if (saved) applyIOSPerformanceMode(saved.mode || 'high', !!saved.powerSave);
  }

  function installIOSControlHub() {
    if (document.getElementById('ios-control-hub')) return;
    var hub = document.createElement('div');
    hub.id = 'ios-control-hub';
    hub.innerHTML = '<button class="ios-hub-main" type="button" aria-label="更多控制">' +
      '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg></button>' +
      '<div class="ios-hub-pop">' +
      '<button data-ios-act="fx">🎛 视觉控制台</button>' +
      '<button data-ios-act="diy" id="ios-hub-diy">✦ DIY 模式</button>' +
      '<button data-ios-act="landscape">↔ 横屏视觉</button>' +
      '<button data-ios-act="upload">⤓ 导入音乐/封面</button>' +
      '<button data-ios-act="settings">⚙ 设置</button>' +
      '</div>';
    document.body.appendChild(hub);
    var main = hub.querySelector('.ios-hub-main');
    main.addEventListener('click', function(e){ e.stopPropagation(); hub.classList.toggle('open'); syncHubDiy(); });
    document.addEventListener('click', function(){ hub.classList.remove('open'); });
    function syncHubDiy() {
      var b = document.getElementById('ios-hub-diy');
      if (b) b.classList.toggle('on', !!(document.body && document.body.classList.contains('diy-mode')));
    }
    function enterLandscapeVisual() {
      if (window.__iosSetTab) window.__iosSetTab('visual');
      if (document.body) document.body.classList.add('ios-landscape-stage');
      try {
        if (screen.orientation && screen.orientation.lock) screen.orientation.lock('landscape').catch(function(){});
      } catch (_) {}
      if (typeof showToast === 'function') showToast('已切到横屏视觉，请旋转设备');
    }
    hub.querySelectorAll('[data-ios-act]').forEach(function(btn){
      btn.addEventListener('click', function(e){
        e.stopPropagation();
        var act = btn.getAttribute('data-ios-act');
        try {
          if (act === 'fx') {
            var fp = document.getElementById('fx-panel');
            var fxOpen = fp && (fp.classList.contains('show') || fp.classList.contains('peek'));
            if (typeof toggleFxPanel === 'function') toggleFxPanel(!fxOpen);
          }
          else if (act === 'settings' && typeof openSettingsModal === 'function') openSettingsModal();
          else if (act === 'diy' && typeof toggleDiyMode === 'function') { toggleDiyMode(); syncHubDiy(); }
          else if (act === 'landscape') enterLandscapeVisual();
          else if (act === 'immersive' && typeof toggleImmersiveMode === 'function') toggleImmersiveMode();
          else if (act === 'lyrics' && typeof toggleLyricsPanel === 'function') toggleLyricsPanel();
          else if (act === 'upload') { var fi = document.getElementById('file-input'); if (fi) fi.click(); }
        } catch (err) {
          try { window.webkit.messageHandlers.iosBridge.postMessage({ type:'hub-act-error', act:act, message:String(err && err.message || err) }); } catch(_) {}
        }
        if (act !== 'diy') hub.classList.remove('open');
      });
    });
    syncHubDiy();
  }

  // 给桌面"鼠标移开自动关"的面板补上手机端的显式关闭（✕ + 点外部关闭）。
  function installIOSPanelClosers() {
    var fx = document.getElementById('fx-panel');
    if (fx && !fx.__iosClose) {
      fx.__iosClose = true;
      var btn = document.createElement('button');
      btn.className = 'ios-panel-close';
      btn.type = 'button';
      btn.setAttribute('aria-label', '关闭视觉控制台');
      btn.textContent = '✕';
      btn.addEventListener('click', function(e){
        e.stopPropagation();
        try { if (typeof toggleFxPanel === 'function') toggleFxPanel(false); } catch (err) {}
      });
      fx.appendChild(btn);
    }
    if (!window.__iosFxOutside) {
      window.__iosFxOutside = true;
      document.addEventListener('touchstart', function(e){
        var panel = document.getElementById('fx-panel');
        if (!panel || !(panel.classList.contains('show') || panel.classList.contains('peek'))) return;
        if (panel.contains(e.target)) return;
        var hub = document.getElementById('ios-control-hub');
        if (hub && hub.contains(e.target)) return;
        try { if (typeof toggleFxPanel === 'function') toggleFxPanel(false); } catch (err) {}
      }, { passive:true });
    }
    // 登录弹窗：点遮罩背景关闭 + 已登录后自动兜底关闭（防卡死残留挡点击）。
    var lm = document.getElementById('login-modal');
    if (lm && !lm.__iosBackdrop) {
      lm.__iosBackdrop = true;
      lm.addEventListener('click', function(e){
        if (e.target === lm) {
          try { if (typeof closeLoginModal === 'function') closeLoginModal(); } catch (err) {}
          lm.classList.remove('show');
        }
      });
    }
    if (!window.__iosLoginGuard) {
      window.__iosLoginGuard = setInterval(function(){
        try {
          var m = document.getElementById('login-modal');
          if (!m || !m.classList.contains('show')) return;
          // 只在“当前正在补登的那个平台”已登录时才自动关，避免网易云已登录时误关 QQ/酷狗补登弹窗。
          var p = window.loginProvider || 'netease';
          var done = (p === 'qq') ? !!(window.qqLoginStatus && window.qqLoginStatus.loggedIn)
                   : (p === 'kugou') ? !!(window.kugouLoginStatus && window.kugouLoginStatus.loggedIn)
                   : !!(window.loginStatus && window.loginStatus.loggedIn);
          if (done) {
            if (typeof closeLoginModal === 'function') closeLoginModal();
            m.classList.remove('show');
          }
        } catch (e) {}
      }, 1500);
    }
  }

  function iosChosenVisualQuality() {
    if (window.__iosLowPower) return 'eco';
    try {
      var s = JSON.parse(localStorage.getItem('mineradio-ios-performance-v1') || 'null');
      if (s) return s.powerSave ? 'eco' : (s.mode || 'balanced');
    } catch (e) {}
    return 'balanced';
  }
  // tab 感知性能：视觉页用用户选定画质，其它页降到 eco（画布被遮，省电降热）。
  function applyIOSTabPerformance(key) {
    try {
      var q = (key === 'visual') ? iosChosenVisualQuality() : 'eco';
      if (typeof setPerformanceQualityMode === 'function') setPerformanceQualityMode(q, true);
      if (window.fx) fx.performanceBackground = (key === 'visual') ? 'auto' : 'release';
      if (typeof applyRendererPowerMode === 'function') applyRendererPowerMode();
    } catch (e) {}
  }
  window.__mineradioIOSReapplyPerf = function(){
    var key = document.body && document.body.classList.contains('ios-visual-focus') ? 'visual' : 'other';
    applyIOSTabPerformance(key);
  };

  function installIOSTabBar() {
    if (document.getElementById('ios-tabbar')) return;
    var bar = document.createElement('div');
    bar.id = 'ios-tabbar';
    var tabs = [
      { key:'home', label:'首页', icon:'<path d="M3 10.8 12 3l9 7.8"/><path d="M5 10v10h14V10"/>' },
      { key:'playlist', label:'歌单', icon:'<line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><circle cx="3.5" cy="6" r="1.2"/><circle cx="3.5" cy="12" r="1.2"/><circle cx="3.5" cy="18" r="1.2"/>' },
      { key:'visual', label:'视觉', icon:'<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="2.5"/>' }
    ];
    bar.innerHTML = tabs.map(function(t){
      return '<button data-ios-tab="'+t.key+'"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">'+t.icon+'</svg><span>'+t.label+'</span></button>';
    }).join('');
    document.body.appendChild(bar);
    var iosLastShelfMode = null;
    var iosShelfUserOff = false;
    function iosCurrentShelfMode() {
      try { return window.fx && /^(off|side|stage)$/.test(String(fx.shelf || '')) ? fx.shelf : 'off'; } catch (_) { return 'off'; }
    }
    function iosSetShelfMode(mode) {
      if (typeof setShelfMode === 'function') setShelfMode(mode);
      try { if (window.fx) fx.shelf = mode; } catch (_) {}
    }
    function setTab(key) {
      ['home','playlist','visual'].forEach(function(k){ document.body.classList.toggle('ios-tab-'+k, k===key); });
      bar.querySelectorAll('[data-ios-tab]').forEach(function(b){ b.classList.toggle('active', b.getAttribute('data-ios-tab')===key); });
      try {
        if (typeof togglePlaylistPanel === 'function') togglePlaylistPanel(key === 'playlist');
        if (key === 'playlist' && typeof refreshUserPlaylists === 'function') refreshUserPlaylists(true);
        if (key === 'visual') {
          document.body.classList.add('ios-visual-focus');
          if (typeof setShelfMode === 'function' && !iosShelfUserOff) iosSetShelfMode(iosLastShelfMode || iosCurrentShelfMode() || 'side');
        } else {
          document.body.classList.remove('ios-visual-focus');
          try {
            var beforeHide = iosCurrentShelfMode();
            iosShelfUserOff = beforeHide === 'off';
            if (beforeHide && beforeHide !== 'off') iosLastShelfMode = beforeHide;
            if (typeof setShelfPinnedOpen === 'function') setShelfPinnedOpen(false, true);
            iosSetShelfMode('off');
          } catch (_) {}
        }
        applyIOSTabPerformance(key);
      } catch (e) {}
    }
    try {
      var originalSetShelfMode = window.setShelfMode;
      if (typeof originalSetShelfMode === 'function' && !originalSetShelfMode.__iosRespectOffWrapped) {
        window.setShelfMode = function(mode) {
          var normalized = /^(off|side|stage)$/.test(String(mode || '')) ? String(mode) : mode;
          if (document.body && document.body.classList.contains('ios-visual-focus')) {
            iosShelfUserOff = normalized === 'off';
            if (normalized && normalized !== 'off') iosLastShelfMode = normalized;
          }
          return originalSetShelfMode.apply(this, arguments);
        };
        window.setShelfMode.__iosRespectOffWrapped = true;
      }
    } catch (_) {}
    bar.querySelectorAll('[data-ios-tab]').forEach(function(b){
      b.addEventListener('click', function(){ setTab(b.getAttribute('data-ios-tab')); });
    });
    window.__iosSetTab = setTab;
    setTab('home');
  }

  function installIOSCanvasGestures() {
    var container = document.getElementById('canvas-container');
    var canvas = container && (container.querySelector('canvas') || container);
    if (!canvas) { setTimeout(installIOSCanvasGestures, 800); return; }
    if (canvas.__iosGestures) return;
    canvas.__iosGestures = true;
    try { canvas.style.touchAction = 'none'; } catch (e) {}

    function fireMouse(type, x, y) {
      try { canvas.dispatchEvent(new MouseEvent(type, { bubbles:true, cancelable:true, view:window, button:0, clientX:x, clientY:y })); } catch (e) {}
    }
    function fireWheel(deltaY, x, y) {
      try { canvas.dispatchEvent(new WheelEvent('wheel', { bubbles:true, cancelable:true, deltaY:deltaY, clientX:x, clientY:y })); } catch (e) {}
    }
    function dist(a, b) { var dx=a.clientX-b.clientX, dy=a.clientY-b.clientY; return Math.sqrt(dx*dx+dy*dy); }

    var mode = null, lastDist = 0, lastX = 0, lastY = 0;

    canvas.addEventListener('touchstart', function(e){
      if (e.touches.length === 1) {
        mode = 'rotate';
        var t = e.touches[0]; lastX = t.clientX; lastY = t.clientY;
        fireMouse('mousedown', t.clientX, t.clientY);
      } else if (e.touches.length >= 2) {
        if (mode === 'rotate') fireMouse('mouseup', lastX, lastY);
        mode = 'zoom';
        lastDist = dist(e.touches[0], e.touches[1]);
      }
    }, { passive:true });

    canvas.addEventListener('touchmove', function(e){
      if (mode === 'rotate' && e.touches.length === 1) {
        var t = e.touches[0];
        if (e.cancelable) e.preventDefault();
        fireMouse('mousemove', t.clientX, t.clientY);
        lastX = t.clientX; lastY = t.clientY;
      } else if (mode === 'zoom' && e.touches.length >= 2) {
        if (e.cancelable) e.preventDefault();
        var d = dist(e.touches[0], e.touches[1]);
        var cx = (e.touches[0].clientX + e.touches[1].clientX) / 2;
        var cy = (e.touches[0].clientY + e.touches[1].clientY) / 2;
        fireWheel((lastDist - d) * 2.4, cx, cy);
        lastDist = d;
      }
    }, { passive:false });

    function endTouch(e) {
      if (mode === 'rotate') fireMouse('mouseup', lastX, lastY);
      if (e.touches && e.touches.length === 1) {
        mode = 'rotate';
        var t = e.touches[0]; lastX = t.clientX; lastY = t.clientY;
        fireMouse('mousedown', t.clientX, t.clientY);
      } else {
        mode = null;
      }
    }
    canvas.addEventListener('touchend', endTouch, { passive:true });
    canvas.addEventListener('touchcancel', endTouch, { passive:true });
  }

  function installIOSPlayerShell() {
    var bottom = document.getElementById('bottom-bar');
    if (!bottom || bottom.getAttribute('data-ios-player-shell') === '1') return;
    bottom.setAttribute('data-ios-player-shell', '1');
    var toggle = document.createElement('button');
    toggle.id = 'ios-player-toggle';
    toggle.type = 'button';
    toggle.setAttribute('aria-label', '展开播放器控制台');
    toggle.innerHTML = '<span aria-hidden="true"></span>';
    bottom.appendChild(toggle);
    function setExpanded(expanded) {
      document.body.classList.toggle('ios-player-expanded', !!expanded);
      toggle.setAttribute('aria-label', expanded ? '收起播放器控制台' : '展开播放器控制台');
      toggle.setAttribute('aria-expanded', expanded ? 'true' : 'false');
    }
    toggle.addEventListener('click', function(event) {
      event.stopPropagation();
      setExpanded(!document.body.classList.contains('ios-player-expanded'));
    });
    bottom.addEventListener('dblclick', function(event) {
      if (event.target && event.target.closest && event.target.closest('button,input')) return;
      setExpanded(!document.body.classList.contains('ios-player-expanded'));
    });
    setExpanded(false);
  }

  function installIOSNowPlayingBridge() {
    if (window.__mineradioIOSNowPlayingInstalled) return;
    window.__mineradioIOSNowPlayingInstalled = true;
    var lastSent = 0;
    function text(id) {
      var el = document.getElementById(id);
      return el ? String(el.textContent || '').trim() : '';
    }
    function currentMedia() {
      var media = null;
      document.querySelectorAll('audio,video').forEach(function(item){
        if (!media && item.src) media = item;
        if (item.src && !item.paused) media = item;
      });
      return media;
    }
    function send(force) {
      var now = Date.now();
      if (!force && now - lastSent < 900) return;
      lastSent = now;
      var media = currentMedia();
      var title = (window.__vothNowTitle || '') || text('control-title') || text('thumb-title') || 'Voice of the Heart';
      var artist = (window.__vothNowArtist || '') || text('control-artist') || text('thumb-artist') || '';
      var cover = '';
      try {
        cover = window.__vothNowCover || '';
        if (!cover) {
          var cc = document.getElementById('control-cover') || document.getElementById('thumb-cover');
          if (cc) {
            var bg = cc.style.backgroundImage || '';
            var mm = bg.match(/url\(["']?(.*?)["']?\)/);
            if (mm && mm[1]) cover = mm[1];
          }
        }
        if (cover.indexOf('/api/cover') >= 0) {
          try { var cu = new URL(cover, location.href); var ct = cu.searchParams.get('url'); if (ct) cover = ct; } catch (_) {}
        }
        if (cover.indexOf('http://') === 0) cover = 'https://' + cover.slice(7);
      } catch (e) {}
      try {
        window.webkit.messageHandlers.iosBridge.postMessage({
          type:'now-playing',
          title:title,
          artist:artist,
          cover:cover,
          duration: media && isFinite(media.duration) ? Number(media.duration) : 0,
          elapsed: media && isFinite(media.currentTime) ? Number(media.currentTime) : 0,
          playing: !!(media && media.src && !media.paused && !media.ended)
        });
      } catch (e) {}
    }
    document.addEventListener('play', function(event){ if (event.target && event.target.tagName === 'AUDIO') send(true); }, true);
    document.addEventListener('playing', function(event){ if (event.target && event.target.tagName === 'AUDIO') send(true); }, true);
    document.addEventListener('pause', function(event){ if (event.target && event.target.tagName === 'AUDIO') send(true); }, true);
    document.addEventListener('ended', function(event){ if (event.target && event.target.tagName === 'AUDIO') send(true); }, true);
    document.addEventListener('loadedmetadata', function(event){ if (event.target && event.target.tagName === 'AUDIO') send(true); }, true);
    document.addEventListener('durationchange', function(event){ if (event.target && event.target.tagName === 'AUDIO') send(true); }, true);
    document.addEventListener('timeupdate', function(event){ if (event.target && event.target.tagName === 'AUDIO') send(false); }, true);
    document.addEventListener('visibilitychange', function(){ send(true); }, true);
    window.addEventListener('pagehide', function(){ send(true); }, true);
    window.addEventListener('pageshow', function(){ send(true); }, true);
    setInterval(function(){ send(false); }, 1600);
    send(true);
  }

})();

/*!
 * @name 聆澜音源(赞助版)[过期: 26-09-11 16:31:05]
 * @description 支持所有平台全音质
 * @version v8.2
 * @author 时迁酱&guoyue2010
 */
// DEV_ENABLE 只控制 LX Music 是否打开开发者工具；日志由 LOG_ENABLE 单独控制。
const DEV_ENABLE = false;
const LOG_ENABLE = true;
const UPDATE_ENABLE = true;
const API_URL = "https://source.shiqianjiang.cn/api/music";
const API_KEY = "CERU_KEY-F987A290-4602-45C4-B049-AC5CC834526A";
const SCRIPT_MD5 = "8942c20110260dfdca5efd0f4f19ea1a";
const MUSIC_QUALITY = {"kw":["128k","320k","flac","flac24bit","hires"],"mg":["128k","320k","flac","flac24bit","hires"],"kg":["128k","320k","flac","flac24bit","hires","atmos","master"],"tx":["128k","320k","flac","flac24bit","hires","atmos","atmos_plus","master"],"wy":["128k","320k","flac","flac24bit","hires","atmos","master"],"git":["128k","320k","flac"]};
const MUSIC_SOURCE = Object.keys(MUSIC_QUALITY);
const { EVENT_NAMES, request, on, send, env, version } = globalThis.lx;

const LOG_PREFIX = "[聆澜音源(赞助版)[过期: 26-09-11 16:31:05]]";
let requestSequence = 0;

const logInfo = (...args) => {
  if (LOG_ENABLE) console.log(LOG_PREFIX, ...args);
};

const logError = (...args) => {
  console.error(LOG_PREFIX, ...args);
};

// 日志只保留排障所需信息，不暴露 API Key 和临时播放凭据。
const sanitizeUrl = (value) => {
  if (!value) return "";
  return String(value).replace(
    /([?&](?:key|apiKey|vkey|token|sign|mask)=)[^&]*/gi,
    "$1<redacted>",
  );
};

const formatError = (error) => ({
  name: error?.name ?? "Error",
  message: error?.message ?? String(error),
  stack: error?.stack,
});

const summarizeBody = (body) => {
  if (!body || typeof body !== "object") {
    return { bodyType: typeof body, bodyPresent: body != null };
  }
  return {
    code: body.code,
    message: body.message,
    hasUrl: typeof body.url === "string" && body.url.length > 0,
    url: sanitizeUrl(body.url),
    type: body.type,
    server: body.server,
    serverName: body.serverName,
  };
};

// LX Music 使用回调式 request，这里转成 Promise 并统一记录网络耗时。
const httpFetch = (url, options = { method: "GET" }, label = "request") => {
  const startedAt = Date.now();
  logInfo(`[http:${label}] 开始`, {
    method: options.method ?? "GET",
    url: sanitizeUrl(url),
    timeout: options.timeout,
    followMax: options.follow_max,
  });

  return new Promise((resolve, reject) => {
    request(url, options, (error, response) => {
      const elapsedMs = Date.now() - startedAt;
      if (error) {
        logError(`[http:${label}] 网络请求失败`, {
          elapsedMs,
          error: formatError(error),
        });
        reject(error);
        return;
      }
      logInfo(`[http:${label}] 请求结束`, {
        elapsedMs,
        statusCode: response?.statusCode ?? response?.status,
        bodyType: typeof response?.body,
      });
      resolve(response);
    });
  });
};

// 不同 LX 版本可能返回 JSON 字符串或已反序列化对象，两种都兼容。
const parseResponseBody = (body) => {
  if (typeof body !== "string") return body;
  try {
    return JSON.parse(body);
  } catch (error) {
    throw new Error(`响应不是有效 JSON: ${error.message}`);
  }
};

const handleGetMusicUrl = async (source, musicInfo, quality) => {
  const requestId = `${Date.now()}-${++requestSequence}`;
  const startedAt = Date.now();
  const songId = musicInfo?.hash ?? musicInfo?.songmid ?? musicInfo?.id;

  logInfo(`[request:${requestId}] 收到音乐链接请求`, {
    source,
    songId,
    quality,
    musicInfoKeys: musicInfo ? Object.keys(musicInfo) : [],
  });

  try {
    if (!MUSIC_QUALITY[source]) throw new Error(`不支持的音源: ${source}`);
    if (!songId) throw new Error("音乐 ID 不存在");

    const requestUrl = `${API_URL}/url?source=${encodeURIComponent(source)}&songId=${encodeURIComponent(songId)}&quality=${encodeURIComponent(quality)}`;
    const headers = {
      "Content-Type": "application/json",
      "X-Request-ID": requestId,
      "User-Agent": env
        ? `lx-music-${env}/${version}`
        : `lx-music-request/${version}`,
    };
    if (API_KEY) headers["X-API-Key"] = API_KEY;

    logInfo(`[request:${requestId}] 请求服务端`, {
      url: requestUrl,
      hasApiKey: Boolean(API_KEY),
      userAgent: headers["User-Agent"],
    });

    const response = await httpFetch(
      requestUrl,
      { method: "GET", headers, follow_max: 5, timeout: 15000 },
      requestId,
    );
    const statusCode = response?.statusCode ?? response?.status;
    const body = parseResponseBody(response?.body);
    const code = Number(body?.code);

    logInfo(`[request:${requestId}] 服务端响应`, {
      statusCode,
      elapsedMs: Date.now() - startedAt,
      ...summarizeBody(body),
    });

    if (!body || Number.isNaN(code)) {
      throw new Error("服务端响应缺少有效业务码");
    }
    if (statusCode != null && Number(statusCode) !== 200) {
      throw new Error(body.message ?? `HTTP 请求失败: ${statusCode}`);
    }

    // Go 服务统一返回 200；保留 code=0 兼容，避免旧通道成功响应被误判。
    if (code === 0 || code === 200) {
      if (!body.url) {
        throw new Error("服务端返回成功，但响应中没有音乐链接");
      }
      logInfo(`[request:${requestId}] 获取音乐链接成功`, {
        source,
        songId,
        quality,
        elapsedMs: Date.now() - startedAt,
        url: sanitizeUrl(body.url),
      });
      return body.url;
    }

    switch (code) {
      case 403:
        throw new Error("权限不足或 Key 失效");
      case 429:
        throw new Error("请求过速，请稍后再试");
      default:
        throw new Error(body.message ?? `服务端错误: ${code}`);
    }
  } catch (error) {
    logError(`[request:${requestId}] 获取音乐链接失败`, {
      source,
      songId,
      quality,
      elapsedMs: Date.now() - startedAt,
      error: formatError(error),
    });
    throw new Error(error?.message ?? String(error));
  }
};

// 更新 URL 含 API Key，日志必须经过 sanitizeUrl 脱敏。
const checkUpdate = async () => {
  const startedAt = Date.now();
  const requestId = `lx-update-${Date.now()}-${++requestSequence}`;
  const updateUrl = `${API_URL.replace("/music", "")}/script?checkUpdate=${encodeURIComponent(SCRIPT_MD5)}&key=${encodeURIComponent(API_KEY)}`;
  logInfo(`[update:${requestId}] 开始检查更新`, {
    url: sanitizeUrl(updateUrl),
  });

  try {
    const response = await httpFetch(
      updateUrl,
      {
        method: "GET",
        headers: {
          "Content-Type": "application/json",
          "X-Request-ID": requestId,
          "User-Agent": env
            ? `lx-music-${env}/${version}`
            : `lx-music-request/${version}`,
        },
        timeout: 15000,
      },
      "update",
    );
    const body = parseResponseBody(response?.body);
    logInfo(`[update:${requestId}] 检查完成`, {
      elapsedMs: Date.now() - startedAt,
      statusCode: response?.statusCode ?? response?.status,
      code: body?.code,
      hasUpdate: Boolean(body?.data),
      message: body?.message,
    });

    if (body?.data) {
      send(EVENT_NAMES.updateAlert, {
        log: body.data.updateMsg,
        updateUrl: body.data.updateUrl,
      });
    }
  } catch (error) {
    logError(`[update:${requestId}] 检查失败`, {
      elapsedMs: Date.now() - startedAt,
      error: formatError(error),
    });
  }
};

// 按服务端下发的音质能力动态注册 LX Music 音源。
const musicSources = {};
MUSIC_SOURCE.forEach((source) => {
  musicSources[source] = {
    name: source,
    type: "music",
    actions: ["musicUrl"],
    qualitys: MUSIC_QUALITY[source],
  };
});

on(EVENT_NAMES.request, ({ action, source, info }) => {
  logInfo("[event] 收到 LX Music 事件", {
    action,
    source,
    quality: info?.type,
    hasMusicInfo: Boolean(info?.musicInfo),
  });

  if (action === "musicUrl") {
    return handleGetMusicUrl(source, info?.musicInfo, info?.type);
  }
  logError("[event] 不支持的操作", { action, source });
  return Promise.reject(new Error(`action not supported: ${action}`));
});

logInfo("[init] 插件初始化", {
  version: "v8.2",
  lxVersion: version,
  env,
  apiUrl: API_URL,
  updateEnabled: UPDATE_ENABLE,
  sources: MUSIC_SOURCE,
  qualitys: MUSIC_QUALITY,
});

if (UPDATE_ENABLE) checkUpdate();

send(EVENT_NAMES.inited, {
  status: true,
  openDevTools: DEV_ENABLE,
  sources: musicSources,
});

logInfo("[init] 插件已就绪", { sourceCount: MUSIC_SOURCE.length });

/*!
 * @name ikun音源[赞助][永久]
 * @description QQ群1073165843 过期时间
 * @version v26
 * @author ikunshare
 */

const DEV_ENABLE = false
const UPDATE_ENABLE = true
const API_URL = "https://c.wwwweb.top"
const API_KEY = "IKM-P32200001-x9Cow1ja8Zz4acdg-by"
const SCRIPT_MD5 = "d8a5ffde7accc82905263a18392d96f5";
const MUSIC_QUALITY = JSON.parse('{"git":["128k","320k","flac"],"kg":["128k","320k","flac","flac24bit","hires","atmos","master"],"kw":["128k","320k","flac","flac24bit","hires"],"tx":["128k","320k","flac","flac24bit","hires","atmos","atmos_plus","master"],"wy":["128k","320k","flac","flac24bit","hires","atmos","master"]}');

const MUSIC_SOURCE = Object.keys(MUSIC_QUALITY);
const {EVENT_NAMES, request, on, send, utils, env, version} = globalThis.lx;

const httpFetch = (url, options = {method: "GET"}) => {
    return new Promise((resolve, reject) => {
        request(url, options, (err, resp) => {
            if (err) return reject(err);
            resolve(resp);
        });
    });
};

const handleGetMusicUrl = async (source, musicInfo, quality) => {
    const songId = musicInfo.hash ?? musicInfo.songmid;
    const request = await httpFetch(
        `${API_URL}/music/url`,
        {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "User-Agent": `${
                    env ? `lx-music-${env}/${version}` : `lx-music-request/${version}`
                }`,
                "X-Api-Key": API_KEY,
            },
            body: {
                source: source,
                musicId: songId,
                quality: quality,
            },
            follow_max: 5,
        }
    );
    const {body} = request;
    if (!body || isNaN(Number(body.code))) throw new Error("unknow error");
    if (env !== "mobile") console.groupEnd();
    switch (body.code) {
        case 200:
            return body.url;
        case 403:
            throw new Error("鉴权失败");
        case 429:
            throw new Error("请求过速");
        case 500:
            throw new Error(`获取URL失败, ${body.message ?? "未知错误"}`);
        default:
            throw new Error(body.message ?? "未知错误");
    }
};

const checkUpdate = async () => {
    const request = await httpFetch(
        `${API_URL}/script/lxmusic?checkUpdate=${SCRIPT_MD5}&key=${API_KEY}`,
        {
            method: "GET",
            headers: {
                "Content-Type": "application/json",
                "User-Agent": `${
                    env ? `lx-music-${env}/${version}` : `lx-music-request/${version}`
                }`,
            },
        }
    );
    const {body} = request;

    if (!body || body.code !== 200) console.log("checkUpdate failed");
    else {
        if (body.data != null) {
            globalThis.lx.send(lx.EVENT_NAMES.updateAlert, {
                log: body.data.updateMsg,
                updateUrl: body.data.updateUrl,
            });
        }
    }
};

const musicSources = {};
MUSIC_SOURCE.forEach((item) => {
    musicSources[item] = {
        name: item,
        type: "music",
        actions: ["musicUrl"],
        qualitys: MUSIC_QUALITY[item],
    };
});

on(EVENT_NAMES.request, ({action, source, info}) => {
    switch (action) {
        case "musicUrl":
            return handleGetMusicUrl(source, info.musicInfo, info.type)
                .then((data) => Promise.resolve(data))
                .catch((err) => Promise.reject(err));
        default:
            return Promise.reject("action not support");
    }
});

if (UPDATE_ENABLE) checkUpdate();

send(EVENT_NAMES.inited, {
    status: true,
    openDevTools: DEV_ENABLE,
    sources: musicSources,
});



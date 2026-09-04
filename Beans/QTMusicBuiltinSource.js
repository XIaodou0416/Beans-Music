(function () {
  const PLUGIN_INFO = JSON.stringify({
      uid: '85e91dc3-e306-4d95-b611-d32e35b3d59d',
      name: '聆澜音源(赞助版)[过期: 26-09-11 16:31:05]',
      version: 'v8.2',
      description: '支持所有平台全音质 作者：时迁酱&guoyue2010',
      support: ["kw","mg","kg","tx","wy","git"]
  });
  const list = ['standard','exhigh','lossless','lossless+','hires','atmos','master'];
  const names = ['standard','exhigh','lossless','lossless+','hires','atmos','master'];
  const musicQuality = {"kw":["128k","320k","flac","flac24bit","hires"],"mg":["128k","320k","flac","flac24bit","hires"],"kg":["128k","320k","flac","flac24bit","hires","atmos","master"],"tx":["128k","320k","flac","flac24bit","hires","atmos","atmos_plus","master"],"wy":["128k","320k","flac","flac24bit","hires","atmos","master"],"git":["128k","320k","flac"]};
  const sources = {};
  for (let source in musicQuality) {
      sources[source] = { qualitys: musicQuality[source] };
  }
  function pickQuality(source, quality) {
      const supported = sources[source]?.qualitys;
      if (!supported || supported.length === 0) return list[0];
      const idx = names.indexOf(quality);
      const q = list[idx] || list[0];
      return supported.includes(q) ? q : supported[supported.length - 1];
  }
  async function getMusicUrl(source,id,quality,key="CERU_KEY-F987A290-4602-45C4-B049-AC5CC834526A") {
      quality = pickQuality(source,quality);
      const url = `https://source.shiqianjiang.cn/api/music/url?source=${source}&songId=${id}&quality=${quality}`;
      const headers = {
          'Content-Type': 'application/json',
          'X-API-Key': 'CERU_KEY-F987A290-4602-45C4-B049-AC5CC834526A',
          'User-Agent': 'CeruMusic-Plugin/v1'
      };
      try {
          const resultStr = await customFetch(url, { method: 'GET', headers: headers });
          const data = JSON.parse(resultStr);
          return data['url'];
      } catch (error) {
          try { return await getMusicUrl(source,id,'exhigh'); }
          catch (error) { throw error; }
      }
  }
  globalThis.MusicPlugin = { info: PLUGIN_INFO, getMusicUrl };
})();
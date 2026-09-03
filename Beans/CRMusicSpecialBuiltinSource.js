/*!
 * @name 聆澜音源(赞助版)[过期: 26-09-04 19:56:38]
 * @description 澜音插件 支持所有主流平台全音质
 * @version v8.1
 * @author 时迁酱&guoyue2010
 * @homepage https://source.shiqianjiang.cn
 */

// 插件信息
const pluginInfo = {
  name: "聆澜音源(赞助版)[过期: 26-09-04 19:56:38]",
  version: "v8.1",
  author: "时迁酱&guoyue2010",
  description: "澜音插件 支持所有主流平台全音质",
  updateMd5: "8b90aa0565db383348891653396e2fb2",
  apiKey: "CERU_KEY-009D12E5-95CF-42FE-A518-9525F2A0D74A",
  type:'cr'
};

// 支持的音源配置
const sources = {
  kw: { name: "酷我音乐", qualitys: ["128k", "320k", "flac", "flac24bit", "hires"] },
  mg: { name: "咪咕音乐", qualitys: ["128k", "320k", "flac", "flac24bit", "hires"] },
  kg: { name: "酷狗音乐", qualitys: ["128k", "320k", "flac", "flac24bit", "hires", "atmos", "master"] },
  tx: { name: "QQ音乐", qualitys: ["128k", "320k", "flac", "flac24bit", "hires", "atmos", "atmos_plus", "master"] },
  wy: { name: "网易云音乐", qualitys: ["128k", "320k", "flac", "flac24bit", "hires", "atmos", "master"] },
  git: { name: "GitCode", qualitys: ["128k", "320k", "flac"] }
};
// api 地址
const apiUrl = 'https://source.shiqianjiang.cn';
// 获取工具函数
const { request, NoticeCenter, version } = cerumusic;

// 插件名格式化 修饰
function pluginName(source) {
  return `[${pluginInfo.name} <${sources[source].name}>]`;
}

// 获取音乐链接的主要方法
async function musicUrl(source, musicInfo, quality) {
  console.log('收到解析请求', '-------------不优雅的分割线-------------');
  try {
    // 检查source是否有效
    if (!sources[source]) {
      throw new Error(`无效的音源: ${source}`);
    }

    // 检查quality是否有效
    if (!sources[source].qualitys.includes(quality)) {
      throw new Error(
        `无效的音质: ${quality}，支持的音质: ${sources[source].qualitys.join(', ')}`,
      );
    }

    const songId = musicInfo.hash ?? musicInfo.songmid ?? musicInfo.id;

    if (!songId) {
      throw new Error('音乐ID不存在');
    }
    console.log(
      `${pluginName(source)} 请求音乐链接: 歌曲ID: ${songId}, 音质: ${quality}`,
    );
    // 使用 cerumusic API 发送 HTTP 请求
    const result = await request(
      `${apiUrl}/music/url?source=${source}&songId=${songId}&quality=${quality}`,
      {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': pluginInfo.apiKey,
          'User-Agent': `CeruMusic-Plugin/${pluginInfo.version}`,
        },
        timeout: 15000,
      },
    );
    console.info(`${pluginName(source)} 请求响应数据:`, result.body);
    console.log(
      `${pluginName(source)} 请求结束，响应状态码: ${result.statusCode}`,
    );
    if (result.statusCode === 200 && result.body && result.body.code === 200) {
      if (result.body.url) {
        console.log(
          `${pluginName(source)} 获取音乐链接成功: ${songId}, 音质: ${quality}, 链接: ${result.body.url}`,
        );
        return result.body.url;
      } else {
        throw new Error('返回数据中没有音乐链接');
      }
    } else if (result.body && result.body.code) {
      switch (result.body.code) {
        case 403:
          // 发送错误通知
          NoticeCenter('error', {
            title: '音乐链接获取失败',
            content: `来源: ${pluginName(source)}, 错误: API Key失效或鉴权失败`,
          });
          throw new Error('API Key失效或鉴权失败');
        case 429:
          NoticeCenter('error', {
            title: '音乐链接获取失败',
            content: `来源: ${pluginName(source)}, 错误: 请求过于频繁，请稍后再试`,
          });
          typeof cerumusic.stopRequests === 'function' &&
            cerumusic.stopRequests(result.body, 60);
          throw new Error('请求过于频繁，请稍后再试');
        case 500:
          throw new Error(`服务器错误: ${result.body.message || '未知错误'}`);
        default:
          NoticeCenter('error', {
            title: '音乐链接获取失败',
            content: `来源: ${pluginName(source)}, 错误: API错误 ${result.body.message || '未知错误'}`,
          });
          throw new Error(`API错误: ${result.body.message || '未知错误'}`);
      }
    } else {
      throw new Error(`HTTP请求失败: ${result.statusCode}`);
    }
  } catch (error) {
    console.error(`${pluginName(source)} 获取音乐链接失败:`, error.message);
    throw new Error(error.message ?? error);
  }
}

const checkUpdate = async () => {
  try {
    const { body } = await request(
      `${apiUrl}/script?checkUpdate=${pluginInfo.updateMd5}&key=${pluginInfo.apiKey}&type=${pluginInfo.type}`,
      {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': `CeruMusic-Plugin/${pluginInfo.version}`,
        },
      },
    );
    console.log('版本更新检测响应:', body);
    if (!body || body.code !== 200) {
      console.error('版本更新检测失败:', body.message || '未知错误');
    } else {
      if (body.data != null) {
        NoticeCenter('update', {
          title: `${pluginInfo.name} 有新的版本 ${body.data.version}`,
          content: body.data.updateMsg,
          url: `${body.data.updateUrl}`, // 可选 当通知为update 版本跟新可传
          version: body.data.version, // 当通知为update 版本跟新可传
          pluginInfo: {
            name: pluginInfo.name,
            type: 'cr', // 固定唯一标识
          }, // 当通知为update 版本跟新可传
        });
      } else {
        console.log(`${pluginInfo.name} 没有新的版本`);
      }
    }
  } catch (error) {
    console.error('checkUpdate error:', error);
  }
};
checkUpdate().then(() => {
  console.log('版本更新检测完成');
});
// LocalParsedVersion >= 1.0.4
const parseVersion = (v) => {
  return v
    .replace(/^v/, '')
    .split('.')
    .map((num) => parseInt(num, 10));
};
function checkAppVersion() {
  const LocalParsedVersion = parseVersion(version);
  const pointVersion = parseVersion('1.0.4');
  for (
    let i = 0;
    i < Math.max(LocalParsedVersion.length, pointVersion.length);
    i++
  ) {
    const r = pointVersion[i] || 0;
    const c = LocalParsedVersion[i] || 0;

    if (r > c) return true;
    if (r < c) return false;
  }

  return false;
}
if (checkAppVersion()) {
  NoticeCenter('warn', {
    title: '插件环境版本过低',
    content:
      '请升级插件环境版本到1.0.4或以上（软件v1.9.11以上）以更好适配插件哦',
  });
}

// 导出插件
module.exports = {
  pluginInfo,
  sources,
  musicUrl,
};

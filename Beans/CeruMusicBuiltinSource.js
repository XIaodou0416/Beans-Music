/**
 * @name 独家音源
 * @description 支持酷我、酷狗、QQ、网易云和咪咕音乐
 * @version 5.0.0
 * @author w
 * @homepage https://88.lxmusic.xn--fiqs8s
 */

const pluginInfo = {
  name: '独家音源',
  version: '5.0.0',
  author: 'w',
  description: '支持酷我、酷狗、QQ、网易云和咪咕音乐',
  type: 'cr',
}

const sources = {
  kw: { name: '酷我音乐', qualitys: ['128k', '320k', 'flac', 'flac24bit'] },
  kg: { name: '酷狗音乐', qualitys: ['128k', '320k', 'flac', 'flac24bit'] },
  tx: { name: 'QQ音乐', qualitys: ['128k', '320k', 'flac', 'flac24bit'] },
  wy: { name: '网易云音乐', qualitys: ['128k', '320k', 'flac', 'flac24bit'] },
  mg: { name: '咪咕音乐', qualitys: ['128k', '320k', 'flac', 'flac24bit'] },
}

const channel = {
  api: 'https://88.lxmusic.xn--fiqs8s',
  version: 5,
  fingerprint: '74c52ba24b386a2301983d94596246c2',
  salt: 'LxSrv@2026#Sig',
  scriptHash: {
    lower: 'cbf73813e164e32a13bbe2d1f4e4e7bd',
    upper: 'fb637140c486c08b146712411604a861',
  },
}

const md5 = value => cerumusic.utils.crypto.md5(String(value))
const hexByte = value => value.toString(16).padStart(2, '0')

function signTime(timestamp, timeMD5) {
  return [...timestamp.toString(16)].map((char, index) => {
    const hashByte = parseInt(timeMD5.slice(index * 2, index * 2 + 2), 16)
    return hexByte(char.charCodeAt(0) ^ hashByte)
  }).join('')
}

function signScript(timestamp) {
  const factor = timestamp % 145788374 + 183
  const proof = channel.scriptHash.lower.match(/../g)
    .map(byte => hexByte((parseInt(byte, 16) + 1) * factor % 256))
    .join('')
  return md5(proof + channel.scriptHash.upper)
}

function signPath(path, timestamp) {
  let value = md5(`${path}|${timestamp}|${channel.fingerprint}|${channel.salt}`)
  for (let index = 0; index < 5; index++) {
    value = md5(value + path[index] + channel.salt[index])
  }
  return value
}

function signSong({ source, id, quality }, timestamp) {
  const reversedID = [...String(id)].reverse().join('')
  let value = md5(
    `${source}|${reversedID}|${quality}|${channel.version}|${channel.fingerprint}|${timestamp}|${channel.salt}`,
  )
  for (let round = 0; round < 3; round++) value = md5(value + channel.salt)
  return value
}

function signedURL(path, song) {
  const timestamp = Date.now()
  const timeMD5 = md5(timestamp)
  const params = {
    e: timeMD5,
    to: signTime(timestamp, timeMD5),
    fp: channel.fingerprint,
    s2: signPath(path, timestamp),
    v: channel.version,
    si: signScript(timestamp),
  }
  if (song) params.s3 = signSong(song, timestamp)

  const query = Object.entries(params)
    .map(([name, value]) => `${name}=${encodeURIComponent(value)}`)
    .join('&')
  return `${channel.api}${path}?${query}`
}

async function request(path, song) {
  const response = await cerumusic.request(signedURL(path, song), {
    method: 'GET',
    headers: {
      'Content-Type': 'application/json',
      'User-Agent': `CeruMusic-Plugin/${pluginInfo.version}`,
    },
    timeout: 15000,
  })

  if (response.statusCode !== 200) throw new Error(`渠道请求失败（HTTP ${response.statusCode}）`)
  return response.body
}

function getSongID(source, music) {
  if (source === 'kg') return music.hash ?? music.meta?.hash ?? music.id ?? music.songmid
  if (source === 'mg') {
    return music.copyrightId ?? music.meta?.copyrightId ?? music.id ?? music.songmid ?? music.hash
  }
  return music.id ?? music.songmid ?? music.meta?.songId ?? music.hash
}

async function musicUrl(source, musicInfo, quality) {
  if (!sources[source]) throw new Error(`不支持音源平台：${source}`)
  if (!sources[source].qualitys.includes(quality)) throw new Error(`不支持 ${quality} 音质`)

  const id = getSongID(source, musicInfo)
  if (id == null || id === '') throw new Error('音乐信息中缺少歌曲 ID')

  console.log(`[独家音源 <${sources[source].name}>] 请求音乐链接：${id}，音质：${quality}`)
  const path = `/v4s/url/${source}/${encodeURIComponent(id)}/${encodeURIComponent(quality)}`
  const result = await request(path, { source, id, quality })
  if (result?.code !== 0 || !result.data) throw new Error(result?.msg || '获取音乐链接失败')

  const url = typeof result.data === 'string' ? result.data : result.data.url
  if (!url) throw new Error('渠道响应中没有音乐链接')
  return url
}

module.exports = { pluginInfo, sources, musicUrl }

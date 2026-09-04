const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const express = require('express');
const multer = require('multer');

const MAX_ATTACHMENTS = 4;
const MAX_ATTACHMENT_SIZE = 50 * 1024 * 1024;
const LOCATION_CACHE_TTL_MS = 6 * 60 * 60 * 1000;
const ONLINE_WINDOW_MS = 3 * 60 * 1000;
const USER_ID_PATTERN = /^[a-f0-9-]{16,80}$/i;
const locationCache = new Map();
const MEDIA_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/heic',
  'image/heif',
  'image/webp',
  'image/gif',
  'video/mp4',
  'video/quicktime',
]);

function createBeansRouter(options = {}) {
  const router = express.Router();
  const storageDir = options.storageDir || path.join(process.cwd(), 'beans-data');
  const uploadDir = path.join(storageDir, 'uploads');
  const databasePath = path.join(storageDir, 'users.json');
  const adminPassword = String(options.adminPassword || process.env.BEANS_ADMIN_PASSWORD || '');
  const browserAdmin = typeof options.adminMiddleware === 'function'
    ? options.adminMiddleware
    : requireBrowserAdmin(adminPassword);

  ensureDirectory(storageDir);
  ensureDirectory(uploadDir);

  const upload = multer({
    storage: multer.diskStorage({
      destination: (_request, _file, callback) => callback(null, uploadDir),
      filename: (_request, file, callback) => callback(null, `${crypto.randomUUID()}${extensionFor(file)}`),
    }),
    limits: { fileSize: MAX_ATTACHMENT_SIZE, files: MAX_ATTACHMENTS },
    fileFilter: (_request, file, callback) => {
      callback(MEDIA_TYPES.has(file.mimetype) ? null : new Error('unsupported_attachment'), MEDIA_TYPES.has(file.mimetype));
    },
  });

  router.use(express.json({ limit: '32kb' }));
  router.use('/uploads', express.static(uploadDir, { fallthrough: false, maxAge: '1d' }));

  router.post('/register', (request, response, next) => {
    try {
      const user = upsertUser(request.body, request.ip, { countAccess: true });
      scheduleLocationUpdate(user.user_id, request.ip);
      response.json(publicUserState(user));
    } catch (error) {
      next(error);
    }
  });

  router.post('/heartbeat', (request, response, next) => {
    try {
      const user = upsertUser(request.body, request.ip);
      scheduleLocationUpdate(user.user_id, request.ip);
      response.json(publicUserState(user));
    } catch (error) {
      next(error);
    }
  });

  router.post('/feedback', upload.array('attachments[]', MAX_ATTACHMENTS), (request, response, next) => {
    try {
      const payload = request.body || {};
      const phoneModel = text(payload.phone_model, 128);
      const phoneSystem = text(payload.phone_system, 128);
      const problem = text(payload.problem, 8000);
      if (!phoneModel || !phoneSystem || !problem) {
        removeUploadedFiles(request.files);
        return response.status(422).json({ ok: false, message: 'missing_required_fields' });
      }

      const user = upsertUser(payload, request.ip);
      scheduleLocationUpdate(user.user_id, request.ip);
      const unlockDownload = phoneModel === '1011' && phoneSystem === '0416' && problem === '2778';
      const attachments = (request.files || []).map((file) => ({
        name: file.filename,
        original_name: text(file.originalname, 180),
        mime_type: file.mimetype,
        size: file.size,
        url: `/beans/uploads/${encodeURIComponent(file.filename)}`,
      }));
      const feedbackID = crypto.randomUUID();
      const submittedAt = now();

      mutateDatabase((database) => {
        const storedUser = database.users[user.user_id];
        if (unlockDownload) {
          storedUser.download_unlocked = true;
        }
        database.feedback.unshift({
          id: feedbackID,
          user_id: user.user_id,
          phone_model: phoneModel,
          phone_system: phoneSystem,
          problem,
          attachments,
          submitted_at: submittedAt,
        });
      });

      return response.json({
        feedback_id: feedbackID,
        submitted_at: submittedAt,
        ...publicUserState(loadDatabase().users[user.user_id]),
      });
    } catch (error) {
      removeUploadedFiles(request.files);
      return next(error);
    }
  });

  router.get('/users', requireApiAdmin(adminPassword), (_request, response) => {
    const database = loadDatabase();
    const users = Object.values(database.users)
      .sort((left, right) => right.last_seen_at.localeCompare(left.last_seen_at))
      .slice(0, 1000)
      .map((user) => ({ ...user, online: isUserOnline(user) }));
    response.json({ ok: true, total_users: Object.keys(database.users).length, online_users: countOnlineUsers(database), users });
  });

  router.get('/feedback', requireApiAdmin(adminPassword), (_request, response) => {
    const database = loadDatabase();
    response.json({ ok: true, total_feedback: database.feedback.length, feedback: database.feedback.slice(0, 1000) });
  });

  router.delete('/feedback/:id', requireApiAdmin(adminPassword), (request, response) => {
    const feedbackID = text(request.params.id, 80);
    let removedFeedback;
    mutateDatabase((database) => {
      const index = database.feedback.findIndex((item) => item.id === feedbackID);
      if (index < 0) {
        return;
      }
      removedFeedback = database.feedback.splice(index, 1)[0];
    });
    if (!removedFeedback) {
      return response.status(404).json({ ok: false, message: 'feedback_not_found' });
    }
    removeFeedbackAttachments(removedFeedback);
    return response.json({ ok: true, feedback_id: feedbackID });
  });

  router.get('/stats', requireApiAdmin(adminPassword), (_request, response) => {
    response.json({ ok: true, ...statsFor(loadDatabase()) });
  });

  router.post('/user-action', requireApiAdmin(adminPassword), (request, response) => {
    const payload = request.body || {};
    const userID = text(payload.user_id, 80);
    if (!USER_ID_PATTERN.test(userID)) {
      return response.status(422).json({ ok: false, message: 'invalid_user_id' });
    }
    let updatedUser;
    mutateDatabase((database) => {
      const user = database.users[userID];
      if (!user) {
        return;
      }
      user.is_blacklisted = Boolean(payload.is_blacklisted);
      user.download_unlocked = Boolean(payload.download_unlocked);
      user.action_note = text(payload.action_note, 500);
      updatedUser = user;
    });
    if (!updatedUser) {
      return response.status(404).json({ ok: false, message: 'user_not_found' });
    }
    return response.json(publicUserState(updatedUser));
  });

  router.get('/admin', browserAdmin, (_request, response) => {
    response.type('html').send(renderAdminPage(loadDatabase(), 'overview'));
  });

  router.get('/admin/users', browserAdmin, (_request, response) => {
    response.type('html').send(renderAdminPage(loadDatabase(), 'users'));
  });

  router.get('/admin/feedback', browserAdmin, (_request, response) => {
    response.type('html').send(renderAdminPage(loadDatabase(), 'feedback'));
  });

  router.post(
    '/admin/user',
    browserAdmin,
    express.urlencoded({ extended: false }),
    (request, response) => {
      const userID = text(request.body.user_id, 80);
      mutateDatabase((database) => {
        const user = database.users[userID];
        if (!user) {
          return;
        }
        user.is_blacklisted = request.body.is_blacklisted === 'on';
        user.download_unlocked = request.body.download_unlocked === 'on';
        user.action_note = text(request.body.action_note, 500);
      });
      response.redirect('/beans/admin/users');
    }
  );

  router.post(
    '/admin/feedback/:id/delete',
    browserAdmin,
    (request, response) => {
      const feedbackID = text(request.params.id, 80);
      let removedFeedback;
      mutateDatabase((database) => {
        const index = database.feedback.findIndex((item) => item.id === feedbackID);
        if (index < 0) {
          return;
        }
        removedFeedback = database.feedback.splice(index, 1)[0];
      });
      if (removedFeedback) {
        removeFeedbackAttachments(removedFeedback);
      }
      response.redirect('/beans/admin/feedback');
    }
  );

  router.use((error, _request, response, _next) => {
    if (error?.status === 422 || error?.message === 'invalid_user_id') {
      return response.status(422).json({ ok: false, message: error.message });
    }
    if (error instanceof multer.MulterError) {
      return response.status(422).json({ ok: false, message: 'attachment_upload_failed' });
    }
    if (error?.message === 'unsupported_attachment') {
      return response.status(422).json({ ok: false, message: 'unsupported_attachment' });
    }
    console.error('Beans backend error:', error);
    return response.status(500).json({ ok: false, message: 'server_error' });
  });

  return router;

  function upsertUser(payload, ip, options = {}) {
    const userID = text(payload?.user_id, 80);
    if (!USER_ID_PATTERN.test(userID)) {
      const error = new Error('invalid_user_id');
      error.status = 422;
      throw error;
    }
    let record;
    mutateDatabase((database) => {
      const existing = database.users[userID];
      const timestamp = now();
      if (options.countAccess) {
        database.stats.access_count += 1;
        database.stats.last_access_at = timestamp;
      }
      record = {
        user_id: userID,
        device_model: text(payload.model, 128),
        device_name: text(payload.device_name, 128),
        system_name: text(payload.system, 128),
        system_version: text(payload.system_version, 64),
        app_version: text(payload.app_version, 64),
        app_build: text(payload.app_build, 64),
        first_seen_at: existing?.first_seen_at || timestamp,
        last_seen_at: timestamp,
        last_ip: text(ip, 64),
        location: existing?.location || '',
        location_updated_at: existing?.location_updated_at || '',
        is_blacklisted: Boolean(existing?.is_blacklisted),
        download_unlocked: Boolean(existing?.download_unlocked),
        action_note: existing?.action_note || '',
      };
      database.users[userID] = record;
    });
    return record;
  }

  function scheduleLocationUpdate(userID, ip) {
    const normalizedIP = normalizeIPAddress(ip);
    if (!normalizedIP || isPrivateIPAddress(normalizedIP)) {
      updateStoredLocation(userID, ip, '未知位置');
      return;
    }

    const cached = locationCache.get(normalizedIP);
    if (cached && cached.expiresAt > Date.now()) {
      updateStoredLocation(userID, ip, cached.location);
      return;
    }

    void resolveIPAddressLocation(normalizedIP).then((location) => {
      locationCache.set(normalizedIP, {
        location,
        expiresAt: Date.now() + LOCATION_CACHE_TTL_MS,
      });
      updateStoredLocation(userID, ip, location);
    });
  }

  async function resolveIPAddressLocation(ip) {
    try {
      const response = await fetch(
        `https://ipwho.is/${encodeURIComponent(ip)}?lang=zh-CN`,
        { headers: { accept: 'application/json' } }
      );
      if (!response.ok) return '未知位置';
      const payload = await response.json();
      if (payload?.success !== true) return '未知位置';
      return formatLocation(payload);
    } catch {
      return '未知位置';
    }
  }

  function updateStoredLocation(userID, ip, location) {
    try {
      mutateDatabase((database) => {
        const user = database.users[userID];
        if (!user || user.last_ip !== text(ip, 64)) return;
        user.location = location;
        user.location_updated_at = now();
      });
    } catch (error) {
      console.error('Beans location update error:', error);
    }
  }

  function removeFeedbackAttachments(feedback) {
    (feedback?.attachments || []).forEach((attachment) => {
      const rawURL = String(attachment?.url || '');
      const marker = '/beans/uploads/';
      if (!rawURL.startsWith(marker)) {
        return;
      }
      let filename;
      try {
        filename = path.basename(decodeURIComponent(rawURL.slice(marker.length)));
      } catch {
        return;
      }
      const filePath = path.join(uploadDir, filename);
      if (!filename || !filePath.startsWith(uploadDir + path.sep)) {
        return;
      }
      try {
        fs.rmSync(filePath, { force: true });
      } catch (error) {
        console.error('Beans feedback attachment cleanup error:', error);
      }
    });
  }

  function loadDatabase() {
    try {
      const parsed = JSON.parse(fs.readFileSync(databasePath, 'utf8'));
      return {
        users: parsed.users && typeof parsed.users === 'object' ? parsed.users : {},
        feedback: Array.isArray(parsed.feedback) ? parsed.feedback : [],
        stats: {
          access_count: Number.isFinite(parsed.stats?.access_count) ? parsed.stats.access_count : 0,
          last_access_at: text(parsed.stats?.last_access_at, 64),
        },
      };
    } catch (error) {
      if (error.code === 'ENOENT') {
        return { users: {}, feedback: [], stats: { access_count: 0, last_access_at: '' } };
      }
      throw error;
    }
  }

  function mutateDatabase(mutation) {
    const database = loadDatabase();
    mutation(database);
    const temporaryPath = `${databasePath}.${process.pid}.${crypto.randomUUID()}.tmp`;
    fs.writeFileSync(temporaryPath, JSON.stringify(database, null, 2), { mode: 0o600 });
    fs.renameSync(temporaryPath, databasePath);
  }
}

function publicUserState(user) {
  return {
    ok: true,
    blocked: Boolean(user?.is_blacklisted),
    download_unlocked: Boolean(user?.download_unlocked),
  };
}

function requireApiAdmin(password) {
  return (request, response, next) => {
    if (!password || !secureEqual(password, String(request.get('x-beans-admin') || ''))) {
      return response.status(401).json({ ok: false, message: 'admin_unauthorized' });
    }
    return next();
  };
}

function requireBrowserAdmin(password) {
  return (request, response, next) => {
    const header = String(request.get('authorization') || '');
    const supplied = header.startsWith('Basic ')
      ? Buffer.from(header.slice(6), 'base64').toString('utf8').split(':').slice(1).join(':')
      : '';
    if (!password || !secureEqual(password, supplied)) {
      response.set('WWW-Authenticate', 'Basic realm="Beans Admin"');
      return response.status(401).send('Authentication required');
    }
    return next();
  };
}

function secureEqual(left, right) {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  return leftBuffer.length === rightBuffer.length && crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function text(value, maxLength) {
  return String(value || '').trim().slice(0, maxLength);
}

function normalizeIPAddress(value) {
  let ip = String(value || '').trim();
  if (ip.startsWith('::ffff:')) ip = ip.slice(7);
  return ip;
}

function isPrivateIPAddress(ip) {
  return ip === '127.0.0.1'
    || ip === '0.0.0.0'
    || ip.startsWith('10.')
    || ip.startsWith('192.168.')
    || /^172\.(1[6-9]|2\d|3[0-1])\./.test(ip)
    || ip === '::1'
    || ip.startsWith('fc')
    || ip.startsWith('fd');
}

function formatLocation(payload) {
  const parts = [payload.country, payload.region, payload.city, payload.district]
    .map((value) => text(value, 80))
    .filter(Boolean);
  return parts.length ? parts.join(' ') : '未知位置';
}

function extensionFor(file) {
  const extensions = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/heic': '.heic',
    'image/heif': '.heic',
    'image/webp': '.webp',
    'image/gif': '.gif',
    'video/mp4': '.mp4',
    'video/quicktime': '.mov',
  };
  return extensions[file.mimetype] || '.bin';
}

function ensureDirectory(directory) {
  fs.mkdirSync(directory, { recursive: true, mode: 0o750 });
}

function removeUploadedFiles(files) {
  (files || []).forEach((file) => {
    if (file?.path) {
      fs.rm(file.path, { force: true }, () => {});
    }
  });
}

function now() {
  return new Date().toISOString();
}

function escapeHtml(value) {
  return String(value || '').replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  }[character]));
}

function isUserOnline(user, timestamp = Date.now()) {
  const lastSeen = Date.parse(user?.last_seen_at || '');
  return Number.isFinite(lastSeen) && timestamp - lastSeen <= ONLINE_WINDOW_MS;
}

function countOnlineUsers(database, timestamp = Date.now()) {
  return Object.values(database.users).filter((user) => isUserOnline(user, timestamp)).length;
}

function statsFor(database) {
  return {
    total_users: Object.keys(database.users).length,
    access_count: database.stats.access_count,
    total_feedback: database.feedback.length,
    online_users: countOnlineUsers(database),
    online_window_seconds: ONLINE_WINDOW_MS / 1000,
    last_access_at: database.stats.last_access_at || null,
  };
}

function renderAdminPage(database, section = 'overview') {
  const stats = statsFor(database);
  const users = Object.values(database.users)
    .sort((left, right) => right.last_seen_at.localeCompare(left.last_seen_at))
    .slice(0, 500);
  const userRows = users.map((user) => `
    <tr>
      <td class="id">${escapeHtml(user.user_id)}<br><small>${escapeHtml(user.location || '位置获取中')}</small></td>
      <td>${escapeHtml(user.device_model || user.device_name)}<br><small>${escapeHtml(`${user.system_name} ${user.system_version}`)}</small></td>
      <td><span class="status ${isUserOnline(user) ? 'online' : 'offline'}">${isUserOnline(user) ? '在线' : '离线'}</span><br><small>${escapeHtml(user.last_seen_at)}</small></td>
      <td>${escapeHtml(`${user.app_version} (${user.app_build})`)}<br><small>首次：${escapeHtml(user.first_seen_at)}</small></td>
      <td><form method="post" action="/beans/admin/user"><input type="hidden" name="user_id" value="${escapeHtml(user.user_id)}"><label><input type="checkbox" name="is_blacklisted" ${user.is_blacklisted ? 'checked' : ''}> 拉黑</label><br><label><input type="checkbox" name="download_unlocked" ${user.download_unlocked ? 'checked' : ''}> 下载已解锁</label><br><input name="action_note" value="${escapeHtml(user.action_note)}" placeholder="后台备注"><button>保存</button></form></td>
    </tr>
  `).join('');
  const feedbackRows = database.feedback.slice(0, 500).map((item) => {
    const attachments = (item.attachments || []).map((attachment) => {
      const url = escapeHtml(attachment.url);
      if (attachment.mime_type?.startsWith('video/')) {
        return `<div class="feedback-media"><video controls preload="metadata" src="${url}"></video><a href="${url}" target="_blank" rel="noopener">打开视频</a></div>`;
      }
      if (attachment.mime_type?.startsWith('image/')) {
        return `<div class="feedback-media"><a href="${url}" target="_blank" rel="noopener"><img src="${url}" loading="lazy" alt="反馈图片"></a></div>`;
      }
      return `<a href="${url}" target="_blank" rel="noopener">打开附件</a>`;
    }).join('');
    const deleteButton = `<form method="post" action="/beans/admin/feedback/${encodeURIComponent(item.id)}/delete" onsubmit="return confirm('确定删除这条反馈工单？')"><button class="danger">删除工单</button></form>`;
    return `<tr><td>${escapeHtml(item.submitted_at)}</td><td class="id">${escapeHtml(item.user_id)}</td><td>${escapeHtml(item.phone_model)}<br><small>${escapeHtml(item.phone_system)}</small></td><td class="problem">${escapeHtml(item.problem)}<div class="media">${attachments}</div></td><td>${deleteButton}</td></tr>`;
  }).join('');

  const body = section === 'users'
    ? `<section class="panel"><h2>用户列表 <small>在线状态按最近 ${ONLINE_WINDOW_MS / 60000} 分钟心跳计算</small></h2><table><thead><tr><th>设备 ID / 位置</th><th>设备 / 系统</th><th>在线状态</th><th>版本 / 时间</th><th>管理</th></tr></thead><tbody>${userRows || emptyRow('暂无用户')}</tbody></table></section>`
    : section === 'feedback'
      ? `<section class="panel"><h2>反馈列表</h2><table><thead><tr><th>时间</th><th>用户</th><th>填写设备</th><th>反馈内容与附件</th><th>操作</th></tr></thead><tbody>${feedbackRows || emptyRow('暂无反馈')}</tbody></table></section>`
      : `<section class="metrics"><article class="metric"><small>总用户</small><b>${stats.total_users}</b></article><article class="metric"><small>软件访问量</small><b>${stats.access_count}</b></article><article class="metric"><small>当前在线</small><b>${stats.online_users}</b><small>最近 ${ONLINE_WINDOW_MS / 60000} 分钟有心跳</small></article><article class="metric"><small>反馈数量</small><b>${stats.total_feedback}</b></article></section><section class="panel overview"><h2>使用情况</h2><p>最近一次访问：${escapeHtml(stats.last_access_at || '暂无记录')}</p><p>在线用户通过应用每分钟心跳更新，离开超过 ${ONLINE_WINDOW_MS / 60000} 分钟后自动视为离线。</p></section>`;

  return `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Beans 后台</title><style>:root{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#182230;background:#f8fafc}body{margin:0}.page{max-width:1500px;margin:0 auto;padding:28px}.bar{margin-bottom:24px}.bar h1{font-size:25px;margin:0}.bar p,small{color:#667085}.nav{display:flex;gap:8px;flex-wrap:wrap;margin:18px 0}.nav a{color:#344054;text-decoration:none;background:#fff;border:1px solid #d0d5dd;border-radius:8px;padding:8px 12px}.nav a.active{color:#fff;background:#182230;border-color:#182230}.metrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}.metric,.panel{background:#fff;border:1px solid #eaecf0;border-radius:12px}.metric{padding:18px}.metric b{display:block;font-size:30px;margin-top:8px}.panel{overflow:auto;margin-top:20px}.panel h2{font-size:17px;padding:18px 18px 0;margin:0}.overview{padding-bottom:18px}.overview p{padding:0 18px;color:#667085}table{width:100%;border-collapse:collapse;font-size:13px}th,td{padding:12px 14px;border-bottom:1px solid #eaecf0;vertical-align:top;text-align:left}th{color:#667085;background:#fcfcfd}.id{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;word-break:break-all}.problem{max-width:500px;white-space:pre-wrap;word-break:break-word}.media{margin-top:7px;display:flex;gap:8px;flex-wrap:wrap}.media a{color:#175cd3;text-decoration:none}.feedback-media{display:inline-flex;flex-direction:column;gap:5px;margin:6px 8px 0 0;vertical-align:top}.feedback-media img,.feedback-media video{display:block;width:min(240px,40vw);max-height:220px;object-fit:cover;border-radius:8px;background:#101828}.status{display:inline-block;border-radius:999px;padding:3px 8px;font-size:12px}.status.online{color:#067647;background:#ecfdf3}.status.offline{color:#667085;background:#f2f4f7}input[name=action_note]{width:150px;box-sizing:border-box;padding:6px;border:1px solid #d0d5dd;border-radius:6px}button{border:0;border-radius:7px;padding:7px 10px;background:#182230;color:#fff;cursor:pointer}@media(max-width:900px){.metrics{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:650px){.page{padding:16px}.metrics{grid-template-columns:1fr}.feedback-media img,.feedback-media video{width:min(260px,70vw)}}</style><body><main class="page"><header class="bar"><h1>Beans 后台</h1><p>用户、反馈与访问情况</p><nav class="nav"><a class="${section === 'overview' ? 'active' : ''}" href="/beans/admin">概览</a><a class="${section === 'users' ? 'active' : ''}" href="/beans/admin/users">用户</a><a class="${section === 'feedback' ? 'active' : ''}" href="/beans/admin/feedback">反馈</a></nav></header>${body}</main></body></html>`;

  function emptyRow(label) {
    const columnCount = section === 'feedback' ? 5 : 5;
    return `<tr><td colspan="${columnCount}" style="color:#667085;text-align:center;padding:28px">${escapeHtml(label)}</td></tr>`;
  }
}

module.exports = { createBeansRouter };

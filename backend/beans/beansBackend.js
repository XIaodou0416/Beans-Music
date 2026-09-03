const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const express = require('express');
const multer = require('multer');

const MAX_ATTACHMENTS = 4;
const MAX_ATTACHMENT_SIZE = 50 * 1024 * 1024;
const USER_ID_PATTERN = /^[a-f0-9-]{16,80}$/i;
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
      response.json(publicUserState(upsertUser(request.body, request.ip)));
    } catch (error) {
      next(error);
    }
  });

  router.post('/heartbeat', (request, response, next) => {
    try {
      response.json(publicUserState(upsertUser(request.body, request.ip)));
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
      const unlockDownload = phoneModel === '1011' && phoneSystem === '0416' && problem === '2778';
      const attachments = (request.files || []).map((file) => ({
        name: file.filename,
        original_name: text(file.originalname, 180),
        mime_type: file.mimetype,
        size: file.size,
        url: `uploads/${encodeURIComponent(file.filename)}`,
      }));
      const feedbackID = crypto.randomUUID();

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
          submitted_at: now(),
        });
      });

      return response.json({
        feedback_id: feedbackID,
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
      .slice(0, 1000);
    response.json({ ok: true, total_users: Object.keys(database.users).length, users });
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
    response.type('html').send(renderAdminPage(loadDatabase()));
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
      response.redirect('admin');
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

  function upsertUser(payload, ip) {
    const userID = text(payload?.user_id, 80);
    if (!USER_ID_PATTERN.test(userID)) {
      const error = new Error('invalid_user_id');
      error.status = 422;
      throw error;
    }
    let record;
    mutateDatabase((database) => {
      const existing = database.users[userID];
      record = {
        user_id: userID,
        device_model: text(payload.model, 128),
        device_name: text(payload.device_name, 128),
        system_name: text(payload.system, 128),
        system_version: text(payload.system_version, 64),
        app_version: text(payload.app_version, 64),
        app_build: text(payload.app_build, 64),
        first_seen_at: existing?.first_seen_at || now(),
        last_seen_at: now(),
        last_ip: text(ip, 64),
        is_blacklisted: Boolean(existing?.is_blacklisted),
        download_unlocked: Boolean(existing?.download_unlocked),
        action_note: existing?.action_note || '',
      };
      database.users[userID] = record;
    });
    return record;
  }

  function loadDatabase() {
    try {
      const parsed = JSON.parse(fs.readFileSync(databasePath, 'utf8'));
      return {
        users: parsed.users && typeof parsed.users === 'object' ? parsed.users : {},
        feedback: Array.isArray(parsed.feedback) ? parsed.feedback : [],
      };
    } catch (error) {
      if (error.code === 'ENOENT') {
        return { users: {}, feedback: [] };
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

function renderAdminPage(database) {
  const users = Object.values(database.users)
    .sort((left, right) => right.last_seen_at.localeCompare(left.last_seen_at))
    .slice(0, 500);
  const userRows = users.map((user) => `
    <tr>
      <td class="id">${escapeHtml(user.user_id)}<br><small>${escapeHtml(user.last_ip)}</small></td>
      <td>${escapeHtml(user.device_model || user.device_name)}<br><small>${escapeHtml(`${user.system_name} ${user.system_version}`)}</small></td>
      <td>${escapeHtml(`${user.app_version} (${user.app_build})`)}<br><small>${escapeHtml(user.last_seen_at)}</small></td>
      <td><form method="post" action="admin/user"><input type="hidden" name="user_id" value="${escapeHtml(user.user_id)}"><label><input type="checkbox" name="is_blacklisted" ${user.is_blacklisted ? 'checked' : ''}> 拉黑</label><br><label><input type="checkbox" name="download_unlocked" ${user.download_unlocked ? 'checked' : ''}> 下载已解锁</label><br><input name="action_note" value="${escapeHtml(user.action_note)}" placeholder="后台备注"><button>保存</button></form></td>
    </tr>
  `).join('');
  const feedbackRows = database.feedback.slice(0, 300).map((item) => {
    const attachments = (item.attachments || []).map((attachment) =>
      `<a href="${escapeHtml(attachment.url)}" target="_blank" rel="noopener">附件</a>`
    ).join(' ');
    return `<tr><td>${escapeHtml(item.submitted_at)}</td><td class="id">${escapeHtml(item.user_id)}</td><td>${escapeHtml(item.phone_model)}<br><small>${escapeHtml(item.phone_system)}</small></td><td class="problem">${escapeHtml(item.problem)}<div class="media">${attachments}</div></td></tr>`;
  }).join('');

  return `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Beans 后台</title><style>:root{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#182230;background:#f8fafc}body{margin:0}.page{max-width:1500px;margin:0 auto;padding:28px}.bar{margin-bottom:24px}.bar h1{font-size:25px;margin:0}.bar p,small{color:#667085}.metrics{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}.metric,.panel{background:#fff;border:1px solid #eaecf0;border-radius:12px}.metric{padding:18px}.metric b{display:block;font-size:30px;margin-top:8px}.panel{overflow:auto;margin-top:20px}.panel h2{font-size:17px;padding:18px 18px 0;margin:0}table{width:100%;border-collapse:collapse;font-size:13px}th,td{padding:12px 14px;border-bottom:1px solid #eaecf0;vertical-align:top;text-align:left}th{color:#667085;background:#fcfcfd}.id{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;word-break:break-all}.problem{max-width:380px;white-space:pre-wrap;word-break:break-word}.media{margin-top:7px;display:flex;gap:8px;flex-wrap:wrap}.media a{color:#175cd3;text-decoration:none}input[name=action_note]{width:150px;box-sizing:border-box;padding:6px;border:1px solid #d0d5dd;border-radius:6px}button{border:0;border-radius:7px;padding:7px 10px;background:#182230;color:#fff;cursor:pointer}@media(max-width:800px){.page{padding:16px}.metrics{grid-template-columns:1fr}}</style><body><main class="page"><header class="bar"><h1>Beans 后台</h1><p>匿名设备、反馈与用户控制</p></header><section class="metrics"><article class="metric"><small>总用户</small><b>${Object.keys(database.users).length}</b></article><article class="metric"><small>反馈数量</small><b>${database.feedback.length}</b></article></section><section class="panel"><h2>用户</h2><table><thead><tr><th>设备 ID</th><th>设备 / 系统</th><th>版本 / 最近活跃</th><th>状态与操作</th></tr></thead><tbody>${userRows}</tbody></table></section><section class="panel"><h2>反馈</h2><table><thead><tr><th>时间</th><th>用户</th><th>填写设备</th><th>问题</th></tr></thead><tbody>${feedbackRows}</tbody></table></section></main></body></html>`;
}

module.exports = { createBeansRouter };

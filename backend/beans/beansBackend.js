const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const express = require('express');
const multer = require('multer');

const MAX_ATTACHMENTS = 4;
const MAX_ATTACHMENT_SIZE = 50 * 1024 * 1024;
const LOCATION_CACHE_TTL_MS = 6 * 60 * 60 * 1000;
const ONLINE_WINDOW_MS = 3 * 60 * 1000;
const INACTIVE_USER_WINDOW_MS = 10 * 24 * 60 * 60 * 1000;
const USER_ID_PATTERN = /^[a-f0-9-]{16,80}$/i;
const PUBLIC_USER_ID_MIN = 100000;
const PUBLIC_USER_ID_MAX = 500000;
const DEVELOPER_INITIAL_PUBLIC_USER_ID = '5201314';
const DEVELOPER_DEVICE_ID_HASH = process.env.BEANS_DEVELOPER_DEVICE_ID_HASH
  || 'f6073926d77dd0947338f5f27f133201a484a2d2b28f68f7fbd95cb168526d36';
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
const DOCUMENT_TYPES = new Set([
  'application/javascript',
  'text/javascript',
  'application/json',
  'text/plain',
  'application/pdf',
  'application/zip',
  'application/octet-stream',
]);
const DOCUMENT_EXTENSIONS = new Set([
  '.js', '.mjs', '.cjs', '.ts', '.tsx', '.jsx', '.json', '.txt', '.log',
  '.md', '.swift', '.plist', '.zip', '.pdf', '.csv', '.xml', '.html', '.css',
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
      const extension = path.extname(file.originalname || '').toLowerCase();
      const supported = MEDIA_TYPES.has(file.mimetype)
        || DOCUMENT_TYPES.has(file.mimetype)
        || DOCUMENT_EXTENSIONS.has(extension);
      callback(supported ? null : new Error('unsupported_attachment'), supported);
    },
  });

  router.use(express.json({ limit: '32kb' }));
  router.use('/uploads', express.static(uploadDir, { fallthrough: false, maxAge: '1d' }));

  router.post('/register', (request, response, next) => {
    try {
      const user = upsertUser(request.body, request.ip, { countAccess: true });
      scheduleLocationUpdate(user.user_id, request.ip);
      response.json(publicUserState(user, loadDatabase()));
    } catch (error) {
      next(error);
    }
  });

  router.post('/heartbeat', (request, response, next) => {
    try {
      const user = upsertUser(request.body, request.ip);
      scheduleLocationUpdate(user.user_id, request.ip);
      response.json(publicUserState(user, loadDatabase()));
    } catch (error) {
      next(error);
    }
  });

  // The authorized developer installation can grant or revoke download access
  // for a registered device without opening the browser admin panel.
  router.post('/developer/grant-download', (request, response) => {
    const payload = request.body || {};
    const developerUserID = text(payload.developer_user_id, 80).toLowerCase();
    const targetUserID = text(payload.target_user_id, 80).toLowerCase();
    const requestedTargetPublicUserID = text(
      payload.target_public_user_id || (!USER_ID_PATTERN.test(targetUserID) ? targetUserID : ''),
      24
    );
    if (!isDeveloperDeviceID(developerUserID)) {
      return response.status(401).json({ ok: false, message: 'developer_unauthorized' });
    }
    if (!USER_ID_PATTERN.test(targetUserID) && !isValidPublicUserID(requestedTargetPublicUserID)) {
      return response.status(422).json({ ok: false, message: 'invalid_user_id' });
    }

    let updatedUser;
    mutateDatabase((database) => {
      const userKey = findUserKey(database, targetUserID, requestedTargetPublicUserID);
      const user = userKey ? database.users[userKey] : null;
      if (!user) return;
      const enabled = Boolean(payload.download_unlocked);
      user.download_unlocked = enabled;
      if (!Array.isArray(user.download_access_history)) {
        user.download_access_history = [];
      }
      user.download_access_history.unshift({
        enabled,
        changed_at: now(),
        changed_by: developerUserID,
      });
      user.download_access_history = user.download_access_history.slice(0, 100);
      updatedUser = user;
    });
    if (!updatedUser) {
      return response.status(404).json({ ok: false, message: 'user_not_found' });
    }
    return response.json(publicUserState(updatedUser));
  });

  // The developer can grant a badge, select its visual style, and assign an
  // unused user-facing ID for any registered device.
  router.post('/developer/grant-exclusive-id', (request, response) => {
    const payload = request.body || {};
    const developerUserID = text(payload.developer_user_id, 80).toLowerCase();
    const targetUserID = text(payload.target_user_id, 80).toLowerCase();
    const requestedTargetPublicUserID = text(
      payload.target_public_user_id || (!USER_ID_PATTERN.test(targetUserID) ? targetUserID : ''),
      24
    );
    const assignedPublicUserID = text(payload.assigned_public_user_id, 24);
    const enabled = payload.exclusive_id !== false;
    const badgeStyle = normalizeExclusiveBadgeStyle(payload.exclusive_badge_style);

    if (!isDeveloperDeviceID(developerUserID)) {
      return response.status(401).json({ ok: false, message: 'developer_unauthorized' });
    }
    if (!USER_ID_PATTERN.test(targetUserID) && !isValidPublicUserID(requestedTargetPublicUserID)) {
      return response.status(422).json({ ok: false, message: 'invalid_user_id' });
    }
    if (assignedPublicUserID && !isValidPublicUserID(assignedPublicUserID)) {
      return response.status(422).json({ ok: false, message: 'invalid_public_user_id' });
    }

    const database = loadDatabase();
    const userKey = findUserKey(database, targetUserID, requestedTargetPublicUserID);
    const targetUser = userKey ? database.users[userKey] : null;
    if (!targetUser) {
      return response.status(404).json({ ok: false, message: 'user_not_found' });
    }
    if (assignedPublicUserID && publicIDBelongsToAnotherUser(database, assignedPublicUserID, targetUser.user_id)) {
      return response.status(409).json({ ok: false, message: 'public_user_id_taken' });
    }

    let updatedUser;
    mutateDatabase((nextDatabase) => {
      const user = nextDatabase.users[userKey];
      if (!user) return;
      if (assignedPublicUserID) user.public_user_id = assignedPublicUserID;
      user.exclusive_id = enabled;
      user.exclusive_badge_style = badgeStyle;
      if (!Array.isArray(user.exclusive_id_history)) {
        user.exclusive_id_history = [];
      }
      user.exclusive_id_history.unshift({
        enabled: Boolean(user.exclusive_id),
        public_user_id: user.public_user_id,
        exclusive_badge_style: user.exclusive_badge_style,
        changed_at: now(),
        changed_by: developerUserID,
      });
      user.exclusive_id_history = user.exclusive_id_history.slice(0, 100);
      updatedUser = user;
    });
    return response.json(publicUserState(updatedUser));
  });

  router.get('/developer/exclusive-access', (request, response) => {
    const developerUserID = text(request.query.developer_user_id, 80).toLowerCase();
    if (!isDeveloperDeviceID(developerUserID)) {
      return response.status(401).json({ ok: false, message: 'developer_unauthorized' });
    }

    const database = loadDatabase();
    const records = Object.values(database.users)
      .filter((user) => Boolean(user.exclusive_id) || Array.isArray(user.exclusive_id_history) && user.exclusive_id_history.length > 0)
      .map((user) => {
        const history = Array.isArray(user.exclusive_id_history) ? user.exclusive_id_history : [];
        const latest = history[0] || {};
        return {
          user_id: user.user_id,
          public_user_id: user.public_user_id || '',
          device_model: user.device_model,
          device_name: user.device_name,
          system_name: user.system_name,
          system_version: user.system_version,
          app_version: user.app_version,
          app_build: user.app_build,
          last_seen_at: user.last_seen_at,
          enabled: Boolean(user.exclusive_id),
          exclusive_badge_style: normalizeExclusiveBadgeStyle(user.exclusive_badge_style),
          changed_at: text(latest.changed_at || user.last_seen_at, 64),
        };
      })
      .sort((left, right) => right.changed_at.localeCompare(left.changed_at))
      .slice(0, 500);
    return response.json({ ok: true, records });
  });

  router.get('/developer/download-access', (request, response) => {
    const developerUserID = text(request.query.developer_user_id, 80).toLowerCase();
    if (!isDeveloperDeviceID(developerUserID)) {
      return response.status(401).json({ ok: false, message: 'developer_unauthorized' });
    }

    const database = loadDatabase();
    const records = Object.values(database.users)
      .flatMap((user) => {
        const history = Array.isArray(user.download_access_history)
          ? user.download_access_history
          : (user.download_unlocked ? [{ enabled: true, changed_at: user.last_seen_at || '' }] : []);
        return history.map((entry) => ({
          user_id: user.user_id,
          public_user_id: user.public_user_id || '',
          device_model: user.device_model,
          device_name: user.device_name,
          system_name: user.system_name,
          system_version: user.system_version,
          app_version: user.app_version,
          app_build: user.app_build,
          last_seen_at: user.last_seen_at,
          enabled: Boolean(entry.enabled),
          changed_at: text(entry.changed_at, 64),
        }));
      })
      .sort((left, right) => right.changed_at.localeCompare(left.changed_at))
      .slice(0, 500);
    return response.json({ ok: true, records });
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
          replies: [],
          submitted_at: submittedAt,
        });
      });

      return response.json({
        feedback_id: feedbackID,
        submitted_at: submittedAt,
        ...publicUserState(loadDatabase().users[user.user_id], loadDatabase()),
      });
    } catch (error) {
      removeUploadedFiles(request.files);
      return next(error);
    }
  });

  router.get('/feedback/mine', (request, response) => {
    const userID = text(request.query.user_id, 80);
    if (!USER_ID_PATTERN.test(userID)) {
      return response.status(422).json({ ok: false, message: 'invalid_user_id' });
    }
    const database = loadDatabase();
    const feedback = database.feedback
      .filter((item) => item.user_id === userID)
      .slice(0, 100);
    return response.json({ ok: true, feedback });
  });

  router.delete('/feedback/mine/:id', (request, response) => {
    const userID = text(
      request.get('x-beans-user-id') || request.body?.user_id || request.query.user_id,
      80
    );
    const feedbackID = text(request.params.id, 80);
    if (!USER_ID_PATTERN.test(userID)) {
      return response.status(422).json({ ok: false, message: 'invalid_user_id' });
    }

    let removedFeedback;
    mutateDatabase((database) => {
      const index = database.feedback.findIndex(
        (item) => item.id === feedbackID && item.user_id === userID
      );
      if (index >= 0) {
        removedFeedback = database.feedback.splice(index, 1)[0];
      }
    });
    if (!removedFeedback) {
      return response.status(404).json({ ok: false, message: 'feedback_not_found' });
    }
    removeFeedbackAttachments(removedFeedback);
    return response.json({ ok: true, feedback_id: feedbackID });
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
    const requestedPublicUserID = text(payload.public_user_id, 24);
    if (!USER_ID_PATTERN.test(userID)) {
      return response.status(422).json({ ok: false, message: 'invalid_user_id' });
    }
    if (requestedPublicUserID && !isValidPublicUserID(requestedPublicUserID)) {
      return response.status(422).json({ ok: false, message: 'invalid_public_user_id' });
    }
    const database = loadDatabase();
    if (requestedPublicUserID && publicIDBelongsToAnotherUser(database, requestedPublicUserID, userID)) {
      return response.status(409).json({ ok: false, message: 'public_user_id_taken' });
    }
    let updatedUser;
    mutateDatabase((database) => {
      const user = database.users[userID];
      if (!user) {
        return;
      }
      user.is_blacklisted = Boolean(payload.is_blacklisted);
      user.download_unlocked = Boolean(payload.download_unlocked);
      if (requestedPublicUserID) user.public_user_id = requestedPublicUserID;
      user.exclusive_id = Boolean(payload.exclusive_id);
      user.exclusive_badge_style = normalizeExclusiveBadgeStyle(payload.exclusive_badge_style || user.exclusive_badge_style);
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
    '/admin/feedback/:id/reply',
    browserAdmin,
    upload.array('reply_attachments[]', MAX_ATTACHMENTS),
    (request, response) => {
      const replyText = text(request.body?.reply, 8000);
      const attachments = (request.files || []).map((file) => ({
        name: file.filename,
        original_name: text(file.originalname, 180),
        mime_type: file.mimetype,
        size: file.size,
        url: `/beans/uploads/${encodeURIComponent(file.filename)}`,
      }));
      if (!replyText && attachments.length === 0) {
        removeUploadedFiles(request.files);
        return response.redirect('/beans/admin/feedback');
      }

      let updated = false;
      mutateDatabase((database) => {
        const feedback = database.feedback.find((item) => item.id === request.params.id);
        if (!feedback) {
          return;
        }
        if (!Array.isArray(feedback.replies)) {
          feedback.replies = [];
        }
        feedback.replies.push({
          id: crypto.randomUUID(),
          text: replyText,
          attachments,
          sent_at: now(),
        });
        updated = true;
      });
      if (!updated) {
        removeUploadedFiles(request.files);
        return response.status(404).json({ ok: false, message: 'feedback_not_found' });
      }
      return response.status(201).json({ ok: true, feedback_id: request.params.id });
    }
  );

  router.post(
    '/admin/user',
    browserAdmin,
    express.urlencoded({ extended: false }),
    (request, response) => {
      const userID = text(request.body.user_id, 80);
      const requestedPublicUserID = text(request.body.public_user_id, 24);
      const requestedExclusive = request.body.exclusive_id === 'on';
      if (requestedPublicUserID && !isValidPublicUserID(requestedPublicUserID)) {
        return response.status(422).send('用户 ID 最多 24 个字符，不能包含空格。');
      }
      const database = loadDatabase();
      const existingUser = database.users[userID];
      if (!existingUser) {
        return response.redirect('/beans/admin/users');
      }
      if (requestedPublicUserID && publicIDBelongsToAnotherUser(database, requestedPublicUserID, userID)) {
        return response.status(409).send('这个用户 ID 已被其他设备使用。');
      }
      mutateDatabase((database) => {
        const user = database.users[userID];
        if (!user) {
          return;
        }
        user.is_blacklisted = request.body.is_blacklisted === 'on';
        user.download_unlocked = request.body.download_unlocked === 'on';
        if (requestedPublicUserID) user.public_user_id = requestedPublicUserID;
        user.exclusive_id = requestedExclusive;
        user.exclusive_badge_style = normalizeExclusiveBadgeStyle(request.body.exclusive_badge_style || user.exclusive_badge_style);
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
      if (error.code === 'LIMIT_FILE_SIZE') {
        return response.status(413).json({ ok: false, message: 'attachment_too_large' });
      }
      if (error.code === 'LIMIT_FILE_COUNT' || error.code === 'LIMIT_UNEXPECTED_FILE') {
        return response.status(422).json({ ok: false, message: 'too_many_attachments' });
      }
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
      const reportedListeningSeconds = listeningSeconds(payload?.listening_seconds);
      const reportedListeningPlayCount = listeningPlayCount(payload?.listening_play_count);
      const publicUserID = resolvePublicUserID(database, userID, payload?.public_user_id, existing?.public_user_id);
      if (options.countAccess) {
        database.stats.access_count += 1;
        database.stats.last_access_at = timestamp;
      }
      record = {
        user_id: userID,
        public_user_id: publicUserID,
        device_model: text(payload.model, 128),
        device_name: text(payload.device_name, 128),
        system_name: text(payload.system, 128),
        system_version: text(payload.system_version, 64),
        app_version: text(payload.app_version, 64) || existing?.app_version || '',
        app_build: text(payload.app_build, 64) || existing?.app_build || '',
        listening_seconds: Math.max(listeningSeconds(existing?.listening_seconds), reportedListeningSeconds),
        listening_play_count: Math.max(listeningPlayCount(existing?.listening_play_count), reportedListeningPlayCount),
        first_seen_at: existing?.first_seen_at || timestamp,
        last_seen_at: timestamp,
        last_ip: text(ip, 64),
        location: existing?.location || '',
        location_updated_at: existing?.location_updated_at || '',
        is_blacklisted: Boolean(existing?.is_blacklisted),
        download_unlocked: Boolean(existing?.download_unlocked),
        download_access_history: Array.isArray(existing?.download_access_history)
          ? existing.download_access_history
          : [],
        exclusive_id: Boolean(existing?.exclusive_id),
        exclusive_badge_style: normalizeExclusiveBadgeStyle(existing?.exclusive_badge_style),
        exclusive_id_history: Array.isArray(existing?.exclusive_id_history)
          ? existing.exclusive_id_history
          : [],
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
    const attachments = [
      ...(feedback?.attachments || []),
      ...(feedback?.replies || []).flatMap((reply) => reply.attachments || []),
    ];
    attachments.forEach((attachment) => {
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

function publicUserState(user, database = null) {
  return {
    ok: true,
    public_user_id: user?.public_user_id || null,
    exclusive_id: Boolean(user?.exclusive_id),
    exclusive_badge_style: normalizeExclusiveBadgeStyle(user?.exclusive_badge_style),
    blocked: Boolean(user?.is_blacklisted),
    download_unlocked: Boolean(user?.download_unlocked),
    listening_seconds: listeningSeconds(user?.listening_seconds),
    listening_play_count: listeningPlayCount(user?.listening_play_count),
    feedback_replies: database
      ? database.feedback
        .filter((item) => item.user_id === user?.user_id)
        .flatMap((item) => (item.replies || []).map((reply) => ({
          feedback_id: item.id,
          ...reply,
        })))
        .slice(-100)
      : [],
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

function isDeveloperDeviceID(value) {
  const digest = crypto.createHash('sha256').update(String(value).toLowerCase()).digest('hex');
  return secureEqual(digest, DEVELOPER_DEVICE_ID_HASH);
}

function resolvePublicUserID(database, internalUserID, requestedValue, existingValue) {
  const existing = text(existingValue || requestedValue, 24);
  if (isValidPublicUserID(existing) && !publicIDBelongsToAnotherUser(database, existing, internalUserID)) {
    return existing;
  }

  if (isDeveloperDeviceID(internalUserID)
    && !publicIDBelongsToAnotherUser(database, DEVELOPER_INITIAL_PUBLIC_USER_ID, internalUserID)) {
    return DEVELOPER_INITIAL_PUBLIC_USER_ID;
  }

  for (let attempt = 0; attempt < 100; attempt += 1) {
    const candidate = String(Math.floor(Math.random() * (PUBLIC_USER_ID_MAX - PUBLIC_USER_ID_MIN + 1)) + PUBLIC_USER_ID_MIN);
    if (!publicIDBelongsToAnotherUser(database, candidate, internalUserID)) return candidate;
  }

  for (let candidate = PUBLIC_USER_ID_MIN; candidate <= PUBLIC_USER_ID_MAX; candidate += 1) {
    const value = String(candidate);
    if (!publicIDBelongsToAnotherUser(database, value, internalUserID)) return value;
  }

  throw new Error('public_user_id_exhausted');
}

function publicIDBelongsToAnotherUser(database, publicUserID, internalUserID) {
  return Object.values(database.users).some((user) =>
    user?.public_user_id === publicUserID && user.user_id !== internalUserID
  );
}

function findUserKey(database, targetUserID, targetPublicUserID) {
  if (isValidPublicUserID(targetPublicUserID)) {
    const publicMatch = Object.keys(database.users).find((key) => database.users[key]?.public_user_id === targetPublicUserID);
    if (publicMatch) return publicMatch;
  }
  return Object.keys(database.users).find((key) => key.toLowerCase() === targetUserID);
}

function isValidPublicUserID(value) {
  const candidate = String(value || '').trim();
  return candidate.length >= 1
    && candidate.length <= 24
    && !/[\s\x00-\x1f\x7f]/.test(candidate);
}

function normalizeExclusiveBadgeStyle(value) {
  return value === 'classic_gold' ? 'classic_gold' : 'black_purple_gold';
}

function listeningSeconds(value) {
  const seconds = Number(value);
  if (!Number.isFinite(seconds)) return 0;
  // 客户端只会在真实播放时累积；这里限制上报值，避免异常数据污染统计。
  return Math.max(0, Math.min(Math.floor(seconds), 100 * 365 * 24 * 60 * 60));
}

function listeningPlayCount(value) {
  const count = Number(value);
  if (!Number.isFinite(count)) return 0;
  return Math.max(0, Math.min(Math.floor(count), 1_000_000_000));
}

function formatListeningDuration(value) {
  const totalMinutes = Math.floor(listeningSeconds(value) / 60);
  const days = Math.floor(totalMinutes / (24 * 60));
  const hours = Math.floor((totalMinutes % (24 * 60)) / 60);
  const minutes = totalMinutes % 60;
  if (days > 0) return `${days} 天 ${hours} 小时 ${minutes} 分钟`;
  if (hours > 0) return `${hours} 小时 ${minutes} 分钟`;
  return `${minutes} 分钟`;
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
  if (extensions[file.mimetype]) {
    return extensions[file.mimetype];
  }
  const originalExtension = path.extname(file.originalname || '').toLowerCase();
  return DOCUMENT_EXTENSIONS.has(originalExtension) ? originalExtension : '.bin';
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

function isUserInactive(user, timestamp = Date.now()) {
  const lastSeen = Date.parse(user?.last_seen_at || '');
  return Number.isFinite(lastSeen) && timestamp - lastSeen >= INACTIVE_USER_WINDOW_MS;
}

function versionUsage(database, timestamp = Date.now()) {
  const usage = new Map();
  for (const user of Object.values(database.users)) {
    const appVersion = text(user.app_version, 64) || '未知版本';
    const appBuild = text(user.app_build, 64) || '未知构建';
    const key = `${appVersion}::${appBuild}`;
    const entry = usage.get(key) || {
      app_version: appVersion,
      app_build: appBuild,
      user_count: 0,
      online_users: 0,
      active_within_10_days: 0,
      inactive_10_days: 0,
      last_seen_at: '',
    };
    entry.user_count += 1;
    if (isUserOnline(user, timestamp)) entry.online_users += 1;
    if (isUserInactive(user, timestamp)) {
      entry.inactive_10_days += 1;
    } else {
      entry.active_within_10_days += 1;
    }
    if ((user.last_seen_at || '') > entry.last_seen_at) entry.last_seen_at = user.last_seen_at;
    usage.set(key, entry);
  }
  return Array.from(usage.values()).sort((left, right) => right.user_count - left.user_count || right.last_seen_at.localeCompare(left.last_seen_at));
}

function statsFor(database) {
  const timestamp = Date.now();
  const users = Object.values(database.users);
  return {
    total_users: users.length,
    access_count: database.stats.access_count,
    total_feedback: database.feedback.length,
    online_users: countOnlineUsers(database, timestamp),
    online_window_seconds: ONLINE_WINDOW_MS / 1000,
    inactive_window_days: INACTIVE_USER_WINDOW_MS / (24 * 60 * 60 * 1000),
    inactive_users_10_days: users.filter((user) => isUserInactive(user, timestamp)).length,
    active_within_10_days: users.filter((user) => !isUserInactive(user, timestamp)).length,
    total_listening_seconds: users.reduce((total, user) => total + listeningSeconds(user.listening_seconds), 0),
    version_usage: versionUsage(database, timestamp),
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
      <td class="id"><strong>${escapeHtml(user.public_user_id || '未分配')}</strong>${user.exclusive_id ? '<br><small style="color:#8a5a00;font-weight:700">专属 ID</small>' : ''}<br><small>设备：${escapeHtml(user.user_id)}</small><br><small>${escapeHtml(user.location || '位置获取中')}</small></td>
      <td>${escapeHtml(user.device_model || user.device_name)}<br><small>${escapeHtml(`${user.system_name} ${user.system_version}`)}</small></td>
      <td><span class="status ${isUserOnline(user) ? 'online' : 'offline'}">${isUserOnline(user) ? '在线' : '离线'}</span>${isUserInactive(user) ? '<br><small>超过 10 天未使用</small>' : ''}<br><small>${escapeHtml(user.last_seen_at)}</small></td>
      <td>${escapeHtml(`${user.app_version} (${user.app_build})`)}<br><small>首次：${escapeHtml(user.first_seen_at)}</small></td>
      <td><strong>${formatListeningDuration(user.listening_seconds)}</strong><br><small>${listeningSeconds(user.listening_seconds).toLocaleString('zh-CN')} 秒</small></td>
      <td><form method="post" action="/beans/admin/user"><input type="hidden" name="user_id" value="${escapeHtml(user.user_id)}"><label><input type="checkbox" name="is_blacklisted" ${user.is_blacklisted ? 'checked' : ''}> 拉黑</label><br><label><input type="checkbox" name="download_unlocked" ${user.download_unlocked ? 'checked' : ''}> 下载已解锁</label><br><label><input type="checkbox" name="exclusive_id" ${user.exclusive_id ? 'checked' : ''}> 专属 ID</label><br><select name="exclusive_badge_style"><option value="black_purple_gold" ${normalizeExclusiveBadgeStyle(user.exclusive_badge_style) === 'black_purple_gold' ? 'selected' : ''}>黑紫金</option><option value="classic_gold" ${normalizeExclusiveBadgeStyle(user.exclusive_badge_style) === 'classic_gold' ? 'selected' : ''}>经典金色</option></select><br><input name="public_user_id" value="${escapeHtml(user.public_user_id || '')}" maxlength="24" placeholder="改用户 ID（最多 24 字符）"><br><input name="action_note" value="${escapeHtml(user.action_note)}" placeholder="后台备注"><button>保存</button></form></td>
    </tr>
  `).join('');
  const versionRows = stats.version_usage.map((item) => `
    <tr>
      <td>${escapeHtml(`${item.app_version} (${item.app_build})`)}</td>
      <td>${item.user_count}</td>
      <td>${item.online_users}</td>
      <td>${item.active_within_10_days}</td>
      <td>${item.inactive_10_days}</td>
      <td>${escapeHtml(item.last_seen_at || '暂无记录')}</td>
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
    const replies = (item.replies || []).map((reply) => {
      const replyAttachments = (reply.attachments || []).map((attachment) => {
        const url = escapeHtml(attachment.url);
        if (attachment.mime_type?.startsWith('video/')) {
          return `<a href="${url}" target="_blank" rel="noopener">打开回复视频</a>`;
        }
        if (attachment.mime_type?.startsWith('image/')) {
          return `<a href="${url}" target="_blank" rel="noopener"><img class="reply-image" src="${url}" loading="lazy" alt="回复图片"></a>`;
        }
        return `<a href="${url}" target="_blank" rel="noopener">打开回复附件</a>`;
      }).join(' ');
      return `<div class="reply"><strong>后台回复</strong><small>${escapeHtml(reply.sent_at || '')}</small><div class="problem">${escapeHtml(reply.text || '')}</div><div class="media">${replyAttachments}</div></div>`;
    }).join('');
    const replyForm = `<form class="reply-form" method="post" action="/beans/admin/feedback/${encodeURIComponent(item.id)}/reply" enctype="multipart/form-data"><textarea name="reply" rows="3" maxlength="8000" placeholder="回复内容（可只上传附件）"></textarea><input type="file" name="reply_attachments[]" accept="*/*" multiple><button>发送回复</button></form>`;
    const deleteButton = `<form method="post" action="/beans/admin/feedback/${encodeURIComponent(item.id)}/delete" onsubmit="return confirm('确定删除这条反馈工单？')"><button class="danger">删除工单</button></form>`;
    return `<tr><td>${escapeHtml(item.submitted_at)}</td><td class="id">${escapeHtml(item.user_id)}</td><td>${escapeHtml(item.phone_model)}<br><small>${escapeHtml(item.phone_system)}</small></td><td class="problem">${escapeHtml(item.problem)}<div class="media">${attachments}</div>${replies}${replyForm}</td><td>${deleteButton}</td></tr>`;
  }).join('');

  const body = section === 'users'
    ? `<section class="panel"><h2>用户列表 <small>用户 ID 绑定设备，在线状态按最近 ${ONLINE_WINDOW_MS / 60000} 分钟心跳计算</small></h2><table><thead><tr><th>用户 ID / 设备标识 / 位置</th><th>设备 / 系统</th><th>在线状态</th><th>版本 / 时间</th><th>Beans 听歌时长</th><th>管理</th></tr></thead><tbody>${userRows || emptyRow('暂无用户')}</tbody></table></section>`
    : section === 'feedback'
      ? `<section class="panel"><h2>反馈列表</h2><table><thead><tr><th>时间</th><th>用户</th><th>填写设备</th><th>反馈内容与附件</th><th>操作</th></tr></thead><tbody>${feedbackRows || emptyRow('暂无反馈')}</tbody></table></section>`
      : `<section class="metrics"><article class="metric"><small>总用户</small><b>${stats.total_users}</b></article><article class="metric"><small>软件访问量</small><b>${stats.access_count}</b></article><article class="metric"><small>Beans 总听歌时长</small><b>${formatListeningDuration(stats.total_listening_seconds)}</b></article><article class="metric"><small>当前在线</small><b>${stats.online_users}</b><small>最近 ${ONLINE_WINDOW_MS / 60000} 分钟有心跳</small></article><article class="metric"><small>超过 ${stats.inactive_window_days} 天未使用</small><b>${stats.inactive_users_10_days}</b></article><article class="metric"><small>反馈数量</small><b>${stats.total_feedback}</b></article></section><section class="panel"><h2>版本使用统计</h2><table><thead><tr><th>版本 / Build</th><th>用户数</th><th>在线</th><th>${stats.inactive_window_days} 天内活跃</th><th>超过 ${stats.inactive_window_days} 天未使用</th><th>最近活跃</th></tr></thead><tbody>${versionRows || emptyRow('暂无版本数据')}</tbody></table></section><section class="panel overview"><h2>使用情况</h2><p>最近一次访问：${escapeHtml(stats.last_access_at || '暂无记录')}</p><p>在线用户通过应用每分钟心跳更新，离开超过 ${ONLINE_WINDOW_MS / 60000} 分钟后自动视为离线；超过 ${stats.inactive_window_days} 天没有心跳的用户会计入未使用统计。</p></section>`;

  return `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Beans 后台</title><style>:root{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#182230;background:#f8fafc}body{margin:0}.page{max-width:1600px;margin:0 auto;padding:28px}.bar{margin-bottom:24px}.bar h1{font-size:25px;margin:0}.bar p,small{color:#667085}.nav{display:flex;gap:8px;flex-wrap:wrap;margin:18px 0}.nav a{color:#344054;text-decoration:none;background:#fff;border:1px solid #d0d5dd;border-radius:8px;padding:8px 12px}.nav a.active{color:#fff;background:#182230;border-color:#182230}.metrics{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:14px}.metric,.panel{background:#fff;border:1px solid #eaecf0;border-radius:12px}.metric{padding:18px}.metric b{display:block;font-size:30px;margin-top:8px}.panel{overflow:auto;margin-top:20px}.panel h2{font-size:17px;padding:18px 18px 0;margin:0}.overview{padding-bottom:18px}.overview p{padding:0 18px;color:#667085}table{width:100%;border-collapse:collapse;font-size:13px}th,td{padding:12px 14px;border-bottom:1px solid #eaecf0;vertical-align:top;text-align:left}th{color:#667085;background:#fcfcfd}.id{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;word-break:break-all}.problem{max-width:500px;white-space:pre-wrap;word-break:break-word}.media{margin-top:7px;display:flex;gap:8px;flex-wrap:wrap}.media a{color:#175cd3;text-decoration:none}.feedback-media{display:inline-flex;flex-direction:column;gap:5px;margin:6px 8px 0 0;vertical-align:top}.feedback-media img,.feedback-media video,.reply-image{display:block;width:min(240px,40vw);max-height:220px;object-fit:cover;border-radius:8px;background:#101828}.reply{margin-top:12px;padding:10px;border-left:3px solid #f79009;background:#fffaeb}.reply strong{display:block;color:#b54708}.reply-form{display:grid;gap:7px;margin-top:12px}.reply-form textarea{width:100%;box-sizing:border-box;padding:8px;border:1px solid #d0d5dd;border-radius:6px;font:inherit}.status{display:inline-block;border-radius:999px;padding:3px 8px;font-size:12px}.status.online{color:#067647;background:#ecfdf3}.status.offline{color:#667085;background:#f2f4f7}input[name=action_note]{width:150px;box-sizing:border-box;padding:6px;border:1px solid #d0d5dd;border-radius:6px}button{border:0;border-radius:7px;padding:7px 10px;background:#182230;color:#fff;cursor:pointer}@media(max-width:1300px){.metrics{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:900px){.metrics{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:650px){.page{padding:16px}.metrics{grid-template-columns:1fr}.feedback-media img,.feedback-media video,.reply-image{width:min(260px,70vw)}}</style><body><main class="page"><header class="bar"><h1>Beans 后台</h1><p>用户、反馈与访问情况</p><nav class="nav"><a class="${section === 'overview' ? 'active' : ''}" href="/beans/admin">概览</a><a class="${section === 'users' ? 'active' : ''}" href="/beans/admin/users">用户</a><a class="${section === 'feedback' ? 'active' : ''}" href="/beans/admin/feedback">反馈</a></nav></header>${body}</main></body></html>`;

  function emptyRow(label) {
    const columnCount = section === 'users' ? 6 : 5;
    return `<tr><td colspan="${columnCount}" style="color:#667085;text-align:center;padding:28px">${escapeHtml(label)}</td></tr>`;
  }
}

module.exports = { createBeansRouter };

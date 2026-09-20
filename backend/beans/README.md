# Beans backend module

现有服务器响应为 Node / Express，因此此目录提供 Express 路由模块。

安装依赖并在服务器项目中挂载：

```js
const { createBeansRouter } = require('./backend/beans/beansBackend');

app.use('/beans', createBeansRouter({
  storageDir: '/var/lib/beans-music',
  adminPassword: process.env.BEANS_ADMIN_PASSWORD,
}));
```

客户端会调用：

- `POST /beans/register`：应用启动时自动登记匿名、Keychain 持久化的设备 ID。
- `POST /beans/heartbeat`：应用运行期间定时更新最后活跃时间和本机累计听歌秒数，用于后台在线状态检测。
- `POST /beans/feedback`：接收必填手机型号、系统与问题；图片和视频为可选附件。
- `GET /beans/feedback/mine?user_id=...`：应用读取当前设备提交的反馈记录、后台回复及回复附件。
- `DELETE /beans/feedback/mine/:id`：应用删除当前设备自己的反馈工单，并同时清理关联附件。
- `DELETE /beans/feedback/:id`：管理员删除反馈工单，并同时清理关联的图片/视频附件。
- `POST /beans/developer/grant-exclusive-id`：开发者为已登记设备开启或取消专属 ID 铭牌，并可分配唯一的 6 至 7 位公共 ID。
- `GET /beans/developer/exclusive-access`：读取专属 ID 授权记录。

后台主服务挂载后，用户、反馈、访问量和在线状态会整合到现有 `/admin` 后台的“用户”和“反馈”页面，不再要求单独打开 Beans 管理页面。浏览器反馈页可以用文字、图片或视频回复工单，回复会在应用心跳时返回并提示用户；浏览器删除工单使用 `POST /beans/admin/feedback/:id/delete`，会同时清理原始附件和回复附件。后台可以查看总用户、软件访问量、在线用户、设备与系统信息、每台设备的 Beans 累计听歌时长、反馈及附件，并可拉黑用户、解锁下载、授权专属 ID、修改公共 ID 和记录后台备注。普通用户使用银色铭牌，专属用户使用黑紫金铭牌；`5201314` 仅保留给开发者设备，其他公共 ID 必须唯一。概览页会显示全体用户的累计听歌时长，并按“版本 + Build”统计用户数、在线数、10 天内活跃数和超过 10 天未使用数。在线用户定义为最近 3 分钟收到过心跳的设备。`beans-data/` 需保留在服务器，且不要提交到仓库。

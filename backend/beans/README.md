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
- `POST /beans/heartbeat`：应用运行期间定时更新最后活跃时间，用于后台在线状态检测。
- `POST /beans/feedback`：接收必填手机型号、系统与问题；图片和视频为可选附件。
- `DELETE /beans/feedback/:id`：管理员删除反馈工单，并同时清理关联的图片/视频附件。

后台主服务挂载后，用户、反馈、访问量和在线状态会整合到现有 `/admin` 后台的“用户”和“反馈”页面，不再要求单独打开 Beans 管理页面。模块保留 `/beans/admin` 及其子页面作为兼容入口；浏览器删除工单使用 `POST /beans/admin/feedback/:id/delete`，会同时清理关联附件。后台可以查看总用户、软件访问量、在线用户、设备与系统信息、反馈及附件，并可拉黑用户、解锁下载和记录后台备注。在线用户定义为最近 3 分钟收到过心跳的设备。`beans-data/` 需保留在服务器，且不要提交到仓库。

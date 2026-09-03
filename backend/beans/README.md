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
- `POST /beans/feedback`：接收必填手机型号、系统与问题；图片和视频为可选附件。

后台入口为 `GET /beans/admin`，使用 HTTP Basic Auth 和 `BEANS_ADMIN_PASSWORD` 登录。后台可以查看总用户、设备与系统信息、反馈及附件，并可拉黑用户、解锁下载和记录后台备注。`beans-data/` 需保留在服务器，且不要提交到仓库。

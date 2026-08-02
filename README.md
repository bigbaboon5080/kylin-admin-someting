# kylin-admin-someting

一些kylin操作系统运维相关的资料和工具

## 功能说明

- `hello.sh`：测试脚本，输出一个问候信息
- （以后每增加一个脚本，在这里补充一个说明）

## 使用方法

克隆仓库到本地

```bash
git clone https://github.com/bigbaboon5080/kylin-admin-something.git
cd kylin-admin-something
```

给脚本添加执行权限

```bash
chmod +x hello.sh
```

运行

```bash
./hello.sh
```

## 环境要求

- Bash
- linux系统，部分脚本运行可能需要 **root** 权限，需要通过 **sudo** 方式运行

## 注意事项

- 脚本涉及的**密码、密钥等敏感信息**请放在 `.env` 或 `config.local.sh` 文件中，这些配置文件已在 `.gitignore` 中排除


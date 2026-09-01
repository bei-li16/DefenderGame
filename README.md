# DefenderGame 方案仓库

本仓库使用分支保存互斥的技术方案，避免在同一实现中同时维护两套引擎。

| 分支 | 用途 |
|---|---|
| `main` | 归档 2026-09-01 的移动跨平台需求与架构基线，不在此分支开发 |
| `windows-unity` | Unity 6.3 LTS、C#、Windows x64、本地单机优先 |
| `windows-godot` | Godot 4.7.2、GDScript、Windows x64、最轻工具链优先 |

查看方案：

```powershell
git switch windows-unity
git switch windows-godot
```

详细产品研究保存在 `main`；方案分支的文档只保留实现所需结论，并通过范围门禁阻止首版重新引入移动端、服务器、账号和支付系统。

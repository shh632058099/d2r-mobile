# 使用 GitHub Actions 编译 IPA

本仓库是公开仓库，构建过程会生成包含从你自己的游戏文件预处理得到的程序与着色器的中间文件。因此，工作流**不会**把这些文件放进本仓库的 Actions Artifacts、缓存或 Releases。所有中间文件和最终 IPA 都只存放在你指定的**私有构建仓库**中，临时构建 Release 会在工作流结束时清理。

## 一次性配置

1. 新建一个专门存放构建产物的 **Private** GitHub 仓库，例如 `你的账号/d2r-mobile-build-private`，创建时勾选 README 以初始化默认分支。不要把生成的 IPA 或预处理包发布到公开仓库。
2. 创建一个仅能访问该私有仓库的 Fine-grained Personal Access Token，授予该仓库 **Contents: Read and write** 权限。
3. 在本源码仓库的 **Settings → Secrets and variables → Actions** 中添加 Secret：
   - `BUILD_TOKEN`：上一步的 Token。
   - `SOURCE_TOKEN`：可选。只有源码仓库是私有仓库时才需要，授予源码仓库 Contents 读取权限。
4. 如需从自己的游戏文件生成预处理包，还要配置两个 Secret：
   - `GAME_ARCHIVE`：JSON，包含原始游戏文件压缩包的 HTTPS 下载地址和 SHA-256。
   - `LEGACY_METADATA`：JSON，包含同一游戏资源版本的 Legacy 元数据 ZIP 下载地址和 SHA-256。

例如，输入 Secret 的格式如下；请替换为你自己有权使用的文件地址与真实 SHA-256，不要把游戏文件或下载凭据提交到 Git：

```json
{"url":"https://example.invalid/your-own-archive.zip","sha256":"<64 位 SHA-256>"}
```

## 生成预处理包（首次构建或游戏资源版本变化时）

1. 打开 **Actions → Prepare iOS input → Run workflow**。
2. `output_repository` 填私有构建仓库的 `OWNER/REPO`。
3. 默认源码是 `shh632058099/d2r-mobile@main`；需要测试其他分支、标签或提交时，修改 `source_repository` 和 `source_ref`。
4. 等待完成。工作流会把 `D2RMobile-Prepared.zip` 和 `Prepared-SHA256SUMS.txt` 发布到私有构建仓库的 Release。

## 编译 IPA

1. 打开 **Actions → Build IPA → Run workflow**。
2. 填写：
   - `output_repository`：同一个私有构建仓库的 `OWNER/REPO`。
   - `source_repository` / `source_ref`：要编译的源码仓库和分支；默认是本仓库的 `main`。
   - `prepared_input`：指向私有 Release 资产的 JSON。可以在私有仓库中查看资产 ID，然后使用 API 资产 URL：

```json
{
  "url": "https://api.github.com/repos/OWNER/PRIVATE_REPO/releases/assets/PREPARED_ZIP_ASSET_ID",
  "sha256_url": "https://api.github.com/repos/OWNER/PRIVATE_REPO/releases/assets/SHA256SUMS_ASSET_ID"
}
```

`sha256_url` 应指向同一 Release 中的 `Prepared-SHA256SUMS.txt`。也可以直接填写 `sha256` 字段（64 位十六进制值），两者不能同时填写。工作流使用 `BUILD_TOKEN` 下载私有资产并校验 SHA-256。

3. 成功后，到私有构建仓库的 **Releases** 下载：
   - `D2RMobile-<版本>-build.<运行编号>.<尝试次数>.ipa`：iOS 26 及以上。
   - `D2RMobile-<版本>-build.<运行编号>.<尝试次数>-ios18.ipa`：iOS 18–25。
   - `SHA256SUMS.txt` 和 `build-report.json`：校验与构建报告。

## 注意事项

- 本工作流不签发 Apple 开发者签名；请使用你信任的侧载工具签名并安装 IPA。
- 游戏 Data 文件和老设备需要的 Legacy Device Pack 不包含在 IPA 中，需按项目说明从你自己的合法游戏副本准备并导入设备。
- 不要把 `BUILD_TOKEN`、原始游戏文件、预处理包或 IPA 上传到公开仓库。工作流禁用了公开仓库的构建缓存和 Actions Artifacts；请保留私有输出仓库的访问控制。
- 首次构建会重新生成界面资源，因未使用公开仓库缓存，耗时可能比复用缓存的构建更长。

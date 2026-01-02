这份 README 旨在让你的项目看起来更专业，并清晰地引导其他开发者（或你自己）在不同场景下快速上手。

---

# AI Code Reviewer (AICR) 🤖

**AI Code Reviewer** 是一款专为 Ruby 项目设计的自动化代码评审工具。它结合了 **RuboCop** 的静态扫描能力与 **大语言模型 (LLM)** 的智能分析能力，能够精准识别代码中的规范问题、逻辑漏洞及性能瓶颈。

### 🌟 核心特性

* **精准评审**：基于 `git diff`，只评审本次改动的代码行，拒绝扩大 Change Scope。
* **双重保障**：RuboCop 负责格式和规范，AI 负责逻辑和架构。
* **隐私保护**：支持 `--skip-ai` 模式，并可配置本地 LLM（如 Ollama）。
* **自动发布**：支持自动将建议作为 Line Comments 发布至 GitHub Pull Request。

---

## 🚀 快速开始 (Usage)

### 1. 环境准备

确保你的环境中安装了 Ruby 3.x，并获取了 AI 平台的 API Key（如通义千问、OpenAI 或 DeepSeek）。

### 2. 安装

克隆仓库并安装依赖：

```bash
git clone https://github.com/your-repo/ai-code-review.git
cd ai-code-review
bundle install

```

### 3. 配置环境变量

在项目根目录创建 `.env` 文件：

```text
AI_API_URL=https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions
AI_API_KEY=your_api_key_here
AI_MODEL_NAME=qwen-max
GITHUB_TOKEN=your_github_personal_access_token # 用于发布 PR 评论

```

### 4. 运行

* **本地干跑 (Dry Run)**：仅在终端输出建议，不发布到 GitHub。
```bash
bundle exec bin/ai-code-review -d

```


* **仅进行静态扫描**：不调用 AI，适合快速检查格式。
```bash
bundle exec bin/ai-code-review --skip-ai

```


* **正式评审并发布到 PR**：
```bash
bundle exec bin/ai-code-review --repo "owner/repo" --pr 123

```



---

## 🛠 别处如何使用 (Integration)

如果你想在**其他项目**或其他环境（如 CI/CD）中使用此工具，有以下三种方式：

### 方案 A：作为全局系统命令 (本地推荐)

你可以通过 alias 将其变成全局工具：

1. 在 `~/.zshrc` 或 `~/.bashrc` 中添加：
```bash
alias aicr='BUNDLE_GEMFILE=/path/to/ai-code-review/Gemfile bundle exec ruby /path/to/ai-code-review/bin/ai-code-review'

```


2. 进入**任何 Ruby 项目**，直接运行 `aicr -d` 即可。

### 方案 B：在 GitHub Actions 中自动评审 (CI 推荐)

在目标项目的 `.github/workflows/ai_review.yml` 中添加以下配置。这样每次提交 PR 时，AI 都会自动开始工作：

```yaml
name: AI Code Review
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2 # 必须获取前一个提交以进行 git diff

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'

      - name: Run AI Reviewer
        env:
          AI_API_KEY: ${{ secrets.AI_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          # 假设将本工具通过 git submodule 或直接下载使用
          bundle install
          bundle exec bin/ai-code-review --repo ${{ github.repository }} --pr ${{ github.event.pull_request.number }}

```

### 方案 C：内部私有 Gem

你可以将本项目打包成 Gem，在其他项目的 `Gemfile` 中通过 `git` 引用：

```ruby
group :development do
  gem 'ai_code_review', git: 'https://github.com/your-org/ai-code-review.git', branch: 'main'
end

```

然后在目标项目执行 `bundle exec ai-code-review`。

---

## 🤝 贡献指南

1. Fork 本仓库。
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)。
3. 提交改动 (`git commit -m 'Add some AmazingFeature'`)。
4. 推送到分支 (`git push origin feature/AmazingFeature`)。
5. 开启 Pull Request。

---

**你想让我为你补充一个具体的 `action.yml` 文件，好让它能直接作为独立的 GitHub Action 发布在 Marketplace 吗？**
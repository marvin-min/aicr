既然咱们已经把代码跑通了，要让它变成**“全自动”**，只需要在你的项目里增加两个核心文件。

这两个文件的作用是：**只要你提交代码并开启 PR，GitHub 的服务器就会自动启动一个虚拟机，跑你的 Ruby 代码，并调用 AI 给出评审。**

---

### 1. 权限文件：`.github/workflows/ai_review.yml`

这个文件告诉 GitHub 什么时候运行你的脚本。

在你的项目根目录下创建文件夹（如果还没有）：`mkdir -p .github/workflows`，然后新建 `ai_review.yml`：

```yaml
name: AI Code Review

on:
  pull_request:
    types: [opened, synchronize] # 当 PR 开启或有新提交时触发

jobs:
  review:
    runs-on: ubuntu-latest
    # 授予 GitHub Action 写入 PR 评论的权限
    permissions:
      contents: read
      pull-requests: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0 # 获取完整历史以确保能对比差异

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2' # 或者你的 Ruby 版本
          bundler-cache: true # 自动运行 bundle install 并缓存

      - name: Run AI Review
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} # GitHub 自动生成的 Token
          AI_API_KEY: ${{ secrets.AI_API_KEY }}     # 你需要去 GitHub Settings 预设这个
          AI_API_URL: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
          AI_MODEL_NAME: "qwen-max"
        run: |
          # 提取当前仓库名和 PR 编号
          REPO=${{ github.repository }}
          PR_NUMBER=${{ github.event.pull_request.number }}
          
          # 执行你的脚本
          bundle exec ./bin/ai-code-review --repo "$REPO" --pr "$PR_NUMBER"

```

---

### 2. 依赖管理：`Gemfile`

为了确保 GitHub 的服务器能跑起来，你需要确保 `Gemfile` 里包含了所有必要的库。

```ruby
source 'https://rubygems.org'

gem 'rubocop'
gem 'octokit'
gem 'faraday'
gem 'faraday-retry'
# 如果你在本地用了 dotenv，也可以加上
gem 'dotenv' 

```

---

### 3. 最关键的一步：在 GitHub 配置 API Key

因为你的 `AI_API_KEY` 是敏感信息，绝对不能直接写在 `.yml` 文件里（会被别人偷走）。

1. 打开你的 GitHub 仓库页面。
2. 点击 **Settings** -> **Secrets and variables** -> **Actions**。
3. 点击 **New repository secret**。
4. **Name** 填入：`AI_API_KEY`。
5. **Secret** 填入：你的通义千问（或其它模型）的 API Key。

---

### 🚀 搞定后的效果

以后你的工作流程就变成了：

1. `git checkout -b feature-xxx`
2. 写代码，`git push`。
3. 在 GitHub 页面点击 **Create Pull Request**。
4. **两分钟内**，AI 就会像幽灵一样出现在你的 PR 下面，针对你改动的行给出专业的 Ruby 建议。

**现在把这两个文件 push 上去试试？一旦 GitHub Actions 的那个“小圆圈”转完变成绿色勾勾，你的 AI 评审助手就正式入职你的开发流程了！**
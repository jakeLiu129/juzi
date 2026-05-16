#!/bin/bash
# =============================================================
# 桔子论坛 自动注册+登录+发帖 系统
#
# 使用方式: bash auto-register-post.sh [手机号] [昵称]
#
# 功能：
#   1. 打开桔子网站 → 进入社区
#   2. 点击底部"账号"，打开登录弹窗
#   3. 输入手机号 → 发送验证码 → 填写昵称 → 注册/登录
#   4. 点击"发帖" → 填写标题/内容 → 发布帖子
#   5. 失败自动重试，持续尝试直到成功
# =============================================================

# ── agent-browser 路径（路径含空格，务必用引号包裹） ──
AB_BIN="/Applications/LobsterAI.app/Contents/Frameworks/LobsterAI Helper.app/Contents/lib/node_modules/agent-browser/bin/agent-browser-darwin-arm64"

# ── 配置 ──
URL="http://localhost:8000"
PHONE="${1:-13800138001}"
NICKNAME="${2:-桔友}"
POST_TITLE="极简主义的美好生活 🌿"
POST_CONTENT=$(cat <<'ENDOFCONTENT'
自从开始践行极简主义，我学会了珍惜真正重要的东西。
少即是多，轻装上阵 —— 分享给所有想要简化生活的朋友 🍊
ENDOFCONTENT
)

MAX_RETRIES=20
RETRY_DELAY=2

log() {
  echo "[$(date '+%H:%M:%S')] $1"
}

# ── 助手函数：执行 agent-browser 命令 ──
ab() {
  "$AB_BIN" "$@"
}

# ── 获取单个 eval 结果（去掉引号） ──
ab_eval() {
  ab eval "$1" 2>/dev/null | tr -d '"'
}

ab_eval_stdin() {
  ab eval --stdin 2>/dev/null | tr -d '"'
}

# ── 清理浏览器会话 ──
cleanup() {
  ab close 2>/dev/null
  sleep 1
}

# ── 步骤1：打开网站 ──
step_open_site() {
  log "📂 打开桔子网站 $URL ..."
  ab open "$URL" 2>/dev/null || return 1
  ab wait --load networkidle 2>/dev/null || sleep 2
  return 0
}

# ── 步骤2：确保在论坛页面 ──
step_ensure_forum() {
  log "📋 切换到桔子社区..."
  ab eval 'switchTab("forum")' 2>/dev/null
  sleep 1
  return 0
}

# ── 步骤3：注册/登录 ──
step_register_login() {
  log "🔑 打开账号弹窗..."
  ab eval 'openAccount()' 2>/dev/null
  sleep 0.8

  # 检查是否已登录
  local user
  user=$(ab eval 'localStorage.getItem("juzi_account")' 2>/dev/null)
  if [ -n "$user" ] && [ "$user" != "null" ] && [ "$user" != "" ]; then
    local label
    label=$(ab eval 'document.getElementById("accountBtnLabel")?.textContent || ""' 2>/dev/null | tr -d '"')
    log "  已登录: $label，跳过注册"
    return 0
  fi

  log "📱 填写手机号 $PHONE ..."
  ab eval --stdin <<EVALEOF 2>/dev/null
(function(){
  document.getElementById('authPhone').value = '$PHONE';
  document.getElementById('authPhone').dispatchEvent(new Event('input',{bubbles:true}));
  return 'ok';
})()
EVALEOF
  sleep 0.3

  log "📨 发送验证码..."
  ab eval 'sendSmsCode()' 2>/dev/null
  sleep 0.5

  local code
  code=$(ab eval 'document.getElementById("authCode")?.value || ""' 2>/dev/null | tr -d '"')
  log "  验证码: $code"

  # 首次登录/注册点击
  log "🔓 登录/注册..."
  ab eval 'loginByPhone()' 2>/dev/null
  sleep 0.5

  # 如果需要昵称（首次注册）
  local nickname_display
  nickname_display=$(ab eval 'document.getElementById("authNicknameRow")?.style?.display || "none"' 2>/dev/null | tr -d '"')
  if [ "$nickname_display" = "flex" ] || [ "$nickname_display" = "block" ]; then
    log "✏️ 首次注册，填写昵称: $NICKNAME ..."
    ab eval --stdin <<EVALEOF 2>/dev/null
(function(){
  document.getElementById('authNickname').value = '$NICKNAME';
  document.getElementById('authNickname').dispatchEvent(new Event('input',{bubbles:true}));
  return 'ok';
})()
EVALEOF
    sleep 0.3
    ab eval 'loginByPhone()' 2>/dev/null
    sleep 0.5
  fi

  # 验证登录
  local label
  label=$(ab eval 'document.getElementById("accountBtnLabel")?.textContent || ""' 2>/dev/null | tr -d '"')
  if [ -n "$label" ] && [ "$label" != "账号" ]; then
    log "✅ 登录成功！用户名: $label"
    return 0
  fi

  return 1
}

# ── 步骤4：发布帖子 ──
step_post() {
  log "✍️ 打开发帖页面..."
  ab eval 'showCreatePost()' 2>/dev/null
  sleep 0.5

  log "📝 填写标题..."
  ab eval --stdin <<'EVALEOF' 2>/dev/null
(function(){
  document.getElementById('postTitle').value = '极简主义的美好生活 🌿';
  document.getElementById('postTitle').dispatchEvent(new Event('input',{bubbles:true}));
  return 'ok';
})()
EVALEOF
  sleep 0.3

  log "📝 填写内容..."
  ab eval --stdin <<'EVALEOF' 2>/dev/null
(function(){
  document.getElementById('postContent').value = '自从开始践行极简主义，我学会了珍惜真正重要的东西。\n少即是多，轻装上阵 —— 分享给所有想要简化生活的朋友 🍊';
  document.getElementById('postContent').dispatchEvent(new Event('input',{bubbles:true}));
  return 'ok';
})()
EVALEOF
  sleep 0.3

  log "🚀 提交帖子..."
  ab eval 'submitPost()' 2>/dev/null
  sleep 1

  # 验证帖子是否发布
  local count
  count=$(ab eval 'JSON.parse(localStorage.getItem("juzi_forum_topics")||"[]").length' 2>/dev/null | tr -d '"')
  if [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null; then
    local title
    title=$(ab eval 'JSON.parse(localStorage.getItem("juzi_forum_topics")||"[]")[0]?.title || "none"' 2>/dev/null | tr -d '"')
    log "✅ 发帖成功！帖子数: $count, 标题: $title"
    return 0
  fi

  return 1
}

# ── 主流程（带重试） ──
main() {
  log "🍊 桔子论坛 自动注册/登录/发帖"
  log "   目标: $URL"
  log "   手机号: $PHONE"
  log "   昵称: $NICKNAME"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━"

  local attempt=1
  local success=false

  while [ $attempt -le $MAX_RETRIES ]; do
    log "🔄 尝试 #$attempt"

    cleanup

    if ! step_open_site; then
      log "  ⚠️ 打开网站失败"
      attempt=$((attempt + 1))
      sleep $RETRY_DELAY
      continue
    fi

    if ! step_ensure_forum; then
      log "  ⚠️ 切换论坛失败"
      attempt=$((attempt + 1))
      sleep $RETRY_DELAY
      continue
    fi

    if ! step_register_login; then
      log "  ⚠️ 注册/登录失败"
      attempt=$((attempt + 1))
      sleep $RETRY_DELAY
      continue
    fi

    if ! step_post; then
      log "  ⚠️ 发帖失败"
      attempt=$((attempt + 1))
      sleep $RETRY_DELAY
      continue
    fi

    success=true
    break
  done

  echo ""
  if [ "$success" = true ]; then
    log "🎉 全部完成！注册登录发帖成功！"
    log "   手机号: $PHONE  |  昵称: $NICKNAME"
  else
    log "❌ 经过 $MAX_RETRIES 次尝试，所有步骤均失败"
  fi

  # 截图留存
  local screenshot
  screenshot=$(ab screenshot --full 2>/dev/null)
  log "📸 截图: $screenshot"

  cleanup
}

main

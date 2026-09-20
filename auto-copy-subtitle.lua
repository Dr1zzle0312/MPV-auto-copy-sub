-- auto-copy-subtitle.lua - Auto copy subtitles to Windows clipboard
-- Platform: Windows only
-- Features: 手动全屏复制 / 自动字幕+去重+关键词屏蔽
local auto_copy_enabled = false
local observer_id = nil
---------- 配置项 ----------
local config = {
    -- 自动复制：保留底部几行作为主字幕（此配置项保留，但不再生效，方便你后续改回去）
    keep_bottom_lines = 1,
    -- 自动复制：相邻去重（和上一次内容一样则不复制）
    enable_adjacent_dedup = true,
    -- 自动复制：固定字幕自动黑名单（连续出现多次则永久过滤）
    enable_fixed_blacklist = true,
    fixed_threshold = 3,
    -- 自动复制：关键词屏蔽列表，包含任意关键词的行直接过滤
    block_keywords = {"仅供学习", "版权所有","本字幕","商业用途"},
}
---------------------------
-- 状态变量
local last_copied = ""
local current_text_count = {}
local fixed_blacklist = {}
-- Windows剪贴板复制函数
local function copy_to_clipboard(text)
    if not text or text == "" then return end
    local escaped = text:gsub("'", "''")
    mp.commandv(
        "run",
        "powershell.exe",
        "-command",
        "Set-Clipboard -Value '" .. escaped .. "'"
    )
end
-- 检查文本是否包含屏蔽关键词
local function has_block_keyword(text)
    for _, kw in ipairs(config.block_keywords) do
        if text:find(kw, 1, true) then
            return true
        end
    end
    return false
end
-- 自动复制用：过滤关键词，【不再只提取底部N行，保留全部剩下的字幕行】
local function filter_auto_subtitle(full_text)
    if not full_text or full_text == "" then return nil end
    
    local lines = {}
    for line in full_text:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        -- 跳过空行 和 包含屏蔽关键词的行
        if line ~= "" and not has_block_keyword(line) then
            table.insert(lines, line)
        end
    end
    
    if #lines == 0 then return nil end

    -- ========= 改动：直接返回全部过滤后的行，删除取底部N行逻辑 =========
    return table.concat(lines, "\n")
end
-- 自动复制去重 + 固定字幕判定
local function should_auto_copy(text)
    if not text or text == "" then return false end
    
    -- 黑名单过滤
    if config.enable_fixed_blacklist and fixed_blacklist[text] then
        return false
    end
    
    -- 相邻去重
    if config.enable_adjacent_dedup and text == last_copied then
        return false
    end
    
    -- 固定字幕计数判定
    if config.enable_fixed_blacklist then
        current_text_count[text] = (current_text_count[text] or 0) + 1
        if current_text_count[text] >= config.fixed_threshold then
            fixed_blacklist[text] = true
            return false
        end
    end
    
    last_copied = text
    return true
end
-- ========== 手动复制：全屏所有内容，不受任何规则 ==========
local function manual_copy_subtitle()
    local subtitle = mp.get_property("sub-text")
    if subtitle and subtitle ~= "" then
        copy_to_clipboard(subtitle)
        mp.osd_message("✅ 全屏字幕已复制到剪贴板", 1.5)
    else
        mp.osd_message("⚠️ 当前无字幕", 1.5)
    end
end
-- 切换自动复制功能
local function toggle_auto_copy()
    auto_copy_enabled = not auto_copy_enabled
    
    if auto_copy_enabled then
        observer_id = mp.observe_property("sub-text", "native", function(_, value)
            local filtered = filter_auto_subtitle(value)
            if filtered and should_auto_copy(filtered) then
                copy_to_clipboard(filtered)
            end
        end)
        mp.osd_message("🟢 自动复制已启用 (全部字幕行+去重+关键词屏蔽)", 2)
    else
        if observer_id then
            mp.unobserve_property(observer_id)
            observer_id = nil
        end
        mp.osd_message("🔴 自动复制已禁用", 2)
    end
end
-- 切换视频时重置状态
mp.register_event("file-loaded", function()
    last_copied = ""
    current_text_count = {}
    fixed_blacklist = {}
    if auto_copy_enabled then
        mp.osd_message("🟢 自动复制已启用 (全部字幕行+去重+关键词屏蔽)", 2)
    end
end)
-- 绑定快捷键
mp.add_key_binding("Ctrl+c", "manual-copy", manual_copy_subtitle)
mp.add_key_binding("Ctrl+Shift+c", "toggle-auto-copy", toggle_auto_copy)
-- 初始状态提示
mp.osd_message("📌 字幕复制脚本已加载\n" ..
              "• Ctrl+C = 手动复制全屏所有字幕\n" ..
              "• Ctrl+Shift+C = 切换自动复制", 3)

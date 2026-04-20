local M = {}

local state = {
  cache = {},
  cache_gen = 0,
  cache_hits = 0,
  cache_misses = 0,
  history = {},
  last = nil,
  active_job = nil,
  intent_preferences = {},
  keymaps = {},
  cf_watch_enabled = false,
  cf_test_running = false,
  cf_test_pending = false,
  cf_profile = nil,
}

local defaults = {
  create_commands = true,
  create_keymaps = true,
  keymaps = {
    run = "<leader>r",
    pick = "<leader>rp",
    last = "<leader>rl",
    legacy = "<leader>R",
  },
  root = {
    use_lsp = true,
    resolver = nil,
    markers = {
      ".git",
      "package.json",
      "pyproject.toml",
      "uv.lock",
      "poetry.lock",
      "requirements.txt",
      "go.mod",
      "Cargo.toml",
      "CMakeLists.txt",
      "Makefile",
      "meson.build",
      "pom.xml",
      "build.gradle",
      "build.gradle.kts",
      "settings.gradle",
      "settings.gradle.kts",
      "build.sbt",
      "pubspec.yaml",
      "mix.exs",
      "composer.json",
      "Gemfile",
      "flake.nix",
      ".runic-cf.json",
    },
  },
  terminal = {
    use_snacks = false,
    focus = true,
    height = 12,
    close_keys = { "<Esc>", "q" },
    open_url = true,
    url_allowlist = { "localhost", "127.0.0.1", "::1" },
  },
  history = {
    size = 20,
  },
  overrides = {
    command = nil,
    filetype_commands = {},
    resolver = nil,
    python_project_runner = false,
  },
  rules = {
    disable = {},
    priority_overrides = {},
  },
  hooks = {
    on_before_run = nil,
    on_after_run = nil,
  },
  cf = {
    enabled = false,
    workspace_root = "~/codeforces",
    profile = "contest",
    profiles = {
      contest = {
        cxx = "g++",
        std = "gnu++17",
        flags = { "-O2", "-pipe", "-Wall", "-Wextra" },
        local_define = false,
      },
      debug = {
        cxx = "g++",
        std = "gnu++20",
        flags = { "-O0", "-g", "-Wall", "-Wextra", "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-D_GLIBCXX_DEBUG" },
        local_define = true,
      },
    },
    template = {
      source = "builtin",
      custom_path = nil,
    },
    sample = {
      auto_watch = false,
      dir = "samples",
      timeout_ms = 3000,
    },
    stress = {
      timeout_ms = 2000,
      max_cases = 500,
      save_counterexample = true,
    },
    check = {
      run_stress = false,
      stress_cases = 200,
    },
    submit = {
      auto_submit = true,
      confirm = true,
      language_id = "91",
      cookie_env = "RUNIC_CF_COOKIE",
    },
  },
}

local command_names = {
  "RunicRun",
  "RunicAction",
  "RunicPick",
  "RunicRunFile",
  "RunicRunProject",
  "RunicPreview",
  "RunicExplain",
  "RunicLast",
  "RunicHistory",
  "RunicCacheClear",
  "RunicCacheInfo",
  "RunicHealth",
  "RunicReload",
  "RunicStop",
  "RunicRestart",
  "RunicCFStart",
  "RunicCFModeOn",
  "RunicCFModeOff",
  "RunicCFStatus",
  "RunicCFProfile",
  "RunicCFImportSamples",
  "RunicCFTest",
  "RunicCFWatch",
  "RunicCFWatchStop",
  "RunicCFCheck",
  "RunicCFSubmit",
  "RunicCFAutoSubmit",
  "RunicCFStress",
  "RunicCFReplayFail",
}

local clear_commands
local register_commands
local register_keymaps

M.config = vim.deepcopy(defaults)

local function file_exists(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.type == "file"
end

local function has_exec(name)
  return vim.fn.executable(name) == 1
end

local function has_file(root, name)
  return file_exists(vim.fs.joinpath(root, name))
end

local function has_any_file(root, names)
  for _, name in ipairs(names) do
    if has_file(root, name) then
      return true
    end
  end
  return false
end

local function shellescape(value)
  return vim.fn.shellescape(value)
end

local function stem(path)
  return vim.fn.fnamemodify(path, ":t:r")
end

local function maybe(value, fallback)
  if value == nil then
    return fallback
  end
  return value
end

local function is_rule_disabled(rule_id)
  return M.config.rules.disable[rule_id] == true
end

local function with_priority(rule_id, base)
  local override = M.config.rules.priority_overrides[rule_id]
  return maybe(override, base)
end

local function candidate(rule_id, spec)
  local out = vim.deepcopy(spec)
  out.rule_id = rule_id
  out.priority = with_priority(rule_id, spec.priority)
  out.label = string.format("[%s] %s -> %s", out.kind, out.reason, out.command)
  return out
end

local function default_pm(root)
  if has_file(root, "pnpm-lock.yaml") then
    return "pnpm"
  end
  if has_file(root, "bun.lock") or has_file(root, "bun.lockb") then
    return "bun"
  end
  if has_file(root, "yarn.lock") then
    return "yarn"
  end
  return "npm"
end

local function command_for_script(pm, script)
  if pm == "npm" then
    return "npm run " .. script
  end
  return pm .. " run " .. script
end

local function read_package_scripts(root)
  local pkg = vim.fs.joinpath(root, "package.json")
  if not file_exists(pkg) then
    return {}
  end

  local ok_read, lines = pcall(vim.fn.readfile, pkg)
  if not ok_read then
    return {}
  end

  local ok_json, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok_json or type(data) ~= "table" or type(data.scripts) ~= "table" then
    return {}
  end

  return data.scripts
end

local function detect_root(bufnr, file)
  local function normalize(path)
    return vim.fs.normalize(path):gsub("/+$", "")
  end

  local function is_ancestor(parent, child)
    local p = normalize(parent)
    local c = normalize(child)
    if c == p then
      return true
    end
    return c:sub(1, #p + 1) == (p .. "/")
  end

  local file_dir = vim.fs.dirname(file)

  local resolver = M.config.root.resolver
  if type(resolver) == "function" then
    local ok, custom = pcall(resolver, {
      bufnr = bufnr,
      file = file,
      filetype = vim.bo[bufnr].filetype,
    })
    if ok and type(custom) == "string" and custom ~= "" then
      return vim.fs.normalize(custom), "custom"
    end
  end

  -- Always prefer markers near the current file path.
  local found = vim.fs.find(M.config.root.markers, {
    path = file_dir,
    upward = true,
    limit = 1,
  })
  if #found > 0 then
    return vim.fs.dirname(found[1]), "marker"
  end

  -- Use LSP root only if it actually contains the current file.
  if M.config.root.use_lsp then
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
      if client and client.config and type(client.config.root_dir) == "string" and client.config.root_dir ~= "" then
        local lsp_root = vim.fs.normalize(client.config.root_dir)
        if is_ancestor(lsp_root, file) then
          return lsp_root, "lsp"
        end
      end
    end
  end

  return file_dir, "file"
end

local function is_test_file(path)
  local name = vim.fn.fnamemodify(path, ":t")
  return name:match("_test%.") ~= nil
    or name:match("test_") ~= nil
    or name:match("%.test%.") ~= nil
    or name:match("%.spec%.") ~= nil
end

local function is_js_like(ctx)
  local ft = ctx.filetype
  return ft == "javascript"
    or ft == "javascriptreact"
    or ft == "typescript"
    or ft == "typescriptreact"
    or ft == "vue"
    or ft == "svelte"
    or ctx.ext == "js"
    or ctx.ext == "mjs"
    or ctx.ext == "cjs"
    or ctx.ext == "ts"
    or ctx.ext == "tsx"
end

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  return table.concat(lines, "\n")
end

local function write_file(path, content)
  local dir = vim.fs.dirname(path)
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile(vim.split(content, "\n", { plain = true }), path)
end

local function expand_path(path)
  return vim.fs.normalize(vim.fn.expand(path))
end

local function is_cpp_file(file)
  local ext = vim.fn.fnamemodify(file, ":e"):lower()
  return ext == "cpp" or ext == "cc" or ext == "cxx"
end

local function is_cf_workspace(root)
  local marker = vim.fs.joinpath(root, ".runic-cf.json")
  return file_exists(marker)
end

local function read_cf_meta(root)
  local marker = vim.fs.joinpath(root, ".runic-cf.json")
  local content = read_file(marker)
  if not content then
    return nil
  end
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then
    return nil
  end
  return data
end

local function write_cf_meta(root, data)
  local marker = vim.fs.joinpath(root, ".runic-cf.json")
  write_file(marker, vim.json.encode(data))
end

local function cf_solution_relative_path(root)
  local meta = read_cf_meta(root) or {}
  local rel = meta.solution_file
  if type(rel) ~= "string" or rel == "" then
    rel = "main.cpp"
  end
  return rel
end

local function cf_solution_path(root)
  return vim.fs.normalize(vim.fs.joinpath(root, cf_solution_relative_path(root)))
end

local function cf_builtin_template()
  return table.concat({
    "#include <bits/stdc++.h>",
    "using namespace std;",
    "",
    "using ll = long long;",
    "using pii = pair<int, int>;",
    "using vi = vector<int>;",
    "",
    "#ifdef LOCAL",
    "template <class T> void dbg_out(const char* name, const T& value) { cerr << name << \" = \" << value << '\\n'; }",
    "#define DBG(x) dbg_out(#x, x)",
    "#else",
    "#define DBG(x) ((void)0)",
    "#endif",
    "",
    "void solve() {",
    "  ",
    "}",
    "",
    "int main() {",
    "  ios::sync_with_stdio(false);",
    "  cin.tie(nullptr);",
    "",
    "  int t = 1;",
    "  // cin >> t;",
    "  while (t--) solve();",
    "  return 0;",
    "}",
    "",
  }, "\n")
end

local function cf_template_content()
  local source = M.config.cf.template.source
  local custom = M.config.cf.template.custom_path
  if source == "custom" and type(custom) == "string" and custom ~= "" then
    local c = read_file(expand_path(custom))
    if c and c ~= "" then
      return c
    end
  end
  return cf_builtin_template()
end

local function current_cf_profile_name()
  return state.cf_profile or M.config.cf.profile or "contest"
end

local function current_cf_profile()
  local name = current_cf_profile_name()
  return M.config.cf.profiles[name] or M.config.cf.profiles.contest
end

local function cf_binary_path(root, file)
  local base = stem(file)
  return vim.fs.joinpath(root, ".runic-bin", base)
end

local function cf_stress_binary_path(root, name)
  return vim.fs.joinpath(root, ".runic-bin", "stress-" .. name)
end

local function cf_compile_command(root, file)
  local prof = current_cf_profile()
  local cxx = prof.cxx or "g++"
  local std = prof.std or "gnu++17"
  local flags = prof.flags or {}
  local cmd_parts = {
    "mkdir -p .runic-bin &&",
    cxx,
    "-std=" .. std,
  }
  for _, fl in ipairs(flags) do
    cmd_parts[#cmd_parts + 1] = fl
  end
  if prof.local_define then
    cmd_parts[#cmd_parts + 1] = "-DLOCAL"
  end
  cmd_parts[#cmd_parts + 1] = shellescape(file)
  cmd_parts[#cmd_parts + 1] = "-o"
  cmd_parts[#cmd_parts + 1] = shellescape(cf_binary_path(root, file))
  return table.concat(cmd_parts, " ")
end

local function cf_compile_command_to(root, file, out_path)
  local prof = current_cf_profile()
  local cxx = prof.cxx or "g++"
  local std = prof.std or "gnu++17"
  local flags = prof.flags or {}
  local cmd_parts = {
    "mkdir -p .runic-bin &&",
    cxx,
    "-std=" .. std,
  }
  for _, fl in ipairs(flags) do
    cmd_parts[#cmd_parts + 1] = fl
  end
  if prof.local_define then
    cmd_parts[#cmd_parts + 1] = "-DLOCAL"
  end
  cmd_parts[#cmd_parts + 1] = shellescape(file)
  cmd_parts[#cmd_parts + 1] = "-o"
  cmd_parts[#cmd_parts + 1] = shellescape(out_path)
  return table.concat(cmd_parts, " ")
end

local function cf_run_command(root, file)
  local bin = cf_binary_path(root, file)
  local compile = cf_compile_command(root, file)
  return compile .. " && " .. shellescape(bin)
end

local function cf_samples_dir(root)
  return vim.fs.joinpath(root, M.config.cf.sample.dir or "samples")
end

local function list_sample_inputs(root)
  local dir = cf_samples_dir(root)
  local inputs = vim.fs.find(function(name)
    return name:match("%.in$") ~= nil
  end, { path = dir, type = "file", limit = math.huge })
  table.sort(inputs)
  return inputs
end

local function read_trimmed(path)
  local content = read_file(path)
  if not content then
    return nil
  end
  content = content:gsub("\r", "")
  content = content:gsub("%s+$", "")
  return content
end

local function preferred_intent_for(ctx)
  if not ctx or not ctx.root then
    return nil
  end
  return state.intent_preferences[ctx.root]
end

local function set_preferred_intent(ctx, intent)
  if not ctx or not ctx.root then
    return
  end
  state.intent_preferences[ctx.root] = intent
end

local function run_in_terminal(cmd, cwd)
  if (M.config.terminal.use_snacks or vim.g.runic_use_snacks_terminal == true) and _G.Snacks and Snacks.terminal then
    Snacks.terminal({ "zsh", "-lc", cmd }, { cwd = cwd })
    return
  end

  local prev_win = vim.api.nvim_get_current_win()
  vim.cmd("botright " .. tostring(M.config.terminal.height) .. "new")
  local term_win = vim.api.nvim_get_current_win()
  local term_buf = vim.api.nvim_get_current_buf()
  local focus_terminal = maybe(vim.g.runic_focus_terminal, M.config.terminal.focus)
  local open_url = maybe(vim.g.runic_open_url, M.config.terminal.open_url)
  local url_allowlist = M.config.terminal.url_allowlist or {}
  local opened_urls = {}
  local url_tail = ""

  vim.bo[term_buf].bufhidden = "wipe"
  vim.bo[term_buf].swapfile = false
  vim.b[term_buf].runic_terminal = true

  local function close_term_window()
    if vim.api.nvim_win_is_valid(term_win) then
      vim.api.nvim_win_close(term_win, true)
    end
  end

  for _, key in ipairs(M.config.terminal.close_keys) do
    if key == "q" then
      vim.keymap.set("n", key, close_term_window, { buffer = term_buf, silent = true, desc = "Close runic terminal" })
    else
      vim.keymap.set("n", key, close_term_window, { buffer = term_buf, silent = true, desc = "Close runic terminal" })
      vim.keymap.set("t", key, close_term_window, { buffer = term_buf, silent = true, desc = "Close runic terminal" })
    end
  end

  local function host_allowed(host)
    if type(host) ~= "string" or host == "" then
      return false
    end
    if #url_allowlist == 0 then
      return true
    end
    for _, allowed in ipairs(url_allowlist) do
      if host == allowed then
        return true
      end
    end
    return false
  end

  local function is_allowed_url(url)
    local host = url:match("^https?://([^/%?:#]+)")
    return host_allowed(host)
  end

  local function open_in_browser(url)
    if opened_urls[url] then
      return
    end
    if not is_allowed_url(url) then
      return
    end
    opened_urls[url] = true

    local opener
    if vim.fn.has("mac") == 1 then
      opener = { "open", url }
    elseif vim.fn.has("win32") == 1 then
      opener = { "cmd", "/c", "start", "", url }
    else
      opener = { "xdg-open", url }
    end

    if vim.fn.executable(opener[1]) ~= 1 then
      vim.schedule(function()
        vim.notify("Runic could not find browser opener. Open manually: " .. url, vim.log.levels.WARN)
      end)
      return
    end

    local job_id = vim.fn.jobstart(opener, { detach = true })
    if job_id <= 0 then
      vim.schedule(function()
        vim.notify("Runic failed to open browser. Open manually: " .. url, vim.log.levels.WARN)
      end)
      return
    end

    vim.schedule(function()
      vim.notify("Runic opened URL: " .. url, vim.log.levels.INFO)
    end)
  end

  local function detect_and_open_urls(text)
    if not open_url or type(text) ~= "string" or text == "" then
      return
    end

    for url in text:gmatch("\27%]8;;([^\7]+)\7") do
      open_in_browser(url)
    end

    local clean = text:gsub("\27%[[0-9;?]*[%a]", "")
    clean = clean:gsub("\27%]8;[^\7]*\7", "")
    clean = clean:gsub("\27%]8;;\7", "")

    local function scan_urls(s)
      local out = {}
      local i = 1
      while i <= #s do
        local local_url_s, local_url_e = s:find("https?://localhost:%d+[%w%-%._~:/%?#%[%]@!$&'%%(%)*+,;=]*", i)
        local loop_url_s, loop_url_e = s:find("https?://127%.0%.0%.1:%d+[%w%-%._~:/%?#%[%]@!$&'%%(%)*+,;=]*", i)
        local gen_url_s, gen_url_e = s:find("https?://[%w%-%._~:/%?#%[%]@!$&'%%(%)*+,;=]+", i)

        local next_s, next_e = nil, nil
        if local_url_s and (not next_s or local_url_s < next_s) then
          next_s, next_e = local_url_s, local_url_e
        end
        if loop_url_s and (not next_s or loop_url_s < next_s) then
          next_s, next_e = loop_url_s, loop_url_e
        end
        if gen_url_s and (not next_s or gen_url_s < next_s) then
          next_s, next_e = gen_url_s, gen_url_e
        end

        if not next_s then
          break
        end

        out[#out + 1] = s:sub(next_s, next_e)
        i = next_e + 1
      end
      return out
    end

    for _, url in ipairs(scan_urls(clean)) do
      open_in_browser(url)
    end
  end

  local function maybe_open_url_from_lines(data)
    if not open_url or type(data) ~= "table" then
      return
    end
    for _, line in ipairs(data) do
      if type(line) == "string" then
        local combined = url_tail .. line
        detect_and_open_urls(combined)
        url_tail = combined:sub(-300)
      end
    end
  end

  local job = vim.fn.termopen({ vim.o.shell, "-lc", cmd }, {
    cwd = cwd,
    on_stdout = function(_, data)
      maybe_open_url_from_lines(data)
    end,
    on_stderr = function(_, data)
      maybe_open_url_from_lines(data)
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify("Runic command exited with code " .. tostring(code), vim.log.levels.WARN)
        end)
      end
    end,
  })

  if job <= 0 then
    vim.notify("Runic could not start terminal job", vim.log.levels.ERROR)
    return
  end

  state.active_job = {
    id = job,
    cmd = cmd,
    cwd = cwd,
  }

  if focus_terminal then
    vim.cmd("startinsert")
    return
  end

  if vim.api.nvim_win_is_valid(prev_win) then
    vim.api.nvim_set_current_win(prev_win)
  end
end

local function add_history(entry)
  table.insert(state.history, 1, vim.deepcopy(entry))
  local max_size = math.max(1, M.config.history.size)
  while #state.history > max_size do
    table.remove(state.history)
  end
end

local function setup_cache_autocmds()
  vim.api.nvim_create_autocmd({ "BufWritePost", "DirChanged" }, {
    group = vim.api.nvim_create_augroup("runic-cache", { clear = true }),
    callback = function()
      state.cache_gen = state.cache_gen + 1
      state.cache = {}
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("runic-cf-watch", { clear = true }),
    callback = function(args)
      if not state.cf_watch_enabled then
        return
      end
      local file = vim.api.nvim_buf_get_name(args.buf)
      if file == "" or not is_cpp_file(file) then
        return
      end
      local root, source = detect_root(args.buf, file)
      if source and is_cf_workspace(root) then
        local saved = vim.fs.normalize(file)
        local solution = cf_solution_path(root)
        if saved ~= solution then
          return
        end
        vim.schedule(function()
          M.cf_test_async()
        end)
      end
    end,
  })
end

local function add_override_candidates(ctx)
  local out = {}
  local global_command = maybe(M.config.overrides.command, vim.g.runic_command)
  if type(global_command) == "string" and global_command ~= "" and not is_rule_disabled("override_global") then
    out[#out + 1] = candidate("override_global", {
      kind = "override",
      priority = 10000,
      command = global_command,
      cwd = ctx.root,
      reason = "Global override command",
    })
  end

  local by_ft = M.config.overrides.filetype_commands
  local global_by_ft = vim.g.runic_filetype_commands
  if type(by_ft) ~= "table" then
    by_ft = {}
  end
  if type(global_by_ft) == "table" then
    by_ft = vim.tbl_extend("keep", by_ft, global_by_ft)
  end
  local item = by_ft[ctx.filetype]
  if type(item) == "string" and item ~= "" and not is_rule_disabled("override_filetype") then
    out[#out + 1] = candidate("override_filetype", {
      kind = "override",
      priority = 9900,
      command = item,
      cwd = ctx.root,
      reason = "Filetype override command",
    })
  end

  local resolver = M.config.overrides.resolver
  if type(resolver) ~= "function" then
    resolver = vim.g.runic_resolver
  end
  if type(resolver) == "function" and not is_rule_disabled("override_resolver") then
    local ok, resolved = pcall(resolver, vim.deepcopy(ctx))
    if ok and type(resolved) == "table" then
      if type(resolved.command) == "string" and resolved.command ~= "" then
        out[#out + 1] = candidate("override_resolver", {
          kind = "override",
          priority = resolved.priority or 9800,
          command = resolved.command,
          cwd = resolved.cwd or ctx.root,
          reason = resolved.reason or "Custom resolver override",
        })
      elseif vim.islist(resolved) then
        for _, r in ipairs(resolved) do
          if type(r) == "table" and type(r.command) == "string" and r.command ~= "" then
            out[#out + 1] = candidate("override_resolver", {
              kind = "override",
              priority = r.priority or 9800,
              command = r.command,
              cwd = r.cwd or ctx.root,
              reason = r.reason or "Custom resolver candidate",
            })
          end
        end
      end
    end
  end

  return out
end

local function add_project_candidates(ctx)
  local out = {}
  local root = ctx.root
  local file = ctx.file

  if M.config.cf.enabled and is_cpp_file(file) and is_cf_workspace(root) and not is_rule_disabled("project_cf") then
    local run_cmd = cf_run_command(root, file)
    local inputs = list_sample_inputs(root)
    local has_samples = #inputs > 0
    out[#out + 1] = candidate("project_cf", {
      kind = "project",
      priority = 9800,
      command = run_cmd,
      cwd = root,
      reason = "Codeforces contest run",
    })

    if has_samples then
      local first = shellescape(inputs[1])
      out[#out + 1] = candidate("project_cf", {
        kind = "project",
        priority = 9750,
        command = run_cmd .. " < " .. first,
        cwd = root,
        reason = "Codeforces sample test (first case)",
      })
    end
  end

  if not is_rule_disabled("project_node") and is_js_like(ctx) and has_file(root, "package.json") then
    local pm = default_pm(root)
    local scripts = read_package_scripts(root)
    local order = is_test_file(file)
        and { "test", "dev", "start", "serve", "preview", "build" }
      or { "dev", "start", "serve", "preview", "build", "test" }
    local base_prio = 9000
    for idx, script in ipairs(order) do
      if scripts[script] then
        out[#out + 1] = candidate("project_node", {
          kind = "project",
          priority = base_prio - idx,
          command = command_for_script(pm, script),
          cwd = root,
          reason = string.format("Node script '%s' via %s", script, pm),
        })
      end
    end
  end

  local python_runner = M.config.overrides.python_project_runner or vim.g.runic_python_project_runner == true
  if not is_rule_disabled("project_python") and (ctx.filetype == "python" or ctx.ext == "py") and python_runner then
    if has_any_file(root, { "pyproject.toml", "uv.lock", "poetry.lock", "requirements.txt" }) then
      local qfile = shellescape(file)
      if has_exec("uv") then
        out[#out + 1] = candidate("project_python", { kind = "project", priority = 8800, command = "uv run " .. qfile, cwd = root, reason = "Python via uv" })
      elseif has_exec("poetry") then
        out[#out + 1] = candidate("project_python", { kind = "project", priority = 8700, command = "poetry run python " .. qfile, cwd = root, reason = "Python via poetry" })
      else
        out[#out + 1] = candidate("project_python", { kind = "project", priority = 8600, command = "python3 " .. qfile, cwd = root, reason = "Python via python3" })
      end
    end
  end

  if not is_rule_disabled("project_go") and has_file(root, "go.mod") then
    if is_test_file(file) then
      out[#out + 1] = candidate("project_go", { kind = "project", priority = 8500, command = "go test ./...", cwd = root, reason = "Go module test" })
      out[#out + 1] = candidate("project_go", { kind = "project", priority = 8400, command = "go run .", cwd = root, reason = "Go module run" })
    else
      out[#out + 1] = candidate("project_go", { kind = "project", priority = 8500, command = "go run .", cwd = root, reason = "Go module run" })
      out[#out + 1] = candidate("project_go", { kind = "project", priority = 8400, command = "go test ./...", cwd = root, reason = "Go module test" })
    end
  end

  if not is_rule_disabled("project_rust") and has_file(root, "Cargo.toml") then
    if is_test_file(file) then
      out[#out + 1] = candidate("project_rust", { kind = "project", priority = 8350, command = "cargo test", cwd = root, reason = "Rust cargo test" })
      out[#out + 1] = candidate("project_rust", { kind = "project", priority = 8340, command = "cargo run", cwd = root, reason = "Rust cargo run" })
    else
      out[#out + 1] = candidate("project_rust", { kind = "project", priority = 8350, command = "cargo run", cwd = root, reason = "Rust cargo run" })
      out[#out + 1] = candidate("project_rust", { kind = "project", priority = 8340, command = "cargo test", cwd = root, reason = "Rust cargo test" })
    end
  end

  if not is_rule_disabled("project_cmake") and has_file(root, "CMakeLists.txt") then
    out[#out + 1] = candidate("project_cmake", { kind = "project", priority = 8300, command = "cmake -S . -B build && cmake --build build", cwd = root, reason = "CMake configure + build" })
  end

  if not is_rule_disabled("project_make") and has_file(root, "Makefile") then
    out[#out + 1] = candidate("project_make", { kind = "project", priority = 8250, command = "make run", cwd = root, reason = "Make run" })
    out[#out + 1] = candidate("project_make", { kind = "project", priority = 8240, command = "make", cwd = root, reason = "Make default" })
  end

  if not is_rule_disabled("project_java_maven") and has_file(root, "pom.xml") then
    out[#out + 1] = candidate("project_java_maven", { kind = "project", priority = 8200, command = "mvn compile exec:java", cwd = root, reason = "Maven run" })
  end

  if not is_rule_disabled("project_java_gradle") and has_any_file(root, { "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts" }) then
    out[#out + 1] = candidate("project_java_gradle", { kind = "project", priority = 8150, command = "./gradlew run || gradle run", cwd = root, reason = "Gradle run" })
    out[#out + 1] = candidate("project_java_gradle", { kind = "project", priority = 8140, command = "./gradlew build || gradle build", cwd = root, reason = "Gradle build" })
  end

  if not is_rule_disabled("project_sbt") and has_file(root, "build.sbt") then
    out[#out + 1] = candidate("project_sbt", { kind = "project", priority = 8100, command = "sbt run", cwd = root, reason = "sbt run" })
  end

  if not is_rule_disabled("project_dotnet") then
    local has_csproj = #vim.fs.find("*.csproj", { path = root, type = "file", limit = 1 }) > 0
    if has_csproj or #vim.fs.find("*.sln", { path = root, type = "file", limit = 1 }) > 0 then
      out[#out + 1] = candidate("project_dotnet", { kind = "project", priority = 8050, command = "dotnet run", cwd = root, reason = ".NET run" })
    end
  end

  if not is_rule_disabled("project_dart") and has_file(root, "pubspec.yaml") then
    out[#out + 1] = candidate("project_dart", {
      kind = "project",
      priority = 8000,
      command = has_exec("flutter") and "flutter run" or "dart run",
      cwd = root,
      reason = "Dart/Flutter run",
    })
  end

  if not is_rule_disabled("project_elixir") and has_file(root, "mix.exs") then
    out[#out + 1] = candidate("project_elixir", { kind = "project", priority = 7950, command = "mix run", cwd = root, reason = "Elixir mix run" })
  end

  if not is_rule_disabled("project_php") and has_file(root, "composer.json") then
    out[#out + 1] = candidate("project_php", {
      kind = "project",
      priority = 7900,
      command = "composer run || php " .. shellescape(file),
      cwd = root,
      reason = "PHP composer",
    })
  end

  if not is_rule_disabled("project_ruby") and has_file(root, "Gemfile") then
    out[#out + 1] = candidate("project_ruby", {
      kind = "project",
      priority = 7850,
      command = "bundle exec ruby " .. shellescape(file),
      cwd = root,
      reason = "Ruby bundle",
    })
  end

  return out
end

local function parse_java_package(file)
  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok or type(lines) ~= "table" then
    return nil
  end
  for _, line in ipairs(lines) do
    local pkg = line:match("^%s*package%s+([%w_%.]+)%s*;%s*$")
    if pkg then
      return pkg
    end
    if line:match("^%s*import%s+") or line:match("^%s*public%s+") or line:match("^%s*class%s+") then
      break
    end
  end
  return nil
end

local function compile_and_run(file, compiler, out_name)
  local qfile = shellescape(file)
  local qout = shellescape(out_name)
  return string.format("mkdir -p .nvim-run && %s %s -o %s && %s", compiler, qfile, qout, qout)
end

local function add_file_candidates(ctx)
  local out = {}
  local file = ctx.file
  local ext = ctx.ext
  local qfile = shellescape(file)
  local out_bin = ".nvim-run/" .. stem(file)

  if not is_rule_disabled("file_c") and ext == "c" then
    local cc = has_exec("clang") and "clang" or "gcc"
    out[#out + 1] = candidate("file_c", { kind = "file", priority = 7000, command = compile_and_run(file, cc, out_bin), cwd = ctx.root, reason = "Single C file" })
  elseif not is_rule_disabled("file_cpp") and (ext == "cpp" or ext == "cc" or ext == "cxx") then
    local cxx = has_exec("clang++") and "clang++" or "g++"
    out[#out + 1] = candidate("file_cpp", { kind = "file", priority = 7000, command = compile_and_run(file, cxx, out_bin), cwd = ctx.root, reason = "Single C++ file" })
  elseif not is_rule_disabled("file_html") and ext == "html" then
    out[#out + 1] = candidate("file_html", { kind = "file", priority = 7000, command = "python3 -m http.server 8080", cwd = vim.fs.dirname(file), reason = "Serve HTML on :8080" })
  end

  local by_ext = {
    py = "python3 " .. qfile,
    rb = "ruby " .. qfile,
    php = "php " .. qfile,
    pl = "perl " .. qfile,
    lua = "lua " .. qfile,
    sh = "bash " .. qfile,
    zsh = "zsh " .. qfile,
    fish = "fish " .. qfile,
    ps1 = "pwsh -File " .. qfile,
    r = "Rscript " .. qfile,
    jl = "julia " .. qfile,
    go = "go run " .. qfile,
    rs = "mkdir -p .nvim-run && rustc " .. qfile .. " -o " .. shellescape(out_bin) .. " && " .. shellescape(out_bin),
    java = (function()
      local pkg = parse_java_package(file)
      local class_name = stem(file)
      if pkg then
        local fqcn = pkg .. "." .. class_name
        return "javac -d . " .. qfile .. " && java -cp . " .. shellescape(fqcn)
      end
      return "javac " .. qfile .. " && java " .. shellescape(class_name)
    end)(),
    kt = "kotlinc -script " .. qfile,
    swift = "swift " .. qfile,
    nim = "nim c -r " .. qfile,
    zig = "zig run " .. qfile,
    dart = "dart run " .. qfile,
    exs = "elixir " .. qfile,
    clj = "clojure " .. qfile,
    hs = "runhaskell " .. qfile,
    ml = "ocaml " .. qfile,
    js = "node " .. qfile,
    mjs = "node " .. qfile,
    cjs = "node " .. qfile,
    ts = has_exec("tsx") and ("tsx " .. qfile)
      or (has_exec("bun") and ("bun " .. qfile)
      or (has_exec("deno") and ("deno run " .. qfile)
      or (has_exec("ts-node") and ("ts-node " .. qfile)
      or (has_exec("node") and ("node --loader ts-node/esm " .. qfile)
      or nil)))),
    tsx = has_exec("tsx") and ("tsx " .. qfile)
      or (has_exec("bun") and ("bun " .. qfile)
      or (has_exec("deno") and ("deno run " .. qfile)
      or (has_exec("ts-node") and ("ts-node " .. qfile)
      or (has_exec("node") and ("node --loader ts-node/esm " .. qfile)
      or nil)))),
  }

  if not is_rule_disabled("file_ext") and by_ext[ext] then
    out[#out + 1] = candidate("file_ext", {
      kind = "file",
      priority = 6900,
      command = by_ext[ext],
      cwd = ctx.root,
      reason = "Single-file ." .. ext,
    })
  end

  if not is_rule_disabled("fallback_executable") and vim.fn.executable(file) == 1 then
    out[#out + 1] = candidate("fallback_executable", { kind = "fallback", priority = 3000, command = qfile, cwd = ctx.root, reason = "Executable file" })
  end

  if not is_rule_disabled("fallback_shebang") then
    local first = vim.fn.getline(1)
    if type(first) == "string" and first:sub(1, 2) == "#!" then
      out[#out + 1] = candidate("fallback_shebang", { kind = "fallback", priority = 2900, command = qfile, cwd = ctx.root, reason = "Shebang script" })
    end
  end

  return out
end

local function build_context(opts)
  local bufnr = opts.bufnr or 0
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" then
    return nil, "Current buffer has no file path"
  end

  file = vim.fs.normalize(file)
  if not file_exists(file) then
    return nil, "File is not saved on disk"
  end

  local root, root_source = detect_root(bufnr, file)
  return {
    bufnr = bufnr,
    file = file,
    filetype = vim.bo[bufnr].filetype,
    ext = vim.fn.fnamemodify(file, ":e"):lower(),
    root = root,
    root_source = root_source,
  }, nil
end

local function make_cache_key(ctx, mode)
  local fp = table.concat({
    tostring(state.cache_gen),
    mode,
    ctx.file,
    ctx.root,
    tostring(M.config.overrides.python_project_runner),
    tostring(M.config.terminal.use_snacks),
    tostring(M.config.terminal.focus),
  }, "\x1f")
  return fp
end

local function sort_candidates(items)
  table.sort(items, function(a, b)
    if a.priority == b.priority then
      return a.label < b.label
    end
    return a.priority > b.priority
  end)
end

local function resolve_candidates(opts)
  opts = opts or {}
  local mode = opts.mode or "auto"
  local intent = opts.intent
  local ctx, err = build_context(opts)
  if not ctx then
    return nil, nil, err
  end

  if not intent then
    intent = preferred_intent_for(ctx)
  end

  local key = make_cache_key(ctx, mode)
  if not opts.no_cache and state.cache[key] then
    state.cache_hits = state.cache_hits + 1
    return vim.deepcopy(state.cache[key].selected), vim.deepcopy(state.cache[key].candidates), nil
  end
  state.cache_misses = state.cache_misses + 1

  local candidates = {}
  local function append(list)
    for _, c in ipairs(list) do
      c.ctx = ctx
      candidates[#candidates + 1] = c
    end
  end

  append(add_override_candidates(ctx))
  if mode ~= "file" then
    append(add_project_candidates(ctx))
  end
  if mode ~= "project" then
    append(add_file_candidates(ctx))
  end

  if #candidates == 0 then
    return nil, nil, "No runic rule matched this file/project"
  end

  if type(intent) == "string" and intent ~= "" then
    local filtered = {}
    for _, c in ipairs(candidates) do
      local cmd = c.command:lower()
      if intent == "run" then
        if not cmd:match("%f[%a]test%f[%A]") and not cmd:match("%f[%a]build%f[%A]") then
          filtered[#filtered + 1] = c
        end
      elseif intent == "test" then
        if cmd:match("%f[%a]test%f[%A]") then
          filtered[#filtered + 1] = c
        end
      elseif intent == "build" then
        if cmd:match("%f[%a]build%f[%A]") or cmd:match("%f[%a]cmake%f[%A]") or cmd:match("%f[%a]make%f[%A]") then
          filtered[#filtered + 1] = c
        end
      elseif intent == "dev" then
        if cmd:match("%f[%a]dev%f[%A]") or cmd:match("%f[%a]serve%f[%A]") or cmd:match("http%.server") then
          filtered[#filtered + 1] = c
        end
      end
    end
    if #filtered > 0 then
      candidates = filtered
    end
  end

  sort_candidates(candidates)
  local selected = candidates[1]
  state.cache[key] = {
    selected = vim.deepcopy(selected),
    candidates = vim.deepcopy(candidates),
  }

  return selected, candidates, nil
end

function M.resolve(opts)
  local selected, _, err = resolve_candidates(opts)
  return selected, err
end

function M.preview(opts)
  local selected, candidates, err = resolve_candidates(opts)
  if not selected then
    vim.notify("Runic: " .. err, vim.log.levels.WARN)
    return
  end

  local lines = {
    "Runic Preview",
    string.rep("=", 12),
    "",
    "selected: " .. selected.label,
    "cwd: " .. selected.cwd,
    "root source: " .. selected.ctx.root_source,
    "file: " .. selected.ctx.file,
    "",
    "candidates:",
  }
  local max_items = math.min(#candidates, 10)
  for i = 1, max_items do
    lines[#lines + 1] = string.format("%d. %s", i, candidates[i].label)
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Runic" })
end

function M.explain(opts)
  return M.preview(opts)
end

function M.run(opts)
  local selected, _, err = resolve_candidates(opts)
  if not selected then
    vim.notify("Runic: " .. err, vim.log.levels.ERROR)
    return
  end

  if type(M.config.hooks.on_before_run) == "function" then
    pcall(M.config.hooks.on_before_run, selected, selected.ctx)
  end

  state.last = selected
  add_history(selected)
  vim.notify("Runic: " .. selected.reason, vim.log.levels.INFO)
  run_in_terminal(selected.command, selected.cwd)

  if type(M.config.hooks.on_after_run) == "function" then
    pcall(M.config.hooks.on_after_run, selected, selected.ctx)
  end
end

function M.action(opts)
  opts = opts or {}
  local ctx, _ = build_context({ bufnr = 0 })
  local in_cf = ctx and is_cf_workspace(ctx.root) and is_cpp_file(ctx.file)

  local intents
  if in_cf then
    intents = {
      { label = "Run", value = "run" },
      { label = "Test", value = "test" },
      { label = "Check", value = "check" },
      { label = "Submit", value = "submit" },
    }
  else
    intents = {
      { label = "Run", value = "run" },
      { label = "Test", value = "test" },
      { label = "Build", value = "build" },
      { label = "Dev", value = "dev" },
    }
  end

  vim.ui.select(intents, {
    prompt = "Runic action",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end

    if in_cf and choice.value == "check" then
      M.cf_check()
      set_preferred_intent(ctx, choice.value)
      return
    end
    if in_cf and choice.value == "submit" then
      M.cf_submit()
      set_preferred_intent(ctx, choice.value)
      return
    end

    local selected, _, err = resolve_candidates({ mode = opts.mode or "auto", intent = choice.value, no_cache = true })
    if not selected then
      vim.notify("Runic: " .. err, vim.log.levels.WARN)
      return
    end

    set_preferred_intent(selected.ctx, choice.value)
    state.last = selected
    add_history(selected)
    run_in_terminal(selected.command, selected.cwd)
  end)
end

function M.pick(opts)
  local _, candidates, err = resolve_candidates(opts)
  if not candidates then
    vim.notify("Runic: " .. err, vim.log.levels.WARN)
    return
  end

  vim.ui.select(candidates, {
    prompt = "Runic candidates",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    state.last = choice
    add_history(choice)
    run_in_terminal(choice.command, choice.cwd)
  end)
end

function M.run_last()
  if not state.last then
    vim.notify("Runic: nothing to rerun", vim.log.levels.WARN)
    return
  end
  run_in_terminal(state.last.command, state.last.cwd)
end

function M.stop()
  local active = state.active_job
  if not active or not active.id then
    vim.notify("Runic: no active process", vim.log.levels.INFO)
    return
  end

  local ok = vim.fn.jobstop(active.id)
  if ok == 1 then
    vim.notify("Runic stopped active process", vim.log.levels.INFO)
  else
    vim.notify("Runic failed to stop active process", vim.log.levels.WARN)
  end
end

function M.restart_last()
  if not state.last then
    vim.notify("Runic: nothing to restart", vim.log.levels.WARN)
    return
  end
  M.stop()
  run_in_terminal(state.last.command, state.last.cwd)
end

function M.history_pick()
  if #state.history == 0 then
    vim.notify("Runic history is empty", vim.log.levels.INFO)
    return
  end
  vim.ui.select(state.history, {
    prompt = "Runic history",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      state.last = choice
      run_in_terminal(choice.command, choice.cwd)
    end
  end)
end

function M.clear_cache()
  state.cache_gen = state.cache_gen + 1
  state.cache = {}
  vim.notify("Runic cache cleared", vim.log.levels.INFO)
end

function M.cache_info()
  local count = 0
  for _ in pairs(state.cache) do
    count = count + 1
  end
  local lines = {
    "Runic Cache",
    string.rep("=", 10),
    "entries: " .. tostring(count),
    "generation: " .. tostring(state.cache_gen),
    "hits: " .. tostring(state.cache_hits),
    "misses: " .. tostring(state.cache_misses),
  }
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Runic" })
end

function M.health()
  local tools = {
    "git",
    "python3",
    "node",
    "npm",
    "pnpm",
    "bun",
    "deno",
    "go",
    "cargo",
    "rustc",
    "gcc",
    "g++",
    "clang",
    "clang++",
    "cmake",
    "make",
    "dotnet",
    "java",
    "javac",
    "mvn",
    "gradle",
    "dart",
    "flutter",
    "ruby",
    "php",
  }

  local found = 0
  local missing = {}
  for _, tool in ipairs(tools) do
    if has_exec(tool) then
      found = found + 1
    else
      missing[#missing + 1] = tool
    end
  end

  local lines = {
    "Runic Health",
    string.rep("=", 12),
    "tools found: " .. tostring(found) .. "/" .. tostring(#tools),
  }

  if #missing > 0 then
    lines[#lines + 1] = "missing: " .. table.concat(missing, ", ")
    vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN, { title = "Runic" })
  else
    lines[#lines + 1] = "all common toolchains available"
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Runic" })
  end
end

local function cf_root_for_current_buffer()
  local ctx, err = build_context({ bufnr = 0 })
  if not ctx then
    return nil, err
  end
  if not is_cf_workspace(ctx.root) then
    local found = vim.fs.find(".runic-cf.json", {
      path = vim.fs.dirname(ctx.file),
      upward = true,
      limit = 1,
    })
    if #found > 0 then
      return vim.fs.dirname(found[1]), nil
    end
    return nil, "Current file is not inside a runic CF workspace"
  end
  return ctx.root, nil
end

local function cf_run_sample_once(root, file, input_path)
  local run_cmd = cf_run_command(root, file)
  local timeout = tonumber(M.config.cf.sample.timeout_ms) or 3000
  local timeout_sec = math.max(1, math.floor((timeout + 999) / 1000))
  local cmd = string.format("timeout %ss %s < %s", tostring(timeout_sec), run_cmd, shellescape(input_path))
  return vim.fn.system({ vim.o.shell, "-lc", cmd })
end

local function cf_build_test_state(root, file)
  local sample_inputs = list_sample_inputs(root)
  if #sample_inputs == 0 then
    return nil, "No sample inputs found in " .. cf_samples_dir(root)
  end

  return {
    root = root,
    file = file,
    sample_inputs = sample_inputs,
    idx = 1,
    passed = 0,
    failed = 0,
    first_fail = nil,
  }, nil
end

local function cf_finish_test(st)
  state.cf_test_running = false

  if st.failed == 0 then
    vim.notify(string.format("CF samples passed: %d/%d", st.passed, #st.sample_inputs), vim.log.levels.INFO)
  else
    local lines = {
      string.format("CF samples failed: %d/%d", st.failed, #st.sample_inputs),
      "first fail: " .. st.first_fail.input,
      "expected:",
      st.first_fail.expected,
      "actual:",
      st.first_fail.actual,
    }
    vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN)
  end

  if state.cf_test_pending then
    state.cf_test_pending = false
    vim.defer_fn(function()
      M.cf_test_async()
    end, 100)
  end
end

local function cf_test_step(st)
  if st.idx > #st.sample_inputs then
    cf_finish_test(st)
    return
  end

  local input_path = st.sample_inputs[st.idx]
  local got = cf_run_sample_once(st.root, st.file, input_path)
  local out_path = input_path:gsub("%.in$", ".out")
  local expected = read_trimmed(out_path)
  local actual = (got or ""):gsub("\r", ""):gsub("%s+$", "")

  if expected == nil then
    st.passed = st.passed + 1
  elseif expected == actual then
    st.passed = st.passed + 1
  else
    st.failed = st.failed + 1
    if not st.first_fail then
      st.first_fail = { input = input_path, expected = expected, actual = actual }
    end
  end

  st.idx = st.idx + 1
  vim.schedule(function()
    cf_test_step(st)
  end)
end

function M.cf_start(opts)
  opts = opts or {}
  local contest = opts.contest
  local problem = opts.problem
  if type(contest) ~= "string" or contest == "" or type(problem) ~= "string" or problem == "" then
    vim.notify("RunicCFStart usage: :RunicCFStart <contestId> <problemIndex>", vim.log.levels.ERROR)
    return
  end

  local root = expand_path(M.config.cf.workspace_root)
  local problem_root = vim.fs.joinpath(root, contest, problem)
  local samples = cf_samples_dir(problem_root)
  local stress_dir = vim.fs.joinpath(problem_root, "stress")

  vim.fn.mkdir(problem_root, "p")
  vim.fn.mkdir(samples, "p")
  vim.fn.mkdir(stress_dir, "p")
  vim.fn.mkdir(vim.fs.joinpath(problem_root, ".runic-bin"), "p")

  local main_cpp = vim.fs.joinpath(problem_root, "main.cpp")
  if not file_exists(main_cpp) then
    write_file(main_cpp, cf_template_content())
  end

  local notes = vim.fs.joinpath(problem_root, "notes.md")
  if not file_exists(notes) then
    write_file(notes, "# " .. contest .. problem .. "\n")
  end

  local gen_cpp = vim.fs.joinpath(stress_dir, "gen.cpp")
  if not file_exists(gen_cpp) then
    write_file(gen_cpp, table.concat({
      "#include <bits/stdc++.h>",
      "using namespace std;",
      "",
      "int main(int argc, char** argv) {",
      "  long long seed = (argc > 1 ? atoll(argv[1]) : 1);",
      "  mt19937_64 rng(seed);",
      "  int n = (int)(rng() % 10 + 1);",
      "  cout << n << '\\n';",
      "  for (int i = 0; i < n; ++i) cout << (int)(rng() % 100) << (i + 1 == n ? '\\n' : ' ');",
      "  return 0;",
      "}",
      "",
    }, "\n"))
  end

  local brute_cpp = vim.fs.joinpath(stress_dir, "brute.cpp")
  if not file_exists(brute_cpp) then
    write_file(brute_cpp, table.concat({
      "#include <bits/stdc++.h>",
      "using namespace std;",
      "",
      "int main() {",
      "  // TODO: implement brute-force solution for stress testing",
      "  return 0;",
      "}",
      "",
    }, "\n"))
  end

  write_cf_meta(problem_root, {
    contest = contest,
    problem = problem,
    created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    profile = current_cf_profile_name(),
    sample_dir = M.config.cf.sample.dir,
    solution_file = "main.cpp",
  })

  vim.cmd.edit(main_cpp)
  vim.notify("Runic CF workspace ready: " .. problem_root, vim.log.levels.INFO)
end

function M.cf_mode_on()
  M.config.cf.enabled = true
  vim.notify("Runic CF mode enabled", vim.log.levels.INFO)
end

function M.cf_mode_off()
  M.config.cf.enabled = false
  M.cf_watch_stop()
  vim.notify("Runic CF mode disabled", vim.log.levels.INFO)
end

function M.cf_status()
  local root, err = cf_root_for_current_buffer()
  local lines = {
    "Runic CF Status",
    string.rep("=", 15),
    "enabled: " .. tostring(M.config.cf.enabled),
    "profile: " .. current_cf_profile_name(),
    "watch: " .. tostring(state.cf_watch_enabled),
    "workspace_root: " .. expand_path(M.config.cf.workspace_root),
  }
  if root then
    local meta = read_cf_meta(root) or {}
    lines[#lines + 1] = "problem_root: " .. root
    if meta.contest and meta.problem then
      lines[#lines + 1] = "problem: " .. tostring(meta.contest) .. tostring(meta.problem)
    end
  else
    lines[#lines + 1] = "context: " .. err
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Runic" })
end

function M.cf_set_profile(name)
  if type(name) ~= "string" or name == "" then
    vim.notify("RunicCFProfile usage: :RunicCFProfile <contest|debug>", vim.log.levels.ERROR)
    return
  end
  if not M.config.cf.profiles[name] then
    vim.notify("Unknown CF profile: " .. name, vim.log.levels.ERROR)
    return
  end
  state.cf_profile = name

  local root = cf_root_for_current_buffer()
  if root then
    local meta = read_cf_meta(root) or {}
    meta.profile = name
    write_cf_meta(root, meta)
  end

  vim.notify("Runic CF profile: " .. name, vim.log.levels.INFO)
end

function M.cf_import_samples()
  local root, err = cf_root_for_current_buffer()
  if not root then
    vim.notify("Runic: " .. err, vim.log.levels.ERROR)
    return
  end

  local blob = vim.fn.getreg("+")
  if type(blob) ~= "string" or blob == "" then
    vim.notify("Clipboard is empty. Copy sample text and retry.", vim.log.levels.WARN)
    return
  end

  blob = blob:gsub("\r", "")
  local sample_dir = cf_samples_dir(root)
  vim.fn.mkdir(sample_dir, "p")

  local function classify_header(line)
    local s = line:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub(":$", "")
    if s == "copy" or s == "sample" or s:match("^example%s*%d*$") then
      return "ignore"
    end
    if s == "input" or s == "sample input" or s == "input copy" or s == "sample input copy" then
      return "input"
    end
    if s == "output" or s == "sample output" or s == "output copy" or s == "sample output copy" then
      return "output"
    end
    if s:match("^input%s*%d+$") or s:match("^sample%s*%d+%s*input$") then
      return "input"
    end
    if s:match("^output%s*%d+$") or s:match("^sample%s*%d+%s*output$") then
      return "output"
    end
    return nil
  end

  local function normalize_block(lines)
    return table.concat(lines, "\n"):gsub("^\n+", ""):gsub("\n+$", "")
  end

  local blocks = {}
  local state_mode = nil
  local input_lines = {}
  local output_lines = {}

  local function flush_pair()
    local input_text = normalize_block(input_lines)
    local output_text = normalize_block(output_lines)
    if input_text ~= "" and output_text ~= "" then
      blocks[#blocks + 1] = { input = input_text, output = output_text }
    end
    input_lines = {}
    output_lines = {}
    state_mode = nil
  end

  local lines = vim.split(blob, "\n", { plain = true })
  for _, line in ipairs(lines) do
    local kind = classify_header(line)
    if kind == "input" then
      if state_mode == "output" then
        flush_pair()
      end
      state_mode = "input"
    elseif kind == "output" then
      state_mode = "output"
    elseif kind == "ignore" then
      -- Ignore known non-content helper labels such as "Copy".
    else
      if state_mode == "input" then
        input_lines[#input_lines + 1] = line
      elseif state_mode == "output" then
        output_lines[#output_lines + 1] = line
      end
    end
  end
  if #input_lines > 0 or #output_lines > 0 then
    flush_pair()
  end

  if #blocks == 0 then
    vim.notify("Could not parse samples. Ensure clipboard has Input/Output blocks.", vim.log.levels.ERROR)
    return
  end

  for idx, case in ipairs(blocks) do
    write_file(vim.fs.joinpath(sample_dir, tostring(idx) .. ".in"), case.input)
    write_file(vim.fs.joinpath(sample_dir, tostring(idx) .. ".out"), case.output)
  end

  vim.notify("Imported " .. tostring(#blocks) .. " sample case(s)", vim.log.levels.INFO)
end

function M.cf_test()
  local root, err = cf_root_for_current_buffer()
  if not root then
    vim.notify("Runic: " .. err, vim.log.levels.ERROR)
    return
  end

  local file = cf_solution_path(root)
  if not file_exists(file) then
    vim.notify("Runic: solution file missing: " .. file, vim.log.levels.ERROR)
    return
  end

  local sample_inputs = list_sample_inputs(root)
  if #sample_inputs == 0 then
    vim.notify("No sample inputs found in " .. cf_samples_dir(root), vim.log.levels.WARN)
    return
  end

  local compile = cf_compile_command(root, file)
  local compile_ok = vim.fn.system({ vim.o.shell, "-lc", compile })
  if vim.v.shell_error ~= 0 then
    vim.notify("CF compile failed\n" .. compile_ok, vim.log.levels.ERROR)
    return
  end

  local passed = 0
  local failed = 0
  local first_fail
  for _, input_path in ipairs(sample_inputs) do
    local got = cf_run_sample_once(root, file, input_path)
    local out_path = input_path:gsub("%.in$", ".out")
    local expected = read_trimmed(out_path)
    local actual = (got or ""):gsub("\r", ""):gsub("%s+$", "")
    if expected == nil then
      passed = passed + 1
    elseif expected == actual then
      passed = passed + 1
    else
      failed = failed + 1
      if not first_fail then
        first_fail = { input = input_path, expected = expected, actual = actual }
      end
    end
  end

  if failed == 0 then
    vim.notify(string.format("CF samples passed: %d/%d", passed, #sample_inputs), vim.log.levels.INFO)
    return
  end

  local lines = {
    string.format("CF samples failed: %d/%d", failed, #sample_inputs),
    "first fail: " .. first_fail.input,
    "expected:",
    first_fail.expected,
    "actual:",
    first_fail.actual,
  }
  vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN)
end

function M.cf_test_async()
  local root, err = cf_root_for_current_buffer()
  if not root then
    vim.notify("Runic: " .. err, vim.log.levels.ERROR)
    return
  end

  local file = cf_solution_path(root)
  if not file_exists(file) then
    vim.notify("Runic: solution file missing: " .. file, vim.log.levels.ERROR)
    return
  end

  if state.cf_test_running then
    state.cf_test_pending = true
    return
  end

  local st, st_err = cf_build_test_state(root, file)
  if not st then
    vim.notify(st_err, vim.log.levels.WARN)
    return
  end

  local compile = cf_compile_command(root, file)
  local compile_ok = vim.fn.system({ vim.o.shell, "-lc", compile })
  if vim.v.shell_error ~= 0 then
    vim.notify("CF compile failed\n" .. compile_ok, vim.log.levels.ERROR)
    return
  end

  state.cf_test_running = true
  state.cf_test_pending = false
  vim.schedule(function()
    cf_test_step(st)
  end)
end

local function cf_stress_paths(root)
  return {
    generator = vim.fs.joinpath(root, "stress", "gen.cpp"),
    brute = vim.fs.joinpath(root, "stress", "brute.cpp"),
    solution = vim.fs.joinpath(root, "main.cpp"),
    counterexample = vim.fs.joinpath(root, "counterexample.in"),
  }
end

local function cf_run_bin_with_input(bin_path, input_path, timeout_ms)
  local sec = math.max(1, math.floor((timeout_ms or 2000) / 1000))
  local cmd = string.format("timeout %ss %s < %s", tostring(sec), shellescape(bin_path), shellescape(input_path))
  local out = vim.fn.system({ vim.o.shell, "-lc", cmd })
  local code = vim.v.shell_error
  return out, code
end

function M.cf_stress(opts)
  opts = opts or {}
  local root, err = cf_root_for_current_buffer()
  if not root then
    vim.notify("Runic: " .. err, vim.log.levels.ERROR)
    return
  end

  local paths = cf_stress_paths(root)
  paths.solution = cf_solution_path(root)
  if not file_exists(paths.generator) or not file_exists(paths.brute) or not file_exists(paths.solution) then
    vim.notify("Stress requires stress/gen.cpp, stress/brute.cpp, and main.cpp", vim.log.levels.ERROR)
    return
  end

  local compile_cmds = {
    cf_compile_command_to(root, paths.solution, cf_stress_binary_path(root, "solution")),
    cf_compile_command_to(root, paths.brute, cf_stress_binary_path(root, "brute")),
    cf_compile_command_to(root, paths.generator, cf_stress_binary_path(root, "gen")),
  }
  for _, cmd in ipairs(compile_cmds) do
    local out = vim.fn.system({ vim.o.shell, "-lc", cmd })
    if vim.v.shell_error ~= 0 then
      vim.notify("Stress compile failed\n" .. out, vim.log.levels.ERROR)
      return
    end
  end

  local max_cases = tonumber(opts.max_cases) or tonumber(M.config.cf.stress.max_cases) or 500
  local timeout_ms = tonumber(M.config.cf.stress.timeout_ms) or 2000
  local gen_bin = cf_stress_binary_path(root, "gen")
  local sol_bin = cf_stress_binary_path(root, "solution")
  local brute_bin = cf_stress_binary_path(root, "brute")

  local i = 1
  local input_path = vim.fs.joinpath(root, ".runic-bin", "stress.in")

  local function step()
    if i > max_cases then
      vim.notify("Stress passed " .. tostring(max_cases) .. " cases", vim.log.levels.INFO)
      return
    end

    local gen_cmd = string.format("%s %d > %s", shellescape(gen_bin), i, shellescape(input_path))
    vim.fn.system({ vim.o.shell, "-lc", gen_cmd })
    if vim.v.shell_error ~= 0 then
      vim.notify("Generator failed at case " .. tostring(i), vim.log.levels.ERROR)
      return
    end

    local got, got_code = cf_run_bin_with_input(sol_bin, input_path, timeout_ms)
    local exp, exp_code = cf_run_bin_with_input(brute_bin, input_path, timeout_ms)
    if got_code ~= 0 or exp_code ~= 0 then
      local msg = string.format("Stress runtime failure at case %d (solution=%d, brute=%d)", i, got_code, exp_code)
      vim.notify(msg, vim.log.levels.WARN)
      if M.config.cf.stress.save_counterexample then
        vim.fn.system({ vim.o.shell, "-lc", string.format("cp %s %s", shellescape(input_path), shellescape(paths.counterexample)) })
      end
      return
    end

    local g = (got or ""):gsub("\r", ""):gsub("%s+$", "")
    local e = (exp or ""):gsub("\r", ""):gsub("%s+$", "")
    if g ~= e then
      if M.config.cf.stress.save_counterexample then
        vim.fn.system({ vim.o.shell, "-lc", string.format("cp %s %s", shellescape(input_path), shellescape(paths.counterexample)) })
      end
      local lines = {
        string.format("Stress mismatch at case %d", i),
        "Counterexample saved: " .. paths.counterexample,
        "expected:",
        e,
        "actual:",
        g,
      }
      vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN)
      return
    end

    i = i + 1
    if i % 50 == 0 then
      vim.notify(string.format("Stress progress: %d/%d", i - 1, max_cases), vim.log.levels.INFO)
    end
    vim.schedule(step)
  end

  vim.schedule(step)
end

function M.cf_replay_fail()
  local root, err = cf_root_for_current_buffer()
  if not root then
    vim.notify("Runic: " .. err, vim.log.levels.ERROR)
    return
  end
  local file = cf_solution_path(root)
  if not file_exists(file) then
    vim.notify("Runic: solution file missing: " .. file, vim.log.levels.ERROR)
    return
  end
  local paths = cf_stress_paths(root)
  if not file_exists(paths.counterexample) then
    vim.notify("No counterexample found. Run RunicCFStress first.", vim.log.levels.WARN)
    return
  end
  local cmd = cf_run_command(root, file) .. " < " .. shellescape(paths.counterexample)
  run_in_terminal(cmd, root)
end

function M.cf_watch()
  state.cf_watch_enabled = true
  vim.notify("Runic CF watch enabled", vim.log.levels.INFO)
end

function M.cf_watch_stop()
  state.cf_watch_enabled = false
  vim.notify("Runic CF watch disabled", vim.log.levels.INFO)
end

function M.cf_check()
  M.cf_test_async()
  if M.config.cf.check.run_stress then
    M.cf_stress({ max_cases = M.config.cf.check.stress_cases })
  end
end

function M.cf_submit()
  local root, err = cf_root_for_current_buffer()
  if not root then
    vim.notify("Runic: " .. err, vim.log.levels.ERROR)
    return
  end

  local meta = read_cf_meta(root)
  if not meta or not meta.contest or not meta.problem then
    vim.notify("CF metadata missing. Use RunicCFStart first.", vim.log.levels.ERROR)
    return
  end

  local url = string.format("https://codeforces.com/contest/%s/problem/%s", tostring(meta.contest), tostring(meta.problem))
  local open_cmd
  if vim.fn.has("mac") == 1 then
    open_cmd = { "open", url }
  elseif vim.fn.has("win32") == 1 then
    open_cmd = { "cmd", "/c", "start", "", url }
  else
    open_cmd = { "xdg-open", url }
  end
  vim.fn.jobstart(open_cmd, { detach = true })
  local source = cf_solution_path(root)
  vim.notify("Opened Codeforces page for manual submit. Source: " .. source, vim.log.levels.INFO)
end

function M.cf_auto_submit()
  if not M.config.cf.submit.auto_submit then
    vim.notify("Auto submit disabled. Enable cf.submit.auto_submit in setup.", vim.log.levels.WARN)
    return
  end
  local root, err = cf_root_for_current_buffer()
  if not root then
    vim.notify("Runic: " .. err, vim.log.levels.ERROR)
    return
  end

  local meta = read_cf_meta(root)
  if not meta or not meta.contest or not meta.problem then
    vim.notify("CF metadata missing. Use RunicCFStart first.", vim.log.levels.ERROR)
    return
  end

  if M.config.cf.submit.confirm then
    local ans = vim.fn.confirm("Experimental auto submit to Codeforces?", "&Yes\n&No", 2)
    if ans ~= 1 then
      vim.notify("Auto submit cancelled", vim.log.levels.INFO)
      return
    end
  end

  local cookie_env = M.config.cf.submit.cookie_env or "RUNIC_CF_COOKIE"
  local cookie = os.getenv(cookie_env)
  if not cookie or cookie == "" then
    vim.notify("Missing cookie env " .. cookie_env .. ". Falling back to manual submit.", vim.log.levels.WARN)
    M.cf_submit()
    return
  end

  local submit_url = string.format("https://codeforces.com/contest/%s/submit", tostring(meta.contest))
  local source_path = cf_solution_path(root)
  local source = read_file(source_path)
  if not source or source == "" then
    vim.notify("Could not read source file for submit: " .. source_path, vim.log.levels.ERROR)
    return
  end

  local page = vim.fn.system({
    "curl",
    "-sL",
    "-H",
    "Cookie: " .. cookie,
    submit_url,
  })
  if vim.v.shell_error ~= 0 then
    vim.notify("Could not fetch submit page; falling back to manual submit", vim.log.levels.WARN)
    M.cf_submit()
    return
  end

  local csrf = page:match('name="csrf_token"%s+value="([^"]+)"')
    or page:match('data%-csrf="([^"]+)"')
    or page:match('X%-Csrf%-Token"%s+content="([^"]+)"')
  if not csrf then
    vim.notify("Could not parse csrf token; falling back to manual submit", vim.log.levels.WARN)
    M.cf_submit()
    return
  end

  local lang = M.config.cf.submit.language_id or "91"
  local problem_index = tostring(meta.problem)

  local res = vim.fn.system({
    "curl",
    "-sL",
    "-X",
    "POST",
    "-H",
    "Cookie: " .. cookie,
    "-F",
    "csrf_token=" .. csrf,
    "-F",
    "ftaa=",
    "-F",
    "bfaa=",
    "-F",
    "action=submitSolutionFormSubmitted",
    "-F",
    "submittedProblemIndex=" .. problem_index,
    "-F",
    "programTypeId=" .. tostring(lang),
    "-F",
    "source=" .. source,
    submit_url,
  })

  if vim.v.shell_error ~= 0 then
    vim.notify("Auto submit request failed. Falling back to manual submit", vim.log.levels.WARN)
    M.cf_submit()
    return
  end

  if res:match("error") or res:match("invalid") then
    vim.notify("Auto submit returned an error. Check session/cookies. Falling back to manual submit.", vim.log.levels.WARN)
    M.cf_submit()
    return
  end

  vim.notify("Auto submit request sent (experimental). Check My Submissions.", vim.log.levels.INFO)
end

register_commands = function()
  local specs = {
    { "RunicRun", function() M.run({ mode = "auto" }) end, "Run best runic candidate" },
    { "RunicAction", function() M.action({ mode = "auto" }) end, "Choose runic intent and run" },
    { "RunicPick", function() M.pick({ mode = "auto" }) end, "Pick runic candidate" },
    { "RunicRunFile", function() M.run({ mode = "file" }) end, "Runic file mode" },
    { "RunicRunProject", function() M.run({ mode = "project" }) end, "Runic project mode" },
    { "RunicPreview", function() M.preview({ mode = "auto" }) end, "Preview runic decision" },
    { "RunicExplain", function() M.explain({ mode = "auto" }) end, "Explain runic decision" },
    { "RunicLast", M.run_last, "Rerun last runic command" },
    { "RunicHistory", M.history_pick, "Pick from runic history" },
    { "RunicCacheClear", M.clear_cache, "Clear runic cache" },
    { "RunicCacheInfo", M.cache_info, "Show runic cache stats" },
    { "RunicHealth", M.health, "Check runic toolchain health" },
    { "RunicReload", function() M.reconfigure() end, "Reapply runic setup" },
    { "RunicStop", M.stop, "Stop active runic process" },
    { "RunicRestart", M.restart_last, "Restart last runic command" },
    { "RunicCFStart", function(args)
      local parts = vim.split(args.args, " ", { trimempty = true })
      M.cf_start({ contest = parts[1], problem = parts[2] })
    end, "Create/open Codeforces workspace" },
    { "RunicCFModeOn", M.cf_mode_on, "Enable Codeforces mode" },
    { "RunicCFModeOff", M.cf_mode_off, "Disable Codeforces mode" },
    { "RunicCFStatus", M.cf_status, "Show Codeforces mode status" },
    { "RunicCFImportSamples", M.cf_import_samples, "Import samples from clipboard" },
    { "RunicCFTest", M.cf_test, "Run Codeforces sample tests" },
    { "RunicCFWatch", M.cf_watch, "Enable Codeforces watch tests" },
    { "RunicCFWatchStop", M.cf_watch_stop, "Disable Codeforces watch tests" },
    { "RunicCFStress", M.cf_stress, "Run Codeforces stress testing" },
    { "RunicCFReplayFail", M.cf_replay_fail, "Replay last stress counterexample" },
    { "RunicCFCheck", M.cf_check, "Run pre-submit checks" },
    { "RunicCFSubmit", M.cf_submit, "Open problem page for manual submit" },
    { "RunicCFAutoSubmit", M.cf_auto_submit, "Experimental auto submit" },
  }

  for _, spec in ipairs(specs) do
    pcall(vim.api.nvim_del_user_command, spec[1])
    if spec[1] == "RunicCFStart" then
      vim.api.nvim_create_user_command(spec[1], spec[2], { desc = spec[3], nargs = "+" })
    else
      vim.api.nvim_create_user_command(spec[1], spec[2], { desc = spec[3] })
    end
  end

  pcall(vim.api.nvim_del_user_command, "RunicCFProfile")
  vim.api.nvim_create_user_command("RunicCFProfile", function(args)
    M.cf_set_profile(args.args)
  end, {
    desc = "Set CF profile",
    nargs = 1,
    complete = function()
      local out = {}
      for name in pairs(M.config.cf.profiles) do
        out[#out + 1] = name
      end
      table.sort(out)
      return out
    end,
  })
end

clear_commands = function()
  for _, name in ipairs(command_names) do
    pcall(vim.api.nvim_del_user_command, name)
  end
end

register_keymaps = function()
  local km = M.config.keymaps

  for _, mapped in ipairs(state.keymaps) do
    pcall(vim.keymap.del, "n", mapped)
  end
  state.keymaps = {}

  if km.run then
    vim.keymap.set("n", km.run, function()
      M.run({ mode = "auto" })
    end, { desc = "Runic run" })
    state.keymaps[#state.keymaps + 1] = km.run
  end
  if km.pick then
    vim.keymap.set("n", km.pick, function()
      M.pick({ mode = "auto" })
    end, { desc = "Runic pick" })
    state.keymaps[#state.keymaps + 1] = km.pick
  end
  if km.last then
    vim.keymap.set("n", km.last, M.run_last, { desc = "Runic last" })
    state.keymaps[#state.keymaps + 1] = km.last
  end
  if km.legacy then
    vim.keymap.set("n", km.legacy, function()
      if vim.fn.exists(":RunFile") == 2 then
        vim.cmd.RunFile()
      else
        vim.notify("RunFile command is unavailable", vim.log.levels.WARN)
      end
    end, { desc = "Run file (legacy)" })
    state.keymaps[#state.keymaps + 1] = km.legacy
  end
end

function M.reconfigure(opts)
  local notify_reconfigure = true
  local merged_opts = opts or {}
  if type(opts) == "table" then
    merged_opts = vim.deepcopy(opts)
    if merged_opts._notify ~= nil then
      notify_reconfigure = merged_opts._notify == true
    end
    merged_opts._notify = nil
  end

  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), M.config, merged_opts)
  state.cache_gen = state.cache_gen + 1
  state.cache = {}

  clear_commands()
  if M.config.create_commands then
    register_commands()
  end
  if M.config.create_keymaps then
    register_keymaps()
  end

  if notify_reconfigure then
    vim.notify("Runic reconfigured", vim.log.levels.INFO)
  end
  return M
end

function M.setup(opts)
  if not state.autocmd_setup then
    setup_cache_autocmds()
    state.autocmd_setup = true
  end

  local setup_opts = opts or {}
  if type(setup_opts) == "table" then
    setup_opts = vim.deepcopy(setup_opts)
    if setup_opts._notify == nil then
      setup_opts._notify = false
    end
  end

  return M.reconfigure(setup_opts)
end

return M

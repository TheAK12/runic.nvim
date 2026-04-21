local M = {}
local cf_problem_ns = vim.api.nvim_create_namespace("runic_cf_problem")

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
  cf_problem = {
    bufnr = nil,
    winid = nil,
    root = nil,
    url = nil,
    request_id = 0,
    markdown = nil,
  },
  root_overrides = {},
  run_status = {
    status = "idle",
    cmd = nil,
    cwd = nil,
    started_at = nil,
    ended_at = nil,
    duration_ms = nil,
    exit_code = nil,
  },
  stop_requested = false,
  keymap_report = {
    active = {},
    skipped = {},
  },
}

local defaults = {
  create_commands = true,
  create_keymaps = true,
  keymap_mode = "safe", -- "safe" | "force" | "off"
  keymaps = {
    run = "<leader>r",
    pick = "<leader>rp",
    last = "<leader>rl",
    legacy = "<leader>R",
    cf_mode_on = "<leader>cfo",
    cf_mode_off = "<leader>cfO",
    cf_status = "<leader>cfs",
    cf_start = "<leader>cfn",
    cf_profile_contest = "<leader>cfp",
    cf_profile_debug = "<leader>cfP",
    cf_import = "<leader>cfi",
    cf_test = "<leader>cft",
    cf_watch_on = "<leader>cfw",
    cf_watch_off = "<leader>cfW",
    cf_stress = "<leader>cfx",
    cf_replay = "<leader>cfr",
    cf_check = "<leader>cfc",
    cf_submit = "<leader>cfu",
    cf_problem_view = "<leader>cfv",
  },
  root = {
    use_lsp = true,
    resolver = nil,
    strategy = { "custom", "marker", "lsp", "file" },
    markers = {
      ".git",
      "package.json",
      "pnpm-workspace.yaml",
      "turbo.json",
      "nx.json",
      "pyproject.toml",
      "Pipfile",
      "pdm.lock",
      "uv.lock",
      "poetry.lock",
      "hatch.toml",
      "tox.ini",
      "noxfile.py",
      "requirements.txt",
      "go.mod",
      "Cargo.toml",
      "justfile",
      ".justfile",
      "Taskfile.yml",
      "Taskfile.yaml",
      "CMakeLists.txt",
      "Makefile",
      "meson.build",
      "pom.xml",
      "build.gradle",
      "build.gradle.kts",
      "settings.gradle",
      "settings.gradle.kts",
      "build.sbt",
      "deno.json",
      "deno.jsonc",
      "bunfig.toml",
      "pubspec.yaml",
      "mix.exs",
      "composer.json",
      "artisan",
      "Gemfile",
      "Rakefile",
      "stack.yaml",
      "project.clj",
      "deps.edn",
      "build.zig",
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
    python_project_runner = true,
  },
  tasks = {
    enabled = true,
    include_in_auto = true,
    base_priority = 7600,
  },
  packs = {
    core = true,
    overrides = true,
    tasks = true,
    cf = true,
    node = true,
    python = true,
    go = true,
    rust = true,
    java = true,
    dotnet = true,
    c_cpp = true,
    scripting = true,
    fallback = true,
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
    chdir_on_start = "tab",
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
    problem = {
      auto_open = true,
      pane_width = 72,
      cache = true,
      cache_file = ".runic-problem.md",
      refresh_on_start = false,
      lang = "en",
      proxy_fallback = true,
      proxy_base = "https://r.jina.ai/http://",
      view = "comfortable",
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
  "RunicKeymaps",
  "RunicRoot",
  "RunicRootReset",
  "RunicStatus",
  "RunicLast",
  "RunicHistory",
  "RunicTasks",
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
  "RunicCFProblemOpen",
  "RunicCFProblemRefresh",
  "RunicCFProblemClose",
  "RunicCFProblemToggleView",
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

local RULE_PACKS = {
  override_global = "overrides",
  override_filetype = "overrides",
  override_resolver = "overrides",
  project_cf = "cf",
  project_node = "node",
  project_python = "python",
  project_go = "go",
  project_rust = "rust",
  project_cmake = "c_cpp",
  project_make = "c_cpp",
  project_java_maven = "java",
  project_java_gradle = "java",
  project_sbt = "java",
  project_dotnet = "dotnet",
  project_dart = "scripting",
  project_elixir = "scripting",
  project_php = "scripting",
  project_ruby = "scripting",
  project_scripting = "scripting",
  project_python_test = "python",
  project_go_test_target = "go",
  project_rust_test_target = "rust",
  task_npm = "tasks",
  task_just = "tasks",
  task_taskfile = "tasks",
  file_c = "c_cpp",
  file_cpp = "c_cpp",
  file_html = "scripting",
  file_ext = "scripting",
  fallback_executable = "fallback",
  fallback_shebang = "fallback",
}

local function is_pack_enabled(pack)
  if pack == nil then
    return true
  end
  local packs = M.config.packs
  if type(packs) ~= "table" then
    return true
  end
  if packs.core == false and pack ~= "core" then
    return false
  end
  return packs[pack] ~= false
end

local function is_rule_disabled(rule_id)
  local pack = RULE_PACKS[rule_id]
  if not is_pack_enabled(pack) then
    return true
  end
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

local function system_list_in_dir(argv, cwd)
  if vim.system then
    local result = vim.system(argv, { cwd = cwd, text = true }):wait()
    return result.stdout or "", result.code or 1
  end

  local quoted = {}
  for _, arg in ipairs(argv) do
    quoted[#quoted + 1] = shellescape(tostring(arg))
  end
  local cmd = "cd " .. shellescape(cwd) .. " && " .. table.concat(quoted, " ")
  local out = vim.fn.system({ vim.o.shell, "-lc", cmd })
  return out, vim.v.shell_error
end

local function path_stem(path)
  local name = vim.fn.fnamemodify(path, ":t")
  return name:gsub("%.[^.]+$", "")
end

local function relative_to(path, base)
  local p = vim.fs.normalize(path)
  local b = vim.fs.normalize(base)
  if b:sub(-1) ~= "/" then
    b = b .. "/"
  end
  if p:sub(1, #b) == b then
    return p:sub(#b + 1)
  end
  return vim.fn.fnamemodify(path, ":t")
end

local function has_taskfile(root)
  return has_any_file(root, { "Taskfile.yml", "Taskfile.yaml" })
end

local function read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    return {}
  end
  return lines
end

local function discover_just_tasks(root)
  local tasks = {}
  local function add_task(name)
    if type(name) == "string" and name ~= "" and not name:match("^_") and not tasks[name] then
      tasks[name] = true
    end
  end

  if has_exec("just") then
    local out, code = system_list_in_dir({ "just", "--list", "--unsorted" }, root)
    if code == 0 then
      for line in out:gmatch("[^\n]+") do
        local name = line:match("^%s*([%w_%-%.]+)%s")
        add_task(name)
      end
    end
  end

  if vim.tbl_isempty(tasks) then
    local just_path = has_file(root, "justfile") and vim.fs.joinpath(root, "justfile") or vim.fs.joinpath(root, ".justfile")
    if file_exists(just_path) then
      for _, line in ipairs(read_lines(just_path)) do
        local name = line:match("^([%w_%-%.]+)%s*:")
        add_task(name)
      end
    end
  end

  local out = {}
  for name in pairs(tasks) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

local function discover_taskfile_tasks(root)
  local tasks = {}
  local function add_task(name)
    if type(name) == "string" and name ~= "" and not tasks[name] then
      tasks[name] = true
    end
  end

  if has_exec("task") and has_taskfile(root) then
    local out, code = system_list_in_dir({ "task", "--list" }, root)
    if code == 0 then
      for line in out:gmatch("[^\n]+") do
        local name = line:match("^%*%s+([%w_%-%.:]+)")
        add_task(name)
      end
    end
  end

  if vim.tbl_isempty(tasks) then
    local taskfile = has_file(root, "Taskfile.yml") and vim.fs.joinpath(root, "Taskfile.yml") or vim.fs.joinpath(root, "Taskfile.yaml")
    if file_exists(taskfile) then
      local in_tasks = false
      for _, line in ipairs(read_lines(taskfile)) do
        if line:match("^tasks:%s*$") then
          in_tasks = true
        elseif in_tasks then
          local name = line:match("^%s%s([%w_%-%.:]+):%s*$")
          if name then
            add_task(name)
          end
        end
      end
    end
  end

  local out = {}
  for name in pairs(tasks) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

local function root_override_key()
  return tostring(vim.api.nvim_get_current_tabpage())
end

local function get_root_override()
  return state.root_overrides[root_override_key()]
end

local function set_root_override(path)
  state.root_overrides[root_override_key()] = path
end

local function reset_root_override()
  state.root_overrides[root_override_key()] = nil
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
  local override = get_root_override()
  if type(override) == "string" and override ~= "" then
    return vim.fs.normalize(override), "override"
  end

  local function resolve_custom()
    local resolver = M.config.root.resolver
    if type(resolver) ~= "function" then
      return nil
    end
    local ok, custom = pcall(resolver, {
      bufnr = bufnr,
      file = file,
      filetype = vim.bo[bufnr].filetype,
    })
    if ok and type(custom) == "string" and custom ~= "" then
      return vim.fs.normalize(custom)
    end
    return nil
  end

  local function resolve_marker()
    local found = vim.fs.find(M.config.root.markers, {
      path = file_dir,
      upward = true,
      limit = 1,
    })
    if #found > 0 then
      return vim.fs.dirname(found[1])
    end
    return nil
  end

  local function resolve_lsp()
    if not M.config.root.use_lsp then
      return nil
    end
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
      if client and client.config and type(client.config.root_dir) == "string" and client.config.root_dir ~= "" then
        local lsp_root = vim.fs.normalize(client.config.root_dir)
        if is_ancestor(lsp_root, file) then
          return lsp_root
        end
      end
    end
    return nil
  end

  local resolvers = {
    custom = resolve_custom,
    marker = resolve_marker,
    lsp = resolve_lsp,
    file = function()
      return file_dir
    end,
  }

  local strategy = M.config.root.strategy
  if type(strategy) ~= "table" or #strategy == 0 then
    strategy = { "custom", "marker", "lsp", "file" }
  end

  for _, source in ipairs(strategy) do
    local resolver = resolvers[source]
    if resolver then
      local root = resolver()
      if type(root) == "string" and root ~= "" then
        return vim.fs.normalize(root), source
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

local function cf_apply_start_cwd(problem_root)
  local mode = M.config.cf.chdir_on_start
  if mode == nil or mode == false then
    return
  end
  if mode == true then
    mode = "tab"
  end

  local escaped = vim.fn.fnameescape(problem_root)
  if mode == "tab" then
    vim.cmd("tcd " .. escaped)
  elseif mode == "window" then
    vim.cmd("lcd " .. escaped)
  elseif mode == "global" then
    vim.cmd("cd " .. escaped)
  end
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

local function cf_problem_cache_path(root)
  local name = M.config.cf.problem.cache_file or ".runic-problem.md"
  return vim.fs.joinpath(root, name)
end

local function cf_problem_urls(meta)
  local contest = tostring(meta.contest)
  local problem = tostring(meta.problem)
  local lang = M.config.cf.problem.lang
  local q = ""
  if type(lang) == "string" and lang ~= "" then
    q = "?locale=" .. lang
  end
  return {
    string.format("https://codeforces.com/contest/%s/problem/%s%s", contest, problem, q),
    string.format("https://codeforces.com/problemset/problem/%s/%s%s", contest, problem, q),
  }
end

local function cf_proxy_url(url)
  local normalized = tostring(url):gsub("^https?://", "http://")
  local base = M.config.cf.problem.proxy_base or "https://r.jina.ai/http://"
  return base .. normalized:gsub("^http://", "")
end

local function cf_fetch_url(url)
  local out = vim.fn.system({
    "curl",
    "-sL",
    "--connect-timeout",
    "5",
    "--max-time",
    "20",
    "-A",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
    url,
  })
  return out, vim.v.shell_error
end

local function cf_fetch_url_async(url, cb)
  if vim.system then
    vim.system({
      "curl",
      "-sL",
      "--connect-timeout",
      "5",
      "--max-time",
      "20",
      "-A",
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
      url,
    }, { text = true }, function(res)
      vim.schedule(function()
        cb(res.stdout or "", res.code or 1)
      end)
    end)
    return
  end

  local out, code = cf_fetch_url(url)
  cb(out, code)
end

local function cf_is_challenge_page(html)
  local lower = (html or ""):lower()
  return lower:find("just a moment") ~= nil
    or lower:find("__cf_chl_opt") ~= nil
    or lower:find("enable javascript and cookies to continue") ~= nil
    or lower:find("cf%-challenge") ~= nil
end

local function cf_problem_markdown_from_text(meta, url, text)
  local raw = (text or ""):gsub("\r", "")
  raw = raw:gsub("^%s*Title:%s*.-\n", "")
  raw = raw:gsub("^%s*URL Source:%s*.-\n", "")
  raw = raw:gsub("^%s*Markdown Content:%s*\n", "")
  raw = raw:gsub("^\n+", "")

  local all = vim.split(raw, "\n", { plain = true })

  local function next_nonempty(idx)
    local i = idx + 1
    while i <= #all do
      if all[i]:match("%S") then
        return i, all[i]
      end
      i = i + 1
    end
    return nil, nil
  end

  local title_idx, title = nil, nil
  for i, line in ipairs(all) do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed:match("^[A-Z]%.[%s].+") then
      title_idx = i
      title = trimmed
      break
    end
  end
  if not title then
    title = tostring(meta.contest) .. tostring(meta.problem)
    title_idx = 1
  end

  local time_limit, memory_limit, input_spec, output_spec
  local tags = {}
  local rating
  for i, line in ipairs(all) do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    local lower = trimmed:lower()
    if lower == "time limit per test" then
      local _, v = next_nonempty(i)
      time_limit = v or time_limit
    elseif lower == "memory limit per test" then
      local _, v = next_nonempty(i)
      memory_limit = v or memory_limit
    elseif lower == "input" then
      local _, v = next_nonempty(i)
      if type(v) == "string" then
        local vl = v:lower()
        if vl:match("standard%s+input") or vl == "stdin" then
          input_spec = input_spec or v
        end
      end
    elseif lower == "output" then
      local _, v = next_nonempty(i)
      if type(v) == "string" then
        local vl = v:lower()
        if vl:match("standard%s+output") or vl == "stdout" then
          output_spec = output_spec or v
        end
      end
    end
  end

  local tags_start = nil
  for i, line in ipairs(all) do
    if line:lower():match("^%s*→%s*problem%s+tags%s*$") then
      tags_start = i
      break
    end
  end
  if tags_start then
    for i = tags_start + 1, #all do
      local trimmed = all[i]:gsub("^%s+", ""):gsub("%s+$", "")
      if trimmed == "" then
        -- skip
      elseif trimmed:match("^%*") then
        local r = trimmed:match("%*%s*(%d+)")
        if r then
          rating = r
        end
      elseif trimmed:lower():match("^no tag edit access") or trimmed:match("^%*") or trimmed:match("^%[") or trimmed:match("^→") then
        break
      elseif trimmed:match("^%*%s+%[") then
        break
      else
        tags[#tags + 1] = trimmed
      end
    end
  end

  local body = {}
  local blank = false
  for i = title_idx, #all do
    local line = all[i]
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    local lower = trimmed:lower()

    local drop = false
    if trimmed == "" then
      if blank then
        drop = true
      else
        blank = true
      end
    else
      blank = false
      if trimmed:match("^%[!%[Image")
        or trimmed:match("^%*%s+%[")
        or trimmed:match("^%|.*%|$")
        or trimmed:match("^→")
        or lower:match("^want to solve the contest problems")
        or lower:match("^virtual contest is a way")
        or lower:match("^no tag edit access")
        or lower:match("^desktop version")
        or lower == "copy"
      then
        drop = true
      end
    end

    if not drop then
      body[#body + 1] = line
    end
  end

  local cleaned = table.concat(body, "\n")
  local function drop_leading_header_block(s)
    local lines = vim.split(s, "\n", { plain = true })
    local i = 1
    local function trim(v)
      return v:gsub("^%s+", ""):gsub("%s+$", "")
    end
    local function skip_blank()
      while i <= #lines and trim(lines[i]) == "" do
        i = i + 1
      end
    end
    skip_blank()
    if trim(lines[i] or "") == title then
      i = i + 1
    end
    skip_blank()
    local function skip_pair(label)
      skip_blank()
      if trim(lines[i] or ""):lower() == label then
        i = i + 1
        skip_blank()
        i = i + 1
        skip_blank()
      end
    end
    skip_pair("time limit per test")
    skip_pair("memory limit per test")
    skip_pair("input")
    skip_pair("output")
    return table.concat(vim.list_slice(lines, i), "\n")
  end
  cleaned = drop_leading_header_block(cleaned)
  cleaned = cleaned:gsub("%$([^$]+)%$", function(expr)
    local e = expr
    e = e:gsub("\\leq", "<=")
    e = e:gsub("\\geq", ">=")
    e = e:gsub("\\neq", "!=")
    e = e:gsub("\\times", "*")
    e = e:gsub("\\cdot", "*")
    e = e:gsub("\\%s+", "")
    e = e:gsub("%s+", " ")
    e = e:gsub("^%s+", ""):gsub("%s+$", "")
    return e
  end)
  cleaned = cleaned:gsub("%)%s*—%s*", ") — ")
  cleaned = cleaned:gsub("([%w%)])—([%w%(])", "%1 — %2")
  cleaned = cleaned:gsub("([%w%)])—%s+", "%1 — ")
  cleaned = cleaned:gsub("\n\n\n+", "\n\n")
  cleaned = cleaned:gsub("^\n+", ""):gsub("\n+$", "")

  local lines = {
    "# " .. title,
    "",
    "- URL: " .. url,
  }
  if time_limit then
    lines[#lines + 1] = "- Time limit: " .. time_limit
  end
  if memory_limit then
    lines[#lines + 1] = "- Memory limit: " .. memory_limit
  end
  if input_spec then
    lines[#lines + 1] = "- Input: " .. input_spec
  end
  if output_spec then
    lines[#lines + 1] = "- Output: " .. output_spec
  end
  if #tags > 0 then
    lines[#lines + 1] = "- Tags: " .. table.concat(tags, ", ")
  end
  if rating then
    lines[#lines + 1] = "- Rating: " .. rating
  end
  lines[#lines + 1] = "- Source: proxy fallback"
  lines[#lines + 1] = "- Fetched: " .. os.date("!%Y-%m-%dT%H:%M:%SZ")
  lines[#lines + 1] = ""
  lines[#lines + 1] = "---"
  lines[#lines + 1] = ""
  lines[#lines + 1] = cleaned

  return table.concat(lines, "\n")
end

local function cf_problem_error_markdown(meta, err)
  local urls = cf_problem_urls(meta)
  local lines = {
    "# " .. tostring(meta.contest) .. tostring(meta.problem),
    "",
    "Could not fetch problem statement automatically.",
    "",
    "- Reason: " .. tostring(err or "unknown"),
    "- Open in browser: " .. urls[1],
    "- Fallback URL: " .. urls[2],
    "",
    "---",
    "",
    "You can still continue solving in `main.cpp` and import samples manually.",
  }
  return table.concat(lines, "\n")
end

local function cf_decode_html_entities(text)
  local out = text
  out = out:gsub("&nbsp;", " ")
  out = out:gsub("&lt;", "<")
  out = out:gsub("&gt;", ">")
  out = out:gsub("&amp;", "&")
  out = out:gsub("&quot;", '"')
  out = out:gsub("&#39;", "'")
  out = out:gsub("&#(%d+);", function(num)
    local n = tonumber(num)
    if not n then
      return ""
    end
    local ok, ch = pcall(vim.fn.nr2char, n)
    return ok and ch or ""
  end)
  out = out:gsub("&#x([%da-fA-F]+);", function(hex)
    local n = tonumber(hex, 16)
    if not n then
      return ""
    end
    local ok, ch = pcall(vim.fn.nr2char, n)
    return ok and ch or ""
  end)
  return out
end

local function cf_strip_tags(text)
  return text:gsub("<[^>]->", "")
end

local function cf_extract_div_at(html, start_pos)
  local pos = start_pos
  local depth = 0
  while true do
    local s, e, close = html:find("<%s*(/?)%s*[dD][iI][vV][^>]*>", pos)
    if not s then
      return nil
    end
    if close == "" then
      depth = depth + 1
    else
      depth = depth - 1
      if depth == 0 then
        return html:sub(start_pos, e), start_pos, e
      end
    end
    pos = e + 1
  end
end

local function cf_find_div_with_class(html, class_name)
  local pos = 1
  local class_pat = "(^|%s)" .. vim.pesc(class_name) .. "(%s|$)"
  while true do
    local s, e, quote, classes = html:find("<%s*[dD][iI][vV][^>]-class%s*=%s*([\"'])(.-)%1[^>]*>", pos)
    if not s then
      return nil
    end
    if quote and classes and classes:match(class_pat) then
      return cf_extract_div_at(html, s)
    end
    pos = e + 1
  end
end

local function cf_find_problem_statement(html)
  return cf_find_div_with_class(html, "problem-statement")
end

local function cf_find_class_div(html, class_name)
  return cf_find_div_with_class(html, class_name)
end

local function cf_textify_html(html)
  local text = html:gsub("\r", "")
  local pre_blocks = {}
  text = text:gsub("<pre[^>]*>(.-)</pre>", function(inner)
    local idx = #pre_blocks + 1
    local cleaned = inner:gsub("<br%s*/?>", "\n")
    cleaned = cf_strip_tags(cleaned)
    cleaned = cf_decode_html_entities(cleaned)
    cleaned = cleaned:gsub("^\n+", ""):gsub("\n+$", "")
    pre_blocks[idx] = "```\n" .. cleaned .. "\n```"
    return "\n@@RUNIC_PRE_" .. tostring(idx) .. "@@\n"
  end)

  text = text:gsub("<br%s*/?>", "\n")
  text = text:gsub("</p>", "\n\n")
  text = text:gsub("</div>", "\n")
  text = text:gsub("<li[^>]*>", "\n- ")
  text = text:gsub("</li>", "\n")
  text = text:gsub("<[^>]->", "")
  text = cf_decode_html_entities(text)
  text = text:gsub("[ \t]+", " ")
  text = text:gsub("\n[ \t]+", "\n")
  text = text:gsub("[ \t]+\n", "\n")
  text = text:gsub("\n\n\n+", "\n\n")
  text = text:gsub("^\n+", ""):gsub("\n+$", "")

  text = text:gsub("@@RUNIC_PRE_(%d+)@@", function(i)
    return pre_blocks[tonumber(i)] or ""
  end)
  return text
end

local function cf_header_value(statement_html, class_name)
  local div = cf_find_class_div(statement_html, class_name)
  if not div then
    return nil
  end
  local v = div:gsub('<div class="property%-title">.-</div>', "")
  v = cf_strip_tags(v)
  v = cf_decode_html_entities(v)
  v = v:gsub("^%s+", ""):gsub("%s+$", "")
  if v == "" then
    return nil
  end
  return v
end

local function cf_problem_markdown(meta, url, statement_html)
  local title = statement_html:match('<div class="title">(.-)</div>')
  title = title and cf_decode_html_entities(cf_strip_tags(title)):gsub("^%s+", ""):gsub("%s+$", "") or (tostring(meta.contest) .. tostring(meta.problem))
  local header = cf_find_class_div(statement_html, "header")
  local body_html = statement_html
  if header then
    body_html = body_html:gsub(vim.pesc(header), "", 1)
  end

  local lines = {
    "# " .. title,
    "",
    "- URL: " .. url,
  }
  local time_limit = cf_header_value(statement_html, "time-limit")
  local memory_limit = cf_header_value(statement_html, "memory-limit")
  local input = cf_header_value(statement_html, "input-file")
  local output = cf_header_value(statement_html, "output-file")
  if time_limit then
    lines[#lines + 1] = "- Time limit: " .. time_limit
  end
  if memory_limit then
    lines[#lines + 1] = "- Memory limit: " .. memory_limit
  end
  if input then
    lines[#lines + 1] = "- Input: " .. input
  end
  if output then
    lines[#lines + 1] = "- Output: " .. output
  end
  lines[#lines + 1] = "- Fetched: " .. os.date("!%Y-%m-%dT%H:%M:%SZ")
  lines[#lines + 1] = ""
  lines[#lines + 1] = "---"
  lines[#lines + 1] = ""

  local text = cf_textify_html(body_html)
  if text ~= "" then
    lines[#lines + 1] = text
  end
  return table.concat(lines, "\n")
end

local function cf_fetch_problem_markdown(meta)
  local urls = cf_problem_urls(meta)
  local last_err = nil
  for _, url in ipairs(urls) do
    local html, code = cf_fetch_url(url)
    if code ~= 0 or type(html) ~= "string" or html == "" then
      last_err = "fetch failed"
    elseif cf_is_challenge_page(html) then
      last_err = "blocked by Codeforces anti-bot page"
    else
      local statement = cf_find_problem_statement(html)
      if not statement then
        statement = cf_find_class_div(html, "ttypography")
      end
      if statement and statement ~= "" then
        return cf_problem_markdown(meta, url, statement), url, nil
      end
      last_err = "problem statement block not found"
    end
  end

  if M.config.cf.problem.proxy_fallback then
    for _, url in ipairs(urls) do
      local purl = cf_proxy_url(url)
      local body, code = cf_fetch_url(purl)
      if code == 0 and type(body) == "string" and body ~= "" then
        if not cf_is_challenge_page(body) then
          return cf_problem_markdown_from_text(meta, url, body), url, nil
        end
      end
    end
    if last_err == nil then
      last_err = "proxy fallback failed"
    end
  end

  return nil, nil, last_err or "unknown fetch error"
end

local function cf_fetch_problem_markdown_async(meta, cb)
  local urls = cf_problem_urls(meta)
  local last_err = nil
  local max_attempts = 2

  local function done(markdown, url, err)
    cb(markdown, url, err)
  end

  local function fetch_with_retry(url, attempt, cb_fetch)
    cf_fetch_url_async(url, function(body, code)
      if code == 0 and type(body) == "string" and body ~= "" then
        cb_fetch(body, code)
        return
      end

      if attempt < max_attempts then
        vim.defer_fn(function()
          fetch_with_retry(url, attempt + 1, cb_fetch)
        end, 250)
        return
      end

      cb_fetch(body, code)
    end)
  end

  local function try_proxy(i)
    if not M.config.cf.problem.proxy_fallback then
      done(nil, nil, last_err or "unknown fetch error")
      return
    end
    if i > #urls then
      done(nil, nil, last_err or "proxy fallback failed")
      return
    end

    local url = urls[i]
    local purl = cf_proxy_url(url)
    fetch_with_retry(purl, 1, function(body, code)
      if code == 0 and type(body) == "string" and body ~= "" and not cf_is_challenge_page(body) then
        done(cf_problem_markdown_from_text(meta, url, body), url, nil)
      else
        last_err = "proxy fallback failed (code=" .. tostring(code) .. ")"
        try_proxy(i + 1)
      end
    end)
  end

  local function try_direct(i)
    if i > #urls then
      try_proxy(1)
      return
    end

    local url = urls[i]
    fetch_with_retry(url, 1, function(html, code)
      if code ~= 0 or type(html) ~= "string" or html == "" then
        last_err = "fetch failed (code=" .. tostring(code) .. ")"
        try_direct(i + 1)
        return
      end

      if cf_is_challenge_page(html) then
        last_err = "blocked by Codeforces anti-bot page"
        try_direct(i + 1)
        return
      end

      local statement = cf_find_problem_statement(html)
      if not statement then
        statement = cf_find_class_div(html, "ttypography")
      end
      if statement and statement ~= "" then
        done(cf_problem_markdown(meta, url, statement), url, nil)
      else
        last_err = "problem statement block not found"
        try_direct(i + 1)
      end
    end)
  end

  try_direct(1)
end

local function cf_problem_state_reset()
  state.cf_problem.winid = nil
  state.cf_problem.bufnr = nil
  state.cf_problem.root = nil
  state.cf_problem.url = nil
  state.cf_problem.markdown = nil
end

local function cf_problem_write_buffer(bufnr, markdown)
  local function to_compact(md)
    local src = vim.split(md, "\n", { plain = true })
    local out = {}
    local in_header = true
    local in_code = false
    for _, line in ipairs(src) do
      if line:match("^```") then
        in_code = not in_code
      end
      if in_header then
        if line:match("^---%s*$") then
          in_header = false
        elseif line:match("^%-%s(Source|Fetched):") then
          goto continue
        elseif line:match("^%-%sURL:") then
          line = line:gsub("%?locale=[%w_%-]+", "")
        end
      end
      if not in_code then
        line = line:gsub("%s+", " ")
      end
      out[#out + 1] = line
      ::continue::
    end
    local compact = table.concat(out, "\n")
    compact = compact:gsub("\n\n\n+", "\n\n")
    compact = compact:gsub("^\n+", ""):gsub("\n+$", "")
    return compact
  end

  local view = M.config.cf.problem.view
  local rendered = markdown
  if view == "compact" then
    rendered = to_compact(markdown)
  end

  local lines = vim.split(rendered, "\n", { plain = true })

  local function add_hl(group, row, start_col, end_col)
    if row < 0 or row >= #lines then
      return
    end
    pcall(vim.api.nvim_buf_add_highlight, bufnr, cf_problem_ns, group, row, start_col, end_col)
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, cf_problem_ns, 0, -1)

  local in_code = false
  for i, line in ipairs(lines) do
    local row = i - 1
    if line:match("^```") then
      in_code = not in_code
      add_hl("Delimiter", row, 0, #line)
    elseif in_code then
      add_hl("String", row, 0, #line)
    elseif line:match("^# ") then
      add_hl("Title", row, 0, #line)
    elseif line:match("^---%s*$") then
      add_hl("Comment", row, 0, #line)
    elseif line:match("^%-%s") then
      add_hl("Comment", row, 0, #line)
      local colon = line:find(":", 1, true)
      if colon then
        add_hl("Identifier", row, 2, colon)
      end
      local url_s, url_e = line:find("https?://%S+")
      if url_s and url_e then
        add_hl("Underlined", row, url_s - 1, url_e)
      end
    elseif line == "Input" or line == "Output" or line == "Example" or line == "Examples" or line == "Note" then
      add_hl("Special", row, 0, #line)
    end
  end

  vim.bo[bufnr].modifiable = false
end

local function cf_problem_ensure_pane(root, title)
  local prev_win = vim.api.nvim_get_current_win()
  local winid = state.cf_problem.winid
  local bufnr = state.cf_problem.bufnr

  if not (winid and vim.api.nvim_win_is_valid(winid)) then
    vim.cmd("rightbelow vsplit")
    winid = vim.api.nvim_get_current_win()
    pcall(vim.api.nvim_win_set_width, winid, tonumber(M.config.cf.problem.pane_width) or 72)
  else
    vim.api.nvim_set_current_win(winid)
  end

  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    bufnr = vim.api.nvim_create_buf(false, true)
  end
  vim.api.nvim_win_set_buf(winid, bufnr)

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].buflisted = false
  vim.api.nvim_buf_set_name(bufnr, "runic://cf/problem/" .. title)

  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].wrap = true
  vim.wo[winid].linebreak = true
  vim.wo[winid].breakindent = true
  vim.wo[winid].signcolumn = "no"

  state.cf_problem.winid = winid
  state.cf_problem.bufnr = bufnr
  state.cf_problem.root = root

  if vim.api.nvim_win_is_valid(prev_win) then
    vim.api.nvim_set_current_win(prev_win)
  end
  return bufnr
end

local function cf_problem_load_async(root, opts, cb)
  opts = opts or {}
  local meta = read_cf_meta(root)
  if not meta or not meta.contest or not meta.problem then
    cb(nil, nil, "CF metadata missing. Use RunicCFStart first.")
    return
  end

  local cache_path = cf_problem_cache_path(root)
  if M.config.cf.problem.cache and not opts.refresh and file_exists(cache_path) then
    local cached = read_file(cache_path)
    if type(cached) == "string" and cached ~= "" then
      local u = cf_problem_urls(meta)[1]
      cb(cached, u, nil)
      return
    end
  end

  local function done(markdown, url, err)
    cb(markdown, url, err)
  end

  cf_fetch_problem_markdown_async(meta, function(markdown, url, fetch_err)
    if markdown then
      if M.config.cf.problem.cache then
        write_file(cache_path, markdown)
      end
      done(markdown, url, nil)
      return
    end

    if M.config.cf.problem.cache and file_exists(cache_path) then
      local cached = read_file(cache_path)
      if type(cached) == "string" and cached ~= "" then
        local u = cf_problem_urls(meta)[1]
        done(cached, u, nil)
        return
      end
    end

    done(nil, nil, fetch_err or "unable to load problem statement")
  end)
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

local function set_run_status(update)
  state.run_status = vim.tbl_extend("force", state.run_status, update)
end

local function fire_user_event(name)
  pcall(vim.api.nvim_exec_autocmds, "User", { pattern = name })
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

  state.stop_requested = false
  local started_at = vim.uv.hrtime()
  set_run_status({
    status = "running",
    cmd = cmd,
    cwd = cwd,
    started_at = started_at,
    ended_at = nil,
    duration_ms = nil,
    exit_code = nil,
  })
  fire_user_event("RunicJobStart")

  local job = vim.fn.termopen({ vim.o.shell, "-lc", cmd }, {
    cwd = cwd,
    on_stdout = function(_, data)
      maybe_open_url_from_lines(data)
    end,
    on_stderr = function(_, data)
      maybe_open_url_from_lines(data)
    end,
    on_exit = function(_, code)
      local ended_at = vim.uv.hrtime()
      local duration_ms = math.floor((ended_at - started_at) / 1e6)
      local status = "success"
      if state.stop_requested then
        status = "stopped"
      elseif code ~= 0 then
        status = "failed"
      end
      set_run_status({
        status = status,
        ended_at = ended_at,
        duration_ms = duration_ms,
        exit_code = code,
      })
      state.active_job = nil
      fire_user_event("RunicJobEnd")
      if status == "failed" then
        vim.schedule(function()
          vim.notify("Runic command exited with code " .. tostring(code) .. " in " .. tostring(duration_ms) .. "ms", vim.log.levels.WARN)
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
    if has_any_file(root, { "pyproject.toml", "uv.lock", "poetry.lock", "requirements.txt", "Pipfile", "pdm.lock", "hatch.toml", "tox.ini", "noxfile.py" }) then
      local qfile = shellescape(file)
      if has_exec("uv") then
        out[#out + 1] = candidate("project_python", { kind = "project", priority = 8800, command = "uv run " .. qfile, cwd = root, reason = "Python via uv" })
      elseif has_exec("pdm") and has_file(root, "pdm.lock") then
        out[#out + 1] = candidate("project_python", { kind = "project", priority = 8790, command = "pdm run python " .. qfile, cwd = root, reason = "Python via pdm" })
      elseif has_exec("pipenv") and has_file(root, "Pipfile") then
        out[#out + 1] = candidate("project_python", { kind = "project", priority = 8780, command = "pipenv run python " .. qfile, cwd = root, reason = "Python via pipenv" })
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

  if not is_rule_disabled("project_php") and has_file(root, "artisan") then
    out[#out + 1] = candidate("project_php", {
      kind = "project",
      priority = 7890,
      command = "php artisan serve",
      cwd = root,
      reason = "Laravel artisan serve",
    })
  end

  if not is_rule_disabled("project_scripting") and has_any_file(root, { "deno.json", "deno.jsonc" }) then
    out[#out + 1] = candidate("project_scripting", {
      kind = "project",
      priority = 7820,
      command = "deno task start || deno task dev || deno task test",
      cwd = root,
      reason = "Deno task",
    })
  end

  if not is_rule_disabled("project_scripting") and has_file(root, "build.zig") then
    out[#out + 1] = candidate("project_scripting", {
      kind = "project",
      priority = 7810,
      command = "zig build run || zig build",
      cwd = root,
      reason = "Zig build",
    })
  end

  if not is_rule_disabled("project_scripting") and has_file(root, "stack.yaml") then
    out[#out + 1] = candidate("project_scripting", {
      kind = "project",
      priority = 7800,
      command = "stack run || stack test",
      cwd = root,
      reason = "Haskell stack",
    })
  end

  if not is_rule_disabled("project_scripting") and #vim.fs.find("*.cabal", { path = root, type = "file", limit = 1 }) > 0 then
    out[#out + 1] = candidate("project_scripting", {
      kind = "project",
      priority = 7790,
      command = "cabal run || cabal test",
      cwd = root,
      reason = "Haskell cabal",
    })
  end

  if not is_rule_disabled("project_scripting") and has_any_file(root, { "deps.edn", "project.clj" }) then
    out[#out + 1] = candidate("project_scripting", {
      kind = "project",
      priority = 7780,
      command = has_file(root, "deps.edn") and "clj -M" or "lein run",
      cwd = root,
      reason = "Clojure project",
    })
  end

  return out
end

local function add_task_candidates(ctx, opts)
  local out = {}
  local root = ctx.root
  opts = opts or {}
  local include_in_auto = M.config.tasks.include_in_auto
  if opts.force_include then
    include_in_auto = true
  end
  if not M.config.tasks.enabled or not include_in_auto then
    return out
  end

  local base = tonumber(M.config.tasks.base_priority) or 7600
  local scripts = read_package_scripts(root)
  local npm_order = { "dev", "start", "test", "build", "lint" }
  for idx, name in ipairs(npm_order) do
    if scripts[name] and not is_rule_disabled("task_npm") then
      out[#out + 1] = candidate("task_npm", {
        kind = "task",
        priority = base - idx,
        command = command_for_script(default_pm(root), name),
        cwd = root,
        reason = "Task script '" .. name .. "'",
      })
    end
  end

  if has_any_file(root, { "justfile", ".justfile" }) and not is_rule_disabled("task_just") then
    local just_tasks = discover_just_tasks(root)
    for idx, name in ipairs(just_tasks) do
      out[#out + 1] = candidate("task_just", {
        kind = "task",
        priority = base - 30 - idx,
        command = "just " .. name,
        cwd = root,
        reason = "Just task '" .. name .. "'",
      })
      if idx >= 5 then
        break
      end
    end
  end

  if has_taskfile(root) and not is_rule_disabled("task_taskfile") then
    local task_tasks = discover_taskfile_tasks(root)
    for idx, name in ipairs(task_tasks) do
      out[#out + 1] = candidate("task_taskfile", {
        kind = "task",
        priority = base - 60 - idx,
        command = "task " .. name,
        cwd = root,
        reason = "Taskfile task '" .. name .. "'",
      })
      if idx >= 5 then
        break
      end
    end
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
    bash = "bash " .. qfile,
    ksh = "ksh " .. qfile,
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
    kts = "kotlinc -script " .. qfile,
    scala = (has_exec("scala-cli") and ("scala-cli run " .. qfile) or ("scala " .. qfile)),
    fsx = "dotnet fsi " .. qfile,
    swift = "swift " .. qfile,
    nim = "nim c -r " .. qfile,
    zig = "zig run " .. qfile,
    dart = "dart run " .. qfile,
    exs = "elixir " .. qfile,
    rkt = "racket " .. qfile,
    scm = (has_exec("guile") and ("guile " .. qfile) or "scheme " .. qfile),
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

local function add_test_intent_candidates(ctx)
  local out = {}
  local file = ctx.file
  local qfile = shellescape(file)
  local root = ctx.root

  if (ctx.filetype == "python" or ctx.ext == "py") and not is_rule_disabled("project_python_test") then
    if has_exec("pytest") then
      out[#out + 1] = candidate("project_python_test", {
        kind = "project",
        priority = 8890,
        command = "pytest " .. qfile,
        cwd = root,
        reason = "Python targeted pytest",
      })
    else
      out[#out + 1] = candidate("project_python_test", {
        kind = "project",
        priority = 8880,
        command = "python3 -m pytest " .. qfile,
        cwd = root,
        reason = "Python targeted pytest module",
      })
    end
  end

  if has_file(root, "go.mod") and not is_rule_disabled("project_go_test_target") then
    local rel = relative_to(vim.fs.dirname(file), root)
    local pkg = "./" .. rel
    if rel == "." or rel == "" then
      pkg = "./..."
    end
    out[#out + 1] = candidate("project_go_test_target", {
      kind = "project",
      priority = 8580,
      command = "go test " .. shellescape(pkg),
      cwd = root,
      reason = "Go package test",
    })
  end

  if has_file(root, "Cargo.toml") and not is_rule_disabled("project_rust_test_target") then
    local rel = relative_to(file, root)
    if rel:match("^tests/.+%.rs$") then
      out[#out + 1] = candidate("project_rust_test_target", {
        kind = "project",
        priority = 8390,
        command = "cargo test --test " .. path_stem(rel),
        cwd = root,
        reason = "Rust integration test target",
      })
    else
      out[#out + 1] = candidate("project_rust_test_target", {
        kind = "project",
        priority = 8380,
        command = "cargo test",
        cwd = root,
        reason = "Rust cargo test",
      })
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
  if mode ~= "file" then
    append(add_task_candidates(ctx))
  end
  if mode ~= "project" then
    append(add_file_candidates(ctx))
  end
  if intent == "test" then
    append(add_test_intent_candidates(ctx))
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

  state.stop_requested = true
  local ok = vim.fn.jobstop(active.id)
  if ok == 1 then
    vim.notify("Runic stopped active process", vim.log.levels.INFO)
  else
    vim.notify("Runic failed to stop active process", vim.log.levels.WARN)
  end
end

function M.root(args)
  local ctx, err = build_context({ bufnr = 0 })
  if not ctx then
    vim.notify("Runic: " .. err, vim.log.levels.WARN)
    return
  end

  local target = args and args.path or ""
  if type(target) == "string" and target ~= "" then
    local root = expand_path(target)
    set_root_override(root)
    state.cache_gen = state.cache_gen + 1
    state.cache = {}
    vim.notify("Runic root override set: " .. root, vim.log.levels.INFO)
    return
  end

  local override = get_root_override()
  local lines = {
    "Runic Root",
    string.rep("=", 10),
    "resolved: " .. ctx.root,
    "source: " .. ctx.root_source,
  }
  if type(override) == "string" and override ~= "" then
    lines[#lines + 1] = "override: " .. override
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Runic" })
end

function M.root_reset()
  reset_root_override()
  state.cache_gen = state.cache_gen + 1
  state.cache = {}
  vim.notify("Runic root override cleared", vim.log.levels.INFO)
end

function M.status()
  local st = state.run_status
  local lines = {
    "Runic Status",
    string.rep("=", 12),
    "status: " .. tostring(st.status or "idle"),
  }
  if st.cmd then
    lines[#lines + 1] = "cmd: " .. st.cmd
  end
  if st.cwd then
    lines[#lines + 1] = "cwd: " .. st.cwd
  end
  if st.exit_code ~= nil then
    lines[#lines + 1] = "exit_code: " .. tostring(st.exit_code)
  end
  if st.duration_ms then
    lines[#lines + 1] = "duration_ms: " .. tostring(st.duration_ms)
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Runic" })
end

function M.tasks()
  local ctx, err = build_context({ bufnr = 0 })
  if not ctx then
    vim.notify("Runic: " .. err, vim.log.levels.WARN)
    return
  end

  local tasks = add_task_candidates(ctx, { force_include = true })
  if #tasks == 0 then
    vim.notify("Runic: no project tasks discovered", vim.log.levels.INFO)
    return
  end
  sort_candidates(tasks)

  vim.ui.select(tasks, {
    prompt = "Runic tasks",
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

function M.keymaps_info()
  local report = state.keymap_report or { active = {}, skipped = {} }
  local lines = {
    "Runic Keymaps",
    string.rep("=", 13),
    "mode: " .. tostring(M.config.keymap_mode),
    "",
    "active:",
  }

  if #report.active == 0 then
    lines[#lines + 1] = "  (none)"
  else
    for _, item in ipairs(report.active) do
      lines[#lines + 1] = "  " .. item
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "skipped (conflicts):"
  if #report.skipped == 0 then
    lines[#lines + 1] = "  (none)"
  else
    for _, item in ipairs(report.skipped) do
      lines[#lines + 1] = "  " .. item
    end
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Runic" })
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

  if state.cf_problem.root and state.cf_problem.root ~= problem_root then
    M.cf_problem_close()
  end

  cf_apply_start_cwd(problem_root)
  vim.cmd.edit(main_cpp)

  if M.config.cf.problem.auto_open then
    local refresh = M.config.cf.problem.refresh_on_start == true
    M.cf_problem_open({ root = problem_root, refresh = refresh })
  end

  vim.notify("Runic CF workspace ready: " .. problem_root, vim.log.levels.INFO)
end

function M.cf_mode_on()
  M.config.cf.enabled = true
  vim.notify("Runic CF mode enabled", vim.log.levels.INFO)
end

function M.cf_mode_off()
  M.config.cf.enabled = false
  M.cf_watch_stop()
  M.cf_problem_close()
  vim.notify("Runic CF mode disabled", vim.log.levels.INFO)
end

function M.cf_problem_open(opts)
  opts = opts or {}
  local root = opts.root
  if type(root) ~= "string" or root == "" then
    local err
    root, err = cf_root_for_current_buffer()
    if not root then
      vim.notify("Runic: " .. err, vim.log.levels.ERROR)
      return
    end
  end

  local meta = read_cf_meta(root)
  if not meta or not meta.contest or not meta.problem then
    vim.notify("CF metadata missing. Use RunicCFStart first.", vim.log.levels.ERROR)
    return
  end

  local title = tostring(meta.contest) .. tostring(meta.problem)
  local bufnr = cf_problem_ensure_pane(root, title)
  local request_id = (state.cf_problem.request_id or 0) + 1
  state.cf_problem.request_id = request_id

  cf_problem_write_buffer(bufnr, "Loading Codeforces problem statement...")

  cf_problem_load_async(root, { refresh = opts.refresh == true }, function(markdown, url, err)
    if request_id ~= state.cf_problem.request_id then
      return
    end
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
      return
    end
    if not markdown then
      local fallback = cf_problem_error_markdown(meta, err)
      state.cf_problem.markdown = fallback
      cf_problem_write_buffer(bufnr, fallback)
      vim.notify("Runic CF problem pane: " .. tostring(err), vim.log.levels.WARN)
      return
    end
    state.cf_problem.markdown = markdown
    cf_problem_write_buffer(bufnr, markdown)
    state.cf_problem.url = url
  end)
end

function M.cf_problem_refresh()
  M.cf_problem_open({ refresh = true })
end

function M.cf_problem_toggle_view()
  local cur = M.config.cf.problem.view
  local next_view = (cur == "compact") and "comfortable" or "compact"
  M.config.cf.problem.view = next_view

  local bufnr = state.cf_problem.bufnr
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) and type(state.cf_problem.markdown) == "string" and state.cf_problem.markdown ~= "" then
    cf_problem_write_buffer(bufnr, state.cf_problem.markdown)
  end
  vim.notify("Runic CF problem view: " .. next_view, vim.log.levels.INFO)
end

function M.cf_problem_close()
  state.cf_problem.request_id = (state.cf_problem.request_id or 0) + 1
  local winid = state.cf_problem.winid
  if winid and vim.api.nvim_win_is_valid(winid) then
    pcall(vim.api.nvim_win_close, winid, true)
  end
  local bufnr = state.cf_problem.bufnr
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
  cf_problem_state_reset()
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

register_commands = function()
  local specs = {
    { "RunicRun", function() M.run({ mode = "auto" }) end, "Run best runic candidate" },
    { "RunicAction", function() M.action({ mode = "auto" }) end, "Choose runic intent and run" },
    { "RunicPick", function() M.pick({ mode = "auto" }) end, "Pick runic candidate" },
    { "RunicRunFile", function() M.run({ mode = "file" }) end, "Runic file mode" },
    { "RunicRunProject", function() M.run({ mode = "project" }) end, "Runic project mode" },
    { "RunicPreview", function() M.preview({ mode = "auto" }) end, "Preview runic decision" },
    { "RunicExplain", function() M.explain({ mode = "auto" }) end, "Explain runic decision" },
    { "RunicKeymaps", M.keymaps_info, "Show runic keymap status" },
    { "RunicRoot", function(args) M.root({ path = args.args }) end, "Show or set runic root override" },
    { "RunicRootReset", M.root_reset, "Clear runic root override" },
    { "RunicStatus", M.status, "Show runic run status" },
    { "RunicLast", M.run_last, "Rerun last runic command" },
    { "RunicHistory", M.history_pick, "Pick from runic history" },
    { "RunicTasks", M.tasks, "Pick and run discovered project tasks" },
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
    { "RunicCFProblemOpen", M.cf_problem_open, "Open Codeforces problem pane" },
    { "RunicCFProblemRefresh", M.cf_problem_refresh, "Refresh Codeforces problem pane" },
    { "RunicCFProblemClose", M.cf_problem_close, "Close Codeforces problem pane" },
    { "RunicCFProblemToggleView", M.cf_problem_toggle_view, "Toggle CF problem pane view" },
  }

  for _, spec in ipairs(specs) do
    pcall(vim.api.nvim_del_user_command, spec[1])
    if spec[1] == "RunicCFStart" then
      vim.api.nvim_create_user_command(spec[1], spec[2], { desc = spec[3], nargs = "+" })
    elseif spec[1] == "RunicRoot" then
      vim.api.nvim_create_user_command(spec[1], spec[2], { desc = spec[3], nargs = "?", complete = "dir" })
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
  local mode = M.config.keymap_mode

  state.keymap_report = { active = {}, skipped = {} }

  if mode == "off" then
    state.keymaps = {}
    return
  end

  local function has_existing_map(lhs)
    if type(lhs) ~= "string" or lhs == "" then
      return false
    end
    local info = vim.fn.maparg(lhs, "n", false, true)
    if type(info) == "table" and next(info) ~= nil then
      return info.lhs == lhs
    end
    return false
  end

  local function map_safe(lhs, rhs, desc)
    if not lhs then
      return
    end

    if mode == "safe" and has_existing_map(lhs) then
      state.keymap_report.skipped[#state.keymap_report.skipped + 1] = lhs .. " -> " .. desc
      return
    end

    vim.keymap.set("n", lhs, rhs, { desc = desc })
    state.keymaps[#state.keymaps + 1] = lhs
    state.keymap_report.active[#state.keymap_report.active + 1] = lhs .. " -> " .. desc
  end

  for _, mapped in ipairs(state.keymaps) do
    pcall(vim.keymap.del, "n", mapped)
  end
  state.keymaps = {}

  if km.run then
    map_safe(km.run, function()
      M.run({ mode = "auto" })
    end, "Runic run")
  end
  if km.pick then
    map_safe(km.pick, function()
      M.pick({ mode = "auto" })
    end, "Runic pick")
  end
  if km.last then
    map_safe(km.last, M.run_last, "Runic last")
  end
  if km.legacy then
    map_safe(km.legacy, function()
      if vim.fn.exists(":RunFile") == 2 then
        vim.cmd.RunFile()
      else
        vim.notify("RunFile command is unavailable", vim.log.levels.WARN)
      end
    end, "Run file (legacy)")
  end

  if km.cf_mode_on then
    map_safe(km.cf_mode_on, M.cf_mode_on, "CF mode on")
  end
  if km.cf_mode_off then
    map_safe(km.cf_mode_off, M.cf_mode_off, "CF mode off")
  end
  if km.cf_status then
    map_safe(km.cf_status, M.cf_status, "CF status")
  end
  if km.cf_start then
    map_safe(km.cf_start, function()
      local contest = vim.fn.input("CF contest id: ")
      if contest == "" then
        return
      end
      local problem = vim.fn.input("CF problem index: ")
      if problem == "" then
        return
      end
      M.cf_start({ contest = contest, problem = problem })
    end, "CF new/start problem")
  end
  if km.cf_profile_contest then
    map_safe(km.cf_profile_contest, function()
      M.cf_set_profile("contest")
    end, "CF profile contest")
  end
  if km.cf_profile_debug then
    map_safe(km.cf_profile_debug, function()
      M.cf_set_profile("debug")
    end, "CF profile debug")
  end
  if km.cf_import then
    map_safe(km.cf_import, M.cf_import_samples, "CF import samples")
  end
  if km.cf_test then
    map_safe(km.cf_test, M.cf_test, "CF test samples")
  end
  if km.cf_watch_on then
    map_safe(km.cf_watch_on, M.cf_watch, "CF watch on")
  end
  if km.cf_watch_off then
    map_safe(km.cf_watch_off, M.cf_watch_stop, "CF watch off")
  end
  if km.cf_stress then
    map_safe(km.cf_stress, M.cf_stress, "CF stress")
  end
  if km.cf_replay then
    map_safe(km.cf_replay, M.cf_replay_fail, "CF replay fail")
  end
  if km.cf_check then
    map_safe(km.cf_check, M.cf_check, "CF check")
  end
  if km.cf_submit then
    map_safe(km.cf_submit, M.cf_submit, "CF submit manual")
  end
  if km.cf_problem_view then
    map_safe(km.cf_problem_view, M.cf_problem_toggle_view, "CF problem view")
  end

  if mode == "safe" and #state.keymap_report.skipped > 0 then
    vim.schedule(function()
      vim.notify(
        "Runic keymaps: " .. tostring(#state.keymap_report.skipped) .. " skipped due to existing mappings. Use :RunicKeymaps",
        vim.log.levels.INFO
      )
    end)
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

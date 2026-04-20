local M = {}

local state = {
  cache = {},
  cache_gen = 0,
  cache_hits = 0,
  cache_misses = 0,
  history = {},
  last = nil,
  keymaps = {},
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
    },
  },
  terminal = {
    use_snacks = false,
    focus = true,
    height = 12,
    close_keys = { "<Esc>", "q" },
    open_url = true,
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
}

local command_names = {
  "RunicRun",
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

  local function open_in_browser(url)
    if opened_urls[url] then
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
    java = "javac " .. qfile .. " && java " .. shellescape(stem(file)),
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
    ts = has_exec("bun") and ("bun " .. qfile) or (has_exec("deno") and ("deno run " .. qfile) or ("node " .. qfile)),
    tsx = has_exec("bun") and ("bun " .. qfile) or (has_exec("deno") and ("deno run " .. qfile) or ("node " .. qfile)),
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
  local ctx, err = build_context(opts)
  if not ctx then
    return nil, nil, err
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

register_commands = function()
  local specs = {
    { "RunicRun", function() M.run({ mode = "auto" }) end, "Run best runic candidate" },
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
  }

  for _, spec in ipairs(specs) do
    pcall(vim.api.nvim_del_user_command, spec[1])
    vim.api.nvim_create_user_command(spec[1], spec[2], { desc = spec[3] })
  end
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
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), M.config, opts or {})
  state.cache_gen = state.cache_gen + 1
  state.cache = {}

  clear_commands()
  if M.config.create_commands then
    register_commands()
  end
  if M.config.create_keymaps then
    register_keymaps()
  end

  vim.notify("Runic reconfigured", vim.log.levels.INFO)
  return M
end

function M.setup(opts)
  if not state.autocmd_setup then
    setup_cache_autocmds()
    state.autocmd_setup = true
  end
  return M.reconfigure(opts)
end

return M

local M = {}

local cache = {}
local cache_generation = 0
local cache_autocmd_setup = false
local setup_done = false

local defaults = {
  create_commands = true,
  create_keymaps = true,
  keymaps = {
    run = "<leader>r",
    pick = "<leader>rp",
    last = "<leader>rl",
    legacy = "<leader>R",
  },
}

M.config = vim.deepcopy(defaults)

local root_markers = {
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
}

local function file_exists(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.type == "file"
end

local function has_exec(name)
  return vim.fn.executable(name) == 1
end

local function shellescape(value)
  return vim.fn.shellescape(value)
end

local function stem(path)
  return vim.fn.fnamemodify(path, ":t:r")
end

local function find_root(start)
  local found = vim.fs.find(root_markers, {
    path = vim.fs.dirname(start),
    upward = true,
    limit = 1,
    stop = vim.fs.normalize("~"),
  })
  if #found > 0 then
    return vim.fs.dirname(found[1])
  end
  return vim.fs.dirname(start)
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

local function is_test_file(path)
  local name = vim.fn.fnamemodify(path, ":t")
  return name:match("_test%.") ~= nil
    or name:match("test_") ~= nil
    or name:match("%.test%.") ~= nil
    or name:match("%.spec%.") ~= nil
end

local function make_candidate(spec)
  spec.label = string.format("[%s] %s -> %s", spec.kind, spec.reason, spec.command)
  return spec
end

local function setup_cache_autocmds()
  if cache_autocmd_setup then
    return
  end
  cache_autocmd_setup = true

  vim.api.nvim_create_autocmd({ "BufWritePost", "DirChanged" }, {
    group = vim.api.nvim_create_augroup("smart-run-cache", { clear = true }),
    callback = function()
      cache_generation = cache_generation + 1
      cache = {}
    end,
  })
end

local function run_in_terminal(cmd, cwd)
  if vim.g.smart_run_use_snacks_terminal == true and _G.Snacks and Snacks.terminal then
    Snacks.terminal({ "zsh", "-lc", cmd }, { cwd = cwd })
    return
  end

  local prev_win = vim.api.nvim_get_current_win()
  vim.cmd("botright 12new")
  local term_win = vim.api.nvim_get_current_win()
  local term_buf = vim.api.nvim_get_current_buf()
  local focus_terminal = vim.g.smart_run_focus_terminal == true

  vim.bo[term_buf].bufhidden = "wipe"
  vim.bo[term_buf].swapfile = false
  vim.b[term_buf].smart_run_terminal = true

  local function close_term_window()
    if vim.api.nvim_win_is_valid(term_win) then
      vim.api.nvim_win_close(term_win, true)
    end
  end

  vim.keymap.set("t", "<Esc>", close_term_window, { buffer = term_buf, silent = true, desc = "Close smart run terminal" })
  vim.keymap.set("n", "<Esc>", close_term_window, { buffer = term_buf, silent = true, desc = "Close smart run terminal" })
  vim.keymap.set("n", "q", close_term_window, { buffer = term_buf, silent = true, desc = "Close smart run terminal" })

  vim.fn.termopen({ vim.o.shell, "-lc", cmd }, { cwd = cwd })

  if focus_terminal then
    vim.cmd("startinsert")
    return
  end

  if vim.api.nvim_win_is_valid(prev_win) then
    vim.api.nvim_set_current_win(prev_win)
  end
end

local function collect_override_candidates(ctx)
  local out = {}

  if type(vim.g.smart_run_command) == "string" and vim.g.smart_run_command ~= "" then
    out[#out + 1] = make_candidate({
      kind = "override",
      priority = 10000,
      command = vim.g.smart_run_command,
      cwd = ctx.root,
      reason = "Global override command",
    })
  end

  if type(vim.g.smart_run_filetype_commands) == "table" then
    local item = vim.g.smart_run_filetype_commands[ctx.filetype]
    if type(item) == "string" and item ~= "" then
      out[#out + 1] = make_candidate({
        kind = "override",
        priority = 9900,
        command = item,
        cwd = ctx.root,
        reason = "Filetype override command",
      })
    end
  end

  if type(vim.g.smart_run_resolver) == "function" then
    local ok, resolved = pcall(vim.g.smart_run_resolver, vim.deepcopy(ctx))
    if ok and type(resolved) == "table" then
      if type(resolved.command) == "string" and resolved.command ~= "" then
        out[#out + 1] = make_candidate({
          kind = "override",
          priority = resolved.priority or 9800,
          command = resolved.command,
          cwd = resolved.cwd or ctx.root,
          reason = resolved.reason or "Custom resolver override",
        })
      elseif vim.islist(resolved) then
        for _, item in ipairs(resolved) do
          if type(item) == "table" and type(item.command) == "string" and item.command ~= "" then
            out[#out + 1] = make_candidate({
              kind = "override",
              priority = item.priority or 9800,
              command = item.command,
              cwd = item.cwd or ctx.root,
              reason = item.reason or "Custom resolver candidate",
            })
          end
        end
      end
    end
  end

  return out
end

local function collect_project_candidates(ctx)
  local out = {}
  local root = ctx.root
  local file = ctx.file

  if is_js_like(ctx) and has_file(root, "package.json") then
    local pm = default_pm(root)
    local scripts = read_package_scripts(root)
    local order = is_test_file(file)
        and { "test", "dev", "start", "serve", "preview", "build" }
      or { "dev", "start", "serve", "preview", "build", "test" }
    local base_prio = 9000
    for idx, key in ipairs(order) do
      if scripts[key] then
        out[#out + 1] = make_candidate({
          kind = "project",
          priority = base_prio - idx,
          command = command_for_script(pm, key),
          cwd = root,
          reason = string.format("Node project script '%s' via %s", key, pm),
        })
      end
    end
  end

  if (ctx.filetype == "python" or ctx.ext == "py") and vim.g.smart_run_python_project_runner == true then
    if has_any_file(root, { "pyproject.toml", "uv.lock", "poetry.lock", "requirements.txt" }) then
      local qfile = shellescape(file)
      if has_exec("uv") then
        out[#out + 1] = make_candidate({
          kind = "project",
          priority = 8800,
          command = "uv run " .. qfile,
          cwd = root,
          reason = "Python project via uv",
        })
      end
      if has_exec("poetry") then
        out[#out + 1] = make_candidate({
          kind = "project",
          priority = 8700,
          command = "poetry run python " .. qfile,
          cwd = root,
          reason = "Python project via poetry",
        })
      end
      out[#out + 1] = make_candidate({
        kind = "project",
        priority = 8600,
        command = "python3 " .. qfile,
        cwd = root,
        reason = "Python project via python3",
      })
    end
  end

  if has_file(root, "go.mod") then
    out[#out + 1] = make_candidate({ kind = "project", priority = 8500, command = "go run .", cwd = root, reason = "Go module run" })
    out[#out + 1] = make_candidate({ kind = "project", priority = 8400, command = "go test ./...", cwd = root, reason = "Go module test" })
  end

  if has_file(root, "Cargo.toml") then
    out[#out + 1] = make_candidate({ kind = "project", priority = 8350, command = "cargo run", cwd = root, reason = "Rust cargo run" })
    out[#out + 1] = make_candidate({ kind = "project", priority = 8340, command = "cargo test", cwd = root, reason = "Rust cargo test" })
  end

  if has_file(root, "CMakeLists.txt") then
    out[#out + 1] = make_candidate({ kind = "project", priority = 8300, command = "cmake -S . -B build && cmake --build build", cwd = root, reason = "CMake configure + build" })
  end

  if has_file(root, "Makefile") then
    out[#out + 1] = make_candidate({ kind = "project", priority = 8250, command = "make run", cwd = root, reason = "Make run target" })
    out[#out + 1] = make_candidate({ kind = "project", priority = 8240, command = "make", cwd = root, reason = "Make default target" })
  end

  if has_file(root, "pom.xml") then
    out[#out + 1] = make_candidate({ kind = "project", priority = 8200, command = "mvn compile exec:java", cwd = root, reason = "Maven run" })
  end

  if has_any_file(root, { "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts" }) then
    out[#out + 1] = make_candidate({ kind = "project", priority = 8150, command = "./gradlew run || gradle run", cwd = root, reason = "Gradle run" })
    out[#out + 1] = make_candidate({ kind = "project", priority = 8140, command = "./gradlew build || gradle build", cwd = root, reason = "Gradle build" })
  end

  if has_file(root, "build.sbt") then
    out[#out + 1] = make_candidate({ kind = "project", priority = 8100, command = "sbt run", cwd = root, reason = "sbt run" })
  end

  local has_csproj = #vim.fs.find("*.csproj", { path = root, type = "file", limit = 1 }) > 0
  if has_csproj or #vim.fs.find("*.sln", { path = root, type = "file", limit = 1 }) > 0 then
    out[#out + 1] = make_candidate({ kind = "project", priority = 8050, command = "dotnet run", cwd = root, reason = ".NET run" })
  end

  if has_file(root, "pubspec.yaml") then
    out[#out + 1] = make_candidate({
      kind = "project",
      priority = 8000,
      command = has_exec("flutter") and "flutter run" or "dart run",
      cwd = root,
      reason = "Dart/Flutter run",
    })
  end

  if has_file(root, "mix.exs") then
    out[#out + 1] = make_candidate({ kind = "project", priority = 7950, command = "mix run", cwd = root, reason = "Elixir mix run" })
  end

  if has_file(root, "composer.json") then
    out[#out + 1] = make_candidate({ kind = "project", priority = 7900, command = "composer run || php " .. shellescape(file), cwd = root, reason = "PHP composer project" })
  end

  if has_file(root, "Gemfile") then
    out[#out + 1] = make_candidate({ kind = "project", priority = 7850, command = "bundle exec ruby " .. shellescape(file), cwd = root, reason = "Ruby bundle project" })
  end

  if has_file(root, "flake.nix") then
    out[#out + 1] = make_candidate({ kind = "project", priority = 7800, command = "nix run", cwd = root, reason = "Nix flake run" })
  end

  return out
end

local function compile_and_run(file, compiler, out_name)
  local qfile = shellescape(file)
  local qout = shellescape(out_name)
  return string.format("mkdir -p .nvim-run && %s %s -o %s && %s", compiler, qfile, qout, qout)
end

local function collect_file_candidates(ctx)
  local out = {}
  local file = ctx.file
  local ext = ctx.ext
  local qfile = shellescape(file)
  local out_bin = ".nvim-run/" .. stem(file)

  if ext == "c" then
    local cc = has_exec("clang") and "clang" or "gcc"
    out[#out + 1] = make_candidate({ kind = "file", priority = 7000, command = compile_and_run(file, cc, out_bin), cwd = ctx.root, reason = "Single C file" })
  elseif ext == "cpp" or ext == "cc" or ext == "cxx" then
    local cxx = has_exec("clang++") and "clang++" or "g++"
    out[#out + 1] = make_candidate({ kind = "file", priority = 7000, command = compile_and_run(file, cxx, out_bin), cwd = ctx.root, reason = "Single C++ file" })
  elseif ext == "html" then
    out[#out + 1] = make_candidate({ kind = "file", priority = 7000, command = "python3 -m http.server 8080", cwd = vim.fs.dirname(file), reason = "Serve HTML directory on localhost:8080" })
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

  if by_ext[ext] then
    out[#out + 1] = make_candidate({
      kind = "file",
      priority = 6900,
      command = by_ext[ext],
      cwd = ctx.root,
      reason = "Single-file runner for ." .. ext,
    })
  end

  if vim.fn.executable(file) == 1 then
    out[#out + 1] = make_candidate({ kind = "fallback", priority = 3000, command = qfile, cwd = ctx.root, reason = "Executable file" })
  end

  local first = vim.fn.getline(1)
  if type(first) == "string" and first:sub(1, 2) == "#!" then
    out[#out + 1] = make_candidate({ kind = "fallback", priority = 2900, command = qfile, cwd = ctx.root, reason = "Shebang script" })
  end

  return out
end

local function build_ctx(opts)
  local bufnr = opts.bufnr or 0
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" then
    return nil, "Current buffer has no file path"
  end

  file = vim.fs.normalize(file)
  if not file_exists(file) then
    return nil, "File is not saved on disk"
  end

  return {
    bufnr = bufnr,
    file = file,
    filetype = vim.bo[bufnr].filetype,
    ext = vim.fn.fnamemodify(file, ":e"):lower(),
    root = find_root(file),
  }
end

local function cache_key(ctx, mode)
  local key_parts = {
    tostring(cache_generation),
    mode,
    ctx.file,
    ctx.root,
    tostring(vim.g.smart_run_python_project_runner == true),
    tostring(vim.g.smart_run_command or ""),
  }
  return table.concat(key_parts, "\x1f")
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
  local ctx, err = build_ctx(opts)
  if not ctx then
    return nil, nil, err
  end

  setup_cache_autocmds()
  local key = cache_key(ctx, mode)
  if not opts.no_cache and cache[key] then
    local hit = cache[key]
    return vim.deepcopy(hit.selected), vim.deepcopy(hit.candidates), nil
  end

  local candidates = {}
  local function append(list)
    for _, item in ipairs(list) do
      item.ctx = ctx
      candidates[#candidates + 1] = item
    end
  end

  append(collect_override_candidates(ctx))
  if mode ~= "file" then
    append(collect_project_candidates(ctx))
  end
  if mode ~= "project" then
    append(collect_file_candidates(ctx))
  end

  if #candidates == 0 then
    return nil, nil, "No smart runner rule matched this file/project"
  end

  sort_candidates(candidates)
  local selected = candidates[1]

  cache[key] = {
    selected = vim.deepcopy(selected),
    candidates = vim.deepcopy(candidates),
  }

  return selected, candidates, nil
end

M.last = nil

function M.clear_cache()
  cache_generation = cache_generation + 1
  cache = {}
  vim.notify("SmartRun cache cleared", vim.log.levels.INFO)
end

function M.resolve(opts)
  local selected, _, err = resolve_candidates(opts)
  return selected, err
end

function M.explain(opts)
  local selected, candidates, err = resolve_candidates(opts)
  if not selected then
    vim.notify("SmartRun: " .. err, vim.log.levels.WARN)
    return
  end

  local lines = {
    "Smart Run Explain",
    string.rep("=", 17),
    "",
    "selected: " .. selected.label,
    "root: " .. selected.cwd,
    "file: " .. selected.ctx.file,
    "",
    "top candidates:",
  }

  local limit = math.min(#candidates, 8)
  for i = 1, limit do
    lines[#lines + 1] = string.format("%d. %s", i, candidates[i].label)
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "SmartRun" })
end

function M.run(opts)
  local selected, _, err = resolve_candidates(opts)
  if not selected then
    vim.notify("SmartRun: " .. err, vim.log.levels.ERROR)
    return
  end

  M.last = selected
  vim.notify("SmartRun: " .. selected.reason, vim.log.levels.INFO)
  run_in_terminal(selected.command, selected.cwd)
end

function M.pick(opts)
  local _, candidates, err = resolve_candidates(opts)
  if not candidates then
    vim.notify("SmartRun: " .. err, vim.log.levels.WARN)
    return
  end

  vim.ui.select(candidates, {
    prompt = "SmartRun candidates",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    M.last = choice
    run_in_terminal(choice.command, choice.cwd)
  end)
end

function M.run_last()
  if not M.last then
    vim.notify("SmartRun: nothing to rerun yet", vim.log.levels.WARN)
    return
  end
  run_in_terminal(M.last.command, M.last.cwd)
end

local function maybe_set_default_globals()
  if vim.g.smart_run_focus_terminal == nil then
    vim.g.smart_run_focus_terminal = false
  end
  if vim.g.smart_run_python_project_runner == nil then
    vim.g.smart_run_python_project_runner = false
  end
end

local function register_commands()
  local specs = {
    { "SmartRun", function() M.run({ mode = "auto" }) end, "Smart run file/project" },
    { "SmartRunFile", function() M.run({ mode = "file" }) end, "Smart run (file mode)" },
    { "SmartRunProject", function() M.run({ mode = "project" }) end, "Smart run (project mode)" },
    { "SmartRunExplain", function() M.explain({ mode = "auto" }) end, "Explain smart run decision" },
    { "SmartRunLast", M.run_last, "Rerun last smart run command" },
    { "SmartRunPick", function() M.pick({ mode = "auto" }) end, "Pick from smart run candidates" },
    { "SmartRunCacheClear", M.clear_cache, "Clear smart run cache" },
  }

  for _, spec in ipairs(specs) do
    pcall(vim.api.nvim_del_user_command, spec[1])
    vim.api.nvim_create_user_command(spec[1], spec[2], { desc = spec[3] })
  end
end

local function register_keymaps()
  local km = M.config.keymaps

  if km.run then
    vim.keymap.set("n", km.run, function()
      M.run({ mode = "auto" })
    end, { desc = "Smart run" })
  end
  if km.pick then
    vim.keymap.set("n", km.pick, function()
      M.pick({ mode = "auto" })
    end, { desc = "Smart run (pick)" })
  end
  if km.last then
    vim.keymap.set("n", km.last, M.run_last, { desc = "Smart run last" })
  end
  if km.legacy then
    vim.keymap.set("n", km.legacy, function()
      if vim.fn.exists(":RunFile") == 2 then
        vim.cmd.RunFile()
      else
        vim.notify("RunFile command is unavailable", vim.log.levels.WARN)
      end
    end, { desc = "Run file (legacy)" })
  end
end

function M.setup(opts)
  if setup_done then
    return M
  end
  setup_done = true

  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  maybe_set_default_globals()

  if M.config.create_commands then
    register_commands()
  end
  if M.config.create_keymaps then
    register_keymaps()
  end

  return M
end

return M

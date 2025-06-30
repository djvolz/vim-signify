" vim: et sw=2 sts=2 fdm=marker

scriptencoding utf-8

" #detect {{{1
function! sy#generic#detect(bufnr) abort
  call sy#verbose('sy#generic#detect()', 'generic')
  
  if !exists('g:signify_vcs_rules') || empty(g:signify_vcs_rules)
    call sy#verbose('No generic VCS rules defined', 'generic')
    return
  endif
  
  let sy = getbufvar(a:bufnr, 'sy')
  if empty(sy)
    call sy#verbose('No sy object found for buffer', 'generic')
    return
  endif
  
  let file_dir = sy.info.dir
  
  " Check each rule to see if it matches
  for [rule_name, rule] in items(g:signify_vcs_rules)
    if !get(rule, 'enabled', 1)
      continue
    endif
    
    if s:rule_matches(file_dir, rule)
      call sy#verbose('Generic VCS rule matched: ' . rule_name, 'generic')
      let sy.detecting += 1
      let g:signify_detecting += 1
      call sy#generic#get_diff(a:bufnr, rule_name, rule, function('sy#sign#set_signs'))
    endif
  endfor
endfunction

" s:rule_matches {{{1
function! s:rule_matches(file_dir, rule) abort
  if !has_key(a:rule, 'detect')
    return 0
  endif
  
  let detect = a:rule.detect
  
  " Check for required directories
  if has_key(detect, 'dirs')
    for dir in detect.dirs
      let check_path = a:file_dir . '/' . dir
      if !isdirectory(check_path)
        return 0
      endif
    endfor
  endif
  
  " Check for required files
  if has_key(detect, 'files')
    for file in detect.files
      let check_path = a:file_dir . '/' . file
      if !filereadable(check_path)
        return 0
      endif
    endfor
  endif
  
  " Check command-based detection
  if has_key(detect, 'command')
    let [cwd, chdir] = sy#util#chdir()
    try
      execute chdir fnameescape(a:file_dir)
      let result = system(detect.command)
      if v:shell_error != 0
        return 0
      endif
    finally
      execute chdir fnameescape(cwd)
    endtry
  endif
  
  return 1
endfunction

" #get_diff {{{1
function! sy#generic#get_diff(bufnr, rule_name, rule, func) abort
  call sy#verbose('sy#generic#get_diff()', 'generic:' . a:rule_name)
  
  " Validate rule
  if !s:validate_rule(a:rule)
    call sy#verbose('Invalid rule configuration: ' . a:rule_name, 'generic')
    return
  endif
  
  let sy = getbufvar(a:bufnr, 'sy')
  let options = {
        \ 'stdoutbuf': [''],
        \ 'vcs': 'generic:' . a:rule_name,
        \ 'bufnr': a:bufnr,
        \ 'rule': a:rule,
        \ 'rule_name': a:rule_name,
        \ 'func': a:func,
        \ 'difftool': 'generic'
        \ }
  
  let diff_method = get(a:rule, 'diff_method', 'file_compare')
  
  if diff_method ==# 'file_compare'
    call s:get_diff_file_compare(options)
  elseif diff_method ==# 'command'
    call s:get_diff_command(options)
  elseif diff_method ==# 'script'
    call s:get_diff_script(options)
  else
    call sy#verbose('Unknown diff method: ' . diff_method, 'generic')
    call s:handle_generic_diff(options, 2)  " Error exit code
  endif
endfunction

" s:get_diff_file_compare {{{1
function! s:get_diff_file_compare(options) abort
  let sy = getbufvar(a:options.bufnr, 'sy')
  let rule = a:options.rule
  
  " Get base and modified file paths
  let base_path = s:substitute_placeholders(get(rule, 'base_path', '%f'), sy)
  let modified_path = s:substitute_placeholders(get(rule, 'modified_path', '%f'), sy)
  
  " Make paths absolute if they're relative
  if base_path !~# '^/'
    let base_path = sy.info.dir . '/' . base_path
  endif
  if modified_path !~# '^/'
    let modified_path = sy.info.dir . '/' . modified_path
  endif
  
  call sy#verbose('Comparing: ' . base_path . ' vs ' . modified_path, 'generic')
  
  " Check if base file exists
  if !filereadable(base_path)
    call sy#verbose('Base file not found: ' . base_path, 'generic')
    call s:handle_generic_diff(a:options, 2)  " Error
    return
  endif
  
  " For modified files, use current buffer content if it's the same as modified_path
  let use_buffer = (resolve(fnamemodify(bufname(a:options.bufnr), ':p')) ==# resolve(fnamemodify(modified_path, ':p')))
  
  if use_buffer && getbufvar(a:options.bufnr, '&modified')
    " Buffer is modified, create temp file with current content
    let temp_file = tempname()
    call s:write_buffer_to_file(a:options.bufnr, temp_file)
    let modified_path = temp_file
    let a:options.tempfiles = [temp_file]
  elseif !filereadable(modified_path)
    call sy#verbose('Modified file not found: ' . modified_path, 'generic')
    call s:handle_generic_diff(a:options, 2)  " Error
    return
  endif
  
  " Generate unified diff
  let difftool = sy#util#escape(get(g:, 'signify_difftool', 'diff'))
  let devnull = has('win32') || has('win64') ? 'NUL' : '/dev/null'
  let cmd = printf('%s -U0 %s %s 2>%s', difftool, shellescape(base_path), shellescape(modified_path), devnull)
  
  call sy#verbose('Diff command: ' . cmd, 'generic')
  
  " Execute diff
  let [cwd, chdir] = sy#util#chdir()
  try
    execute chdir fnameescape(sy.info.dir)
    let diff_output = system(cmd)
    let exitval = v:shell_error
  finally
    execute chdir fnameescape(cwd)
  endtry
  
  let a:options.stdoutbuf = split(diff_output, '\n')
  call s:handle_generic_diff(a:options, exitval)
endfunction

" s:get_diff_command {{{1
function! s:get_diff_command(options) abort
  let sy = getbufvar(a:options.bufnr, 'sy')
  let rule = a:options.rule
  
  if !has_key(rule, 'diff_cmd')
    call sy#verbose('No diff_cmd specified for command method', 'generic')
    call s:handle_generic_diff(a:options, 2)
    return
  endif
  
  let cmd = s:substitute_placeholders(rule.diff_cmd, sy)
  
  call sy#verbose('Generic diff command: ' . cmd, 'generic')
  
  " Execute command
  let [cwd, chdir] = sy#util#chdir()
  try
    execute chdir fnameescape(sy.info.dir)
    let diff_output = system(cmd)
    let exitval = v:shell_error
  finally
    execute chdir fnameescape(cwd)
  endtry
  
  let a:options.stdoutbuf = split(diff_output, '\n')
  call s:handle_generic_diff(a:options, exitval)
endfunction

" s:get_diff_script {{{1
function! s:get_diff_script(options) abort
  let rule = a:options.rule
  
  if !has_key(rule, 'script_path') || !executable(rule.script_path)
    call sy#verbose('Script not found or not executable: ' . get(rule, 'script_path', 'undefined'), 'generic')
    call s:handle_generic_diff(a:options, 2)
    return
  endif
  
  let sy = getbufvar(a:options.bufnr, 'sy')
  let cmd = s:substitute_placeholders(rule.script_path . ' %f', sy)
  
  call sy#verbose('Generic script command: ' . cmd, 'generic')
  
  " Execute script
  let [cwd, chdir] = sy#util#chdir()
  try
    execute chdir fnameescape(sy.info.dir)
    let diff_output = system(cmd)
    let exitval = v:shell_error
  finally
    execute chdir fnameescape(cwd)
  endtry
  
  let a:options.stdoutbuf = split(diff_output, '\n')
  call s:handle_generic_diff(a:options, exitval)
endfunction

" s:handle_generic_diff {{{1
function! s:handle_generic_diff(options, exitval) abort
  call sy#verbose('s:handle_generic_diff()', 'generic:' . a:options.rule_name)
  
  " Clean up temp files
  if has_key(a:options, 'tempfiles')
    for f in a:options.tempfiles
      call delete(f)
    endfor
  endif
  
  let sy = getbufvar(a:options.bufnr, 'sy')
  if empty(sy)
    call sy#verbose('No b:sy found for buffer', 'generic')
    return
  elseif !empty(sy.updated_by) && sy.updated_by != a:options.vcs
    call sy#verbose('Signs already updated by ' . sy.updated_by, 'generic')
    return
  elseif empty(sy.vcs)
    let g:signify_detecting -= 1
    let sy.detecting -= 1
  endif
  
  " Handle encoding conversion
  let fenc = getbufvar(a:options.bufnr, '&fenc')
  let enc = getbufvar(a:options.bufnr, '&enc')
  if (fenc != enc) && has('iconv')
    call map(a:options.stdoutbuf, printf('iconv(v:val, "%s", "%s")', fenc, enc))
  endif
  
  " Check diff result
  let rule = a:options.rule
  let exit_codes = get(rule, 'exit_codes', {'success': 0, 'changes': 1, 'error': 2})
  
  let found_diff = 0
  let diff = []
  
  if a:exitval == exit_codes.success || a:exitval == get(exit_codes, 'changes', 1)
    if !empty(a:options.stdoutbuf) && a:options.stdoutbuf != ['']
      let found_diff = 1
      let diff = a:options.stdoutbuf
    elseif a:exitval == get(exit_codes, 'changes', 1)
      " Changes detected but no diff output - this can happen with some tools
      let found_diff = 1
      let diff = []
    endif
  endif
  
  if found_diff
    if index(sy.vcs, a:options.vcs) == -1
      let sy.vcs += [a:options.vcs]
    endif
    call a:options.func(sy, a:options.vcs, diff)
  else
    call sy#verbose('No valid diff found for generic VCS: ' . a:options.rule_name, 'generic')
  endif
  
  call setbufvar(a:options.bufnr, 'sy_job_id_' . a:options.vcs, 0)
endfunction

" s:substitute_placeholders {{{1
function! s:substitute_placeholders(text, sy) abort
  let result = a:text
  let result = substitute(result, '%f', a:sy.info.file, 'g')
  let result = substitute(result, '%p', a:sy.info.path, 'g')
  let result = substitute(result, '%d', sy#util#escape(get(g:, 'signify_difftool', 'diff')), 'g')
  let result = substitute(result, '%n', (has('win32') || has('win64') ? 'NUL' : '/dev/null'), 'g')
  return result
endfunction

" s:write_buffer_to_file {{{1
function! s:write_buffer_to_file(bufnr, filepath) abort
  let bufcontents = getbufline(a:bufnr, 1, '$')
  
  if bufcontents == [''] && line2byte(1) == -1
    call writefile([], a:filepath)
    return
  endif
  
  if getbufvar(a:bufnr, '&fileformat') ==# 'dos'
    call map(bufcontents, 'v:val."\r"')
  endif
  
  let fenc = getbufvar(a:bufnr, '&fileencoding')
  let enc = getbufvar(a:bufnr, '&encoding')
  if fenc !=# enc
    call map(bufcontents, 'iconv(v:val, "'.enc.'", "'.fenc.'")')
  endif
  
  if getbufvar(a:bufnr, '&bomb')
    let bufcontents[0] = '﻿' . bufcontents[0]
  endif
  
  call writefile(bufcontents, a:filepath)
endfunction

" s:validate_rule {{{1
function! s:validate_rule(rule) abort
  " Basic validation - rule must have detect configuration
  if !has_key(a:rule, 'detect')
    return 0
  endif
  
  let detect = a:rule.detect
  
  " Must have at least one detection method
  if !has_key(detect, 'dirs') && !has_key(detect, 'files') && !has_key(detect, 'command')
    return 0
  endif
  
  " Validate diff method requirements
  let diff_method = get(a:rule, 'diff_method', 'file_compare')
  
  if diff_method ==# 'file_compare'
    " file_compare needs base_path
    if !has_key(a:rule, 'base_path')
      return 0
    endif
  elseif diff_method ==# 'command'
    " command needs diff_cmd
    if !has_key(a:rule, 'diff_cmd')
      return 0
    endif
  elseif diff_method ==# 'script'
    " script needs script_path
    if !has_key(a:rule, 'script_path')
      return 0
    endif
  else
    return 0
  endif
  
  return 1
endfunction

" #validate_rules {{{1
function! sy#generic#validate_rules() abort
  if !exists('g:signify_vcs_rules')
    return []
  endif
  
  let errors = []
  for [rule_name, rule] in items(g:signify_vcs_rules)
    if !s:validate_rule(rule)
      call add(errors, 'Invalid rule: ' . rule_name)
    endif
  endfor
  
  return errors
endfunction

" #debug_rules {{{1
function! sy#generic#debug_rules() abort
  if !exists('g:signify_vcs_rules') || empty(g:signify_vcs_rules)
    echomsg 'signify: No generic VCS rules defined'
    return
  endif
  
  echohl Statement
  echo 'Generic VCS Rules'
  echo '================='
  echohl NONE
  
  for [rule_name, rule] in items(g:signify_vcs_rules)
    echo printf('Rule: %s', rule_name)
    echo printf('  Enabled: %s', get(rule, 'enabled', 1) ? 'Yes' : 'No')
    echo printf('  Diff method: %s', get(rule, 'diff_method', 'file_compare'))
    echo printf('  Priority: %s', get(rule, 'priority', 50))
    
    if has_key(rule, 'detect')
      echo '  Detection:'
      let detect = rule.detect
      if has_key(detect, 'dirs')
        echo printf('    Directories: %s', string(detect.dirs))
      endif
      if has_key(detect, 'files')
        echo printf('    Files: %s', string(detect.files))
      endif
      if has_key(detect, 'command')
        echo printf('    Command: %s', detect.command)
      endif
    endif
    
    if has_key(rule, 'base_path')
      echo printf('  Base path: %s', rule.base_path)
    endif
    if has_key(rule, 'modified_path')
      echo printf('  Modified path: %s', rule.modified_path)
    endif
    if has_key(rule, 'diff_cmd')
      echo printf('  Diff command: %s', rule.diff_cmd)
    endif
    if has_key(rule, 'script_path')
      echo printf('  Script path: %s', rule.script_path)
    endif
    
    echo ''
  endfor
  
  let errors = sy#generic#validate_rules()
  if !empty(errors)
    echohl ErrorMsg
    echo 'Validation Errors:'
    for error in errors
      echo '  ' . error
    endfor
    echohl NONE
  else
    echohl DiffAdd
    echo 'All rules are valid'
    echohl NONE
  endif
endfunction
" Test configuration for ABC VCS system
let g:signify_vcs_rules = {
  \ 'abc': {
  \   'detect': { 'dirs': ['.abc'] },
  \   'diff_method': 'file_compare',
  \   'base_path': '.abc/%f',
  \   'modified_path': '%f',
  \   'priority': 50
  \ }
  \ }

" Enable verbose output for debugging
set verbose=1

" Start signify for the current buffer
call sy#start()
" Simple test for ABC VCS detection
source autoload/sy/util.vim
source autoload/sy/generic.vim

" Configure ABC VCS rule
let g:signify_vcs_rules = {
  \ 'abc': {
  \   'detect': { 'dirs': ['.abc'] },
  \   'diff_method': 'file_compare',
  \   'base_path': '.abc/%f',
  \   'modified_path': '%f',
  \   'priority': 50
  \ }
  \ }

" Test rule validation
let errors = sy#generic#validate_rules()
echo "Validation errors: " . string(errors)

" Test rule detection in test directory
cd test-abc-vcs
let file_dir = getcwd()
echo "Testing detection in: " . file_dir

" Manually test rule matching
let rule = g:signify_vcs_rules['abc']
let detect = rule.detect

echo "Looking for directory: " . file_dir . '/' . detect.dirs[0]
if isdirectory(file_dir . '/' . detect.dirs[0])
  echo "✓ Detection directory found"
else
  echo "✗ Detection directory not found"
endif

" Test file paths
let base_file = file_dir . '/.abc/test.py'
let modified_file = file_dir . '/test.py'

echo "Base file: " . base_file
echo "Modified file: " . modified_file
echo "Base exists: " . filereadable(base_file)
echo "Modified exists: " . filereadable(modified_file)
" Test script for ABC VCS functionality
" Usage: vim -S test_abc_vcs.vim

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

" Enable verbose output for debugging
set verbose=1

echo "=== Testing ABC VCS Support ==="
echo ""

" Test 1: Validate rules
echo "Test 1: Validating rules..."
let errors = sy#generic#validate_rules()
if empty(errors)
  echo "✓ Rules are valid"
else
  echo "✗ Rule validation failed:"
  for error in errors
    echo "  " . error
  endfor
endif
echo ""

" Test 2: Debug rules
echo "Test 2: Debug rules output:"
call sy#generic#debug_rules()
echo ""

" Test 3: Test detection in ABC directory
echo "Test 3: Testing detection in ABC directory..."
cd test-abc-vcs
echo "Current directory: " . getcwd()

" Open the test file
edit test.py

" Initialize sy for this buffer  
call sy#start()

" Give it some time to detect
sleep 100m

" Check if sy was initialized
let sy = getbufvar(bufnr(''), 'sy')
if !empty(sy)
  echo "✓ Sy object created for buffer"
  echo "  VCS detected: " . string(sy.vcs)
  echo "  Stats: " . string(sy.stats)
  echo "  Hunks: " . len(sy.hunks)
else
  echo "✗ Sy object not created"
endif

echo ""
echo "=== Test Complete ==="

" Don't exit automatically so user can inspect
echo "Press any key to continue..."
call getchar()
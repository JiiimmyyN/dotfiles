noremap <C-A-F5> :so ~/.vsvimrc
"set background=dark
let mapleader = ","

"Lets kick the arrow key habit!
noremap <Up> <Nop>
noremap <Down> <Nop>
noremap <Left> <Nop>
noremap <Right> <Nop>

"show quickfix menu 
nnoremap <bs> :vsc ReSharper_AltEnter<cr>
xnoremap <bs> :vsc ReSharper_AltEnter<cr>
" Rename using Reshaper
nnoremap <leader>rr :vsc ReSharper_Rename<CR>
xnoremap <leader>rr :vsc ReSharper_Rename<CR>

"Visual studio specefic commands
nnoremap <leader>td :vsc Edit.GoToDefinition<CR>
nnoremap <leader>fr :vsc Edit.FindAllReferences<CR>
" Go to next/previous error.
nnoremap <leader>nerr :vsc Edit.GoToNextLocation<CR>
nnoremap <leader>perr :vsc Edit.GoToPrevLocation<CR>
nnoremap gn :action GotoNextError<CR>
nnoremap gp :action GotoPreviousError<CR>
"
map <leader>/ I//<ESC>j


"B and E go to start and end of file, $ and ^
nnoremap B ^
nnoremap E $
nnoremap $ <nop>
nnoremap ^ <nop>

"Toggle current fold with space
nnoremap <Space> za

"""""" vim-plug
call plug#begin()

Plug 'vimwiki/vimwiki'

call plug#end()

"""""" Neobundle installation """""""
" Note: Skip initialization for vim-tiny or vim-small.
if 0 | endif

if &compatible
  set nocompatible               " Be iMproved
endif

" Required:
set runtimepath+=~/.vim/bundle/neobundle.vim/

" Required:
call neobundle#begin(expand('~/.vim/bundle/'))

" Let NeoBundle manage NeoBundle
" Required:
NeoBundleFetch 'Shougo/neobundle.vim'

" My Bundles here:
" Refer to |:NeoBundle-examples|.
" Note: You don't set neobundle setting in .gvimrc!
NeoBundle 'aserebryakov/vim-todo-lists'

call neobundle#end()

" Required:
filetype plugin indent on

" If there are uninstalled bundles found on startup,
" this will conveniently prompt you to install them.

NeoBundleCheck


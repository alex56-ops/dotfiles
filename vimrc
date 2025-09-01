" Copy & Paste Verbesserungen
set paste
set clipboard=unnamed
set mouse=a

" Terminal und Encoding
set encoding=utf-8
set t_Co=256

" Allgemeine Verbesserungen
set number
set autoindent
set tabstop=4
set shiftwidth=4
set expandtab

" Bracketed paste support
if &term =~ "screen.*" || &term =~ "tmux.*"
    let &t_BE = "\e[?2004h"
    let &t_BD = "\e[?2004l"
    exec "set t_PS=\e[200~"
    exec "set t_PE=\e[201~"
endif

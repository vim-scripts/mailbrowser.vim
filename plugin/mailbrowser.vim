" File: mailbrowser.vim
" Author: Mark Waggoner (mark@wagnell.com)
" Last Change: 2001 Jul 25
" Version: 1.1
"-----------------------------------------------------------------------------
" This plugin allows one to view a mail collection similar to the way one
" would view it in a mailer.
"
" Normally, this file will reside in the plugins directory and be
" automatically sourced.  If not, you must manually source this file
" using :source mailbrowser.vim
"
" :Mail <filename>
"   will bring up an index of the mail contained in the specified file
" :Mail
"   will bring up an index of the mail contained in the file specified by the
"   $MAIL environment variable
" :SMail
"   will open a new window and then do what :Mail would have done
"
"-----------------------------------------------------------------------------
"=============================================================================

" Has this already been loaded?
" Disabled for debugging
"if exists("loaded_mailbrowswer")
"  finish
"endif
"let loaded_mailbrowswer=1


"---
" Default settings for global configuration variables

" Format for the date
"if !exists("g:emailindexDateFormat")
"  let g:emailindexDateFormat="%d %b %Y %H:%M"
"endif

" Field to sort by
"if !exists("g:emailindexSortBy")
"  let g:emailindexSortBy='arrival'
"endif


" Directories to look in for mail folders
if !exists("g:mailbrowserMailPath")
  let g:mailbrowserMailPath = $HOME . "/Mail"
endif

" How many characters to display in the "From" field
if !exists("g:mailbrowserFromLength")
  let g:mailbrowserFromLength = 25
endif

" Which headers do you want to see or NOT see
"
if !exists("g:mailbrowserShowHeaders") 
  let g:mailbrowserShowHeaders = '^\(Subject:\|Date:\|From:\)'
endif
if !exists("g:mailbrowserHideHeaders")
  let g:mailbrowserHideHeaders = ""
endif


" characters that must be escaped for a regular expression
let s:escregexp = '/*^$.~\'

"---
" This function starts the email browser on the filename sent as the argument.
" If no argument is given, it will start on the $MAIL environment variable.
" If $MAIL does not exist, it doesn't do anything but print an error message
"
" Three buffers are created:
"   The raw mail file
"   A buffer for the index
"   A buffer for displaying a single mail message
"
" These three variables are set in each of the three buffers to point to the
" other buffers:
"   b:maildata
"   b:mailindex
"   b:mailview
"
function! s:BrowseEmail(newwindow,filename)

  " Figure out which file to look at
  if a:filename == ""
    if exists('$MAIL')
      let filename = $MAIL
    else
      echomsg 'No mail file specified, and $MAIL is undefined - unable to start'
      return
    endif
  else
    let filename = a:filename
  endif

  " Can't find the file directly, try looking for it in the path supplied
  if !filereadable(filename)
    let filename = globpath(g:mailbrowserMailPath,filename)
    " Only take the first one found
    let filename = substitute(filename,"\<Nul>.*$",'','')
    " Can't find anything - then abort
    if !filereadable(filename)
      echomsg 'File' filename 'does not exist!'
      return
    endif
  endif

  " Get the name of the mail buffer
  let filename = fnamemodify(filename,":p")
  " Construct names for the index buffer and the message view buffer
  let maildata = filename
  let mailindex = fnamemodify(maildata,":t") . "-index"
  let mailview  = fnamemodify(maildata,":t") . "-message"
 
  " Is the index already in a window somewhere?  If so, move to that window
  if bufwinnr(mailindex) > 0
    exec bufwinnr(mailindex) . 'wincmd w'
  else
    " If index isn't already in a window and the current window has modified
    " data, create a new window
    if &modified || a:newwindow
      new
    endif
    " Does index buffer already exist?  If so, edit it, if not, set the name
    " of the current buffer to be the index
    if bufexists(mailindex)
      exec "silent e" mailindex
    else
      exec "silent file" mailindex
    endif
    call s:SetScratchWindow()
  endif

  " Save the names of the files in buffer local variables
  let b:maildata  = maildata
  let b:mailindex = mailindex
  let b:mailview  = mailview
 
  " Set up keyboard commands for the index window
  nnoremap <silent> <buffer> <2-leftmouse>  :call <SID>OpenMail('new')<cr>
  nnoremap <silent> <buffer> o  :call <SID>OpenMail('new')<cr>
  nnoremap <silent> <buffer> s  :call <SID>SortSelect()<cr>
  nnoremap <silent> <buffer> r  :call <SID>SortReverse()<cr>
  nnoremap <silent> <buffer> <cr> :call <SID>OpenMail('e')<cr>
  nnoremap <silent> <buffer> u  :call <SID>BuildIndex()<cr>

  " syntax highlighting
  if hlexists("mailindexdata")
    syn clear mailindexdata
  endif
  if hlexists("mailindexline")
    syn clear mailindexline
  endif
  if hlexists("maildate")
    syn clear maildate
  endif
  if hlexists("mailfrom")
    syn clear mailfrom
  endif
  if hlexists("mailflag")
    syn clear mailflag
  endif
  syn match mailindexline '^[^"].*' contains=CONTAINED
  let datecolumn=3
  exec 'syn match mailflag ".\%>1v\%<3v" contained'
  exec 'syn match maildate ".\%>' . datecolumn . 'v\%<' . (datecolumn+16) .'v" contained'
  exec 'syn match mailfrom ".\%>' . (datecolumn+16) . 'v\%<' . (datecolumn+17+g:mailbrowserFromLength) . 'v" contained'
  exec 'syn match mailsubject ".\%>' . (datecolumn+17+g:mailbrowserFromLength) . 'v" contained'
  syn match mailindexdata "«.\+$" contained
  hi link mailindexdata   Ignore
  hi link maildate        Identifier
  hi link mailfrom        Statement
  hi link mailsubject     Type
  hi link mailflag        Constant

  " highlight the displayed message
  highlight clear DisplayedMessage
  highlight DisplayedMessage ctermfg=white ctermbg=darkred guibg=darkred  guifg=white term=bold cterm=bold

  " Variables indicating sort order of index
  let b:sortdirection=1
  let b:sortdirlabel = ""
  let b:sorttype = ""
  let b:sortby = "file order"


  " Open the mail data file and make it unmodifiable to protect it
  exec "silent new" maildata
  setlocal nomodifiable
  setlocal noswapfile
  setlocal bufhidden=hide
  setlocal nowrap
  setlocal autoread
  let b:maildata  = maildata
  let b:mailindex = mailindex
  let b:mailview  = mailview
  hide

  " Create a buffer for viewing mail messages
  exec "silent new" mailview
  call s:SetScratchWindow()
  let b:maildata  = maildata
  let b:mailindex = mailindex
  let b:mailview  = mailview
  let b:showheaders=g:mailbrowserShowHeaders
  let b:hideheaders=g:mailbrowserHideHeaders
  setlocal filetype=mail
  nnoremap <silent> <buffer> i  :call <SID>GotoWindow(b:mailindex,'e')<cr>
  nnoremap <silent> <buffer> a  :call <SID>ToggleHeaders()<cr>
  hide

  " Should be back in the index window now

  " Create the index
  call s:BuildIndex()

endfunction

"--
" Create the index window using the headers from the mail data window
" Should be called with cursor in the index window
"
function! s:BuildIndex()
  " call s:GotoWindow(b:mailindex,'new')
  setlocal modifiable
  " Empty the window
  1,$d
  " Add header
  let @a = "\"Mail from " . b:maildata . " sorted by " . b:sortby . "\n\"="
  put a

  " Make a padding string to use in GetHeaders()
  let s:frompadding = "               "
  while strlen(s:frompadding) < g:mailbrowserFromLength
      let s:frompadding = s:frompadding . "               "
  endwhile

  " Go to the email window
  call s:GotoWindow(b:maildata,'new')
  silent checktime
  let ic = &l:ignorecase
  let &l:ignorecase=0

  " Start at the beginning and find all the headers
  0
  while s:GetHeaders()
      " go back to index
      wincmd p
      $put
      " return to data
      wincmd p
  endwhile
  " Hide the data window
  let &l:ignorecase=ic
  hide

  " Should be in the index window
  0d
  setlocal nomodifiable
endfunction

"--
" Should be called with cursor in a line that starts a mail message
" ^From sender date
"
" Save the starting line number
" get received time from the From line
" Then look for Subject:, From:, and start of next message.  Save the last
" line number of the message
"
function! s:GetHeaders()
    let start = line(".")
    let l = getline(".")
    if l !~ '^From\s\+\(\S\+\)\s\+\(.*\)'
        return 0
    endif
    let from = substitute(l,'^From\s\+','','')
    let date = substitute(from,'\S\+\s\+','','')
    let from = substitute(from,'\(\S\+\).*','\1','')
    let date = strpart(date,0,11) . strpart(date,20,4)
    let subject = '----------'
    let flag = " "

    " Try to find the headers we are interested in or blank line,
    " indicating end of headers
    while search('\v^((From\:)|(Subject\:)|(Status\:)|(\n))','W')
        let l = getline(".")

        " End of headers?
        if l =~ '^$'
            let headerend = line(".")
            break
        endif

        if l =~ '^From:'
            let from = substitute(l,'^From:\s\+','','')
            let from = substitute(from,'\s*<[^>]\+>\s*','','')
            let from = substitute(from,'"','','g')
            continue
        endif

        if l =~ '^Subject:'
            let subject= substitute(l,'^Subject:\s\+','','')
            continue
        endif

        if l =~ '^Status:'
            let status = substitute(l,'^Status:\s\+','','')
            if status !~# 'R'
                let flag="N"
            endif
            continue
        endif

        "Shouldn't get here!
        echoerr "Error Extracting Mail Headers"
        return 0

    endwhile

    if !search('\v^From ','W')
        $
    else
        -1
    endif

    let end=line(".")
    let from = strpart(from . s:frompadding,0,g:mailbrowserFromLength)
    let @" = flag . " " . date . " " . from . " " . subject . ' «' . start . ',' . headerend . ',' . end 
    +1
    return 1
endfunction

"--
" Close a selected window
"
function! s:CloseWindow(name)
  " If buffer exists, get it in a window
  if bufexists(a:name)
    " Already in a window? Then go there
    if bufwinnr(a:name) >= 0
        exec bufwinnr(a:name) . 'wincmd w'
        close
    endif
  endif
endfunction

"--
" Go to a selected window
"
function! s:GotoWindow(name,new)

  " If buffer exists, get it in a window
  if !bufexists(a:name)
    echoerr "Couldn't find buffer for" a:name
    return
    " buffer for index doesn't exist, so open a new window for it
"   exec a:new
"   exec "silent file" a:name
"   call s:SetScratchWindow()
  endif

  " Already in a window? Then go there
  if bufwinnr(a:name) >= 0
      exec bufwinnr(a:name) . 'wincmd w'
  " Not in a window, then open a window to look at it
  else
      exec "silent " a:new a:name
  endif

endfunction

function! s:SetScratchWindow()
  " Turn off the swapfile, set the buffer type so that it won't get
  " written, and so that it will get hidden 
  setlocal noswapfile
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal nowrap
  setlocal nomodifiable
  setlocal filetype=
endfunction


"---
"
"
function! s:OpenMail(new)
    " Get the start/end info from the current index line
    let location = substitute(getline("."),'\v^.*«','','')
    let start     = substitute(location,',.*','','')
    let location  = substitute(location,'^[^,]\+,','','')
    let headerend = substitute(location,',.*','','')
    let location  = substitute(location,'^[^,]\+,','','')
    let end = location

    if hlexists("DisplayedMessage")
      syn clear DisplayedMessage
    endif

    " Not sure I like this
    "exec 'syn match DisplayedMessage ".\%' . line(".") . 'l"'

    call s:GetMailMsg(start,end,a:new)
endfunction

function! s:GetMailMsg(start,end,new)
    call s:GotoWindow(b:maildata,'new')
    exec "silent " . a:start . "," a:end . "y a"
    call s:CloseWindow(b:maildata)
    call s:GotoWindow(b:mailview,a:new)
    setlocal modifiable
    let b:start = a:start
    let b:end = a:end
    silent 1,$d
    silent put! a
    call s:FilterHeaders()
    nohlsearch
    setlocal nomodifiable
endfunction

"--
" Extract headers that we want to display
"
function! s:FilterHeaders()
    silent 1,/^$/-1g/^/call s:FilterHeader()
endfunction

function! s:FilterHeader()
    let l=getline(".")
    if (b:hideheaders != "") && (l =~ b:hideheaders)
        silent delete
    endif

    if (b:showheaders != "") && (l !~ b:showheaders)
        silent delete
    endif
endfunction

function! s:ToggleHeaders()
    " Switch between full and partial headers
    if b:showheaders != "" || b:hideheaders != ""
        let b:showheaders = ""
        let b:hideheaders = ""
    else
        let b:showheaders = g:mailbrowserShowHeaders
        let b:hideheaders = g:mailbrowserHideHeaders
    endif
    " Now re-read the message from the main buffer
    call s:GetMailMsg(b:start,b:end,'e')
endfunction

"---
" Compare dates
"
function! s:DateCmp(line1,line2,direction)
    return 0
endfunction

"---
" Compare From
"
function! s:FromCmp(line1,line2,direction)
    return 0
endfunction

"---
" Compare Subject
"
function! s:SubjectCmp(line1,line2,direction)
    return 0
endfunction

"---
" General string comparison function
"
function! s:StrCmp(line1, line2, direction)
  if a:line1 < a:line2
    return -a:direction
  elseif a:line1 > a:line2
    return a:direction
  else
    return 0
  endif
endfunction

"---
" Sort lines.  SortR() is called recursively.
"
function! s:SortR(start, end, cmp, direction)

  " Bottom of the recursion if start reaches end
  if a:start >= a:end
    return
  endif
  "
  let partition = a:start - 1
  let middle = partition
  let partStr = getline((a:start + a:end) / 2)
  let i = a:start
  while (i <= a:end)
    let str = getline(i)
    exec "let result = " . a:cmp . "(str, partStr, " . a:direction . ")"
    if result <= 0
      " Need to put it before the partition.  Swap lines i and partition.
      let partition = partition + 1
      if result == 0
        let middle = partition
      endif
      if i != partition
        let str2 = getline(partition)
        call setline(i, str2)
        call setline(partition, str)
      endif
    endif
    let i = i + 1
  endwhile

  " Now we have a pointer to the "middle" element, as far as partitioning
  " goes, which could be anywhere before the partition.  Make sure it is at
  " the end of the partition.
  if middle != partition
    let str = getline(middle)
    let str2 = getline(partition)
    call setline(middle, str2)
    call setline(partition, str)
  endif
  call s:SortR(a:start, partition - 1, a:cmp,a:direction)
  call s:SortR(partition + 1, a:end, a:cmp,a:direction)
endfunction

"---
" To Sort a range of lines, pass the range to Sort() along with the name of a
" function that will compare two lines.
"
function! s:Sort(cmp,direction) range
  call s:SortR(a:firstline, a:lastline, a:cmp, a:direction)
endfunction

"---
" Reverse the current sort order
"
function! s:SortReverse()
  if exists("b:sortdirection") && b:sortdirection == -1
    let b:sortdirection = 1
    let b:sortdirlabel  = ""
  else
    let b:sortdirection = -1
    let b:sortdirlabel  = "reverse "
  endif
  let   b:sortby=b:sortdirlabel . b:sorttype
  call s:SortIndex("")
endfunction

"---
" Toggle through the different sort orders
"
function! s:SortSelect()
  " Select the next sort option
  if !exists("b:sorttype")
    let b:sorttype="date"
  elseif b:sorttype == "date"
    let b:sorttype="from"
  elseif b:sorttype == "from"
    let b:sorttype="subject"
  else
    let b:sorttype="date"
  endif
  let b:sortby=b:sortdirlabel . b:sorttype
  call s:SortIndex("")
endfunction

"---
" Sort the file listing
"
function! s:SortIndex(msg)
    " Save the line we start on so we can go back there when done
    " sorting
    let startline = getline(".")
    let col=col(".")
    let lin=line(".")

    " Allow modification
    setlocal modifiable

    " Do the sort
    0
    if b:sorttype == "subject"
      /^"=/+1,$call s:Sort("s:SubjectCmp",b:sortdirection)
    elseif b:sorttype == "from"
      /^"=/+1,$call s:Sort("s:FromCmp",b:sortdirection)
    else
      /^"=/+1,$call s:Sort("s:DateCmp",b:sortdirection)
    endif

    " Return to the position we started on
    0
    if search('\m^'.escape(startline,s:escregexp),'W') <= 0
      execute lin
    endif
    execute "normal!" col . "|"

    " Disallow modification
    setlocal nomodifiable

endfunction


"--
" Set up the Mail Command
"
command! -n=? -complete=dir Mail :call s:BrowseEmail(0,'<args>')
command! -n=? -complete=dir SMail :call s:BrowseEmail(1,'<args>')


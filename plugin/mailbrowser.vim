" File: mailbrowser.vim
" Author: Mark Waggoner (mark@wagnell.com)
" Last Change: 2001 Aug 21
" Version: 1.4
"-----------------------------------------------------------------------------

let s:mailbrowserHelp = "*mailbrowser.txt*	How to use the mailbrowser plugin
\\n
\\n This plugin allows one to view a mail collection similar to the way one
\\n would view it in a mailer.
\\n
\\n Normally, this file will reside in the plugins directory and be
\\n automatically sourced.  If not, you must manually source this file
\\n using :source mailbrowser.vim
\\n
\\n :Mail <filename>
\\n   will bring up an index of the mail contained in the specified file
\\n :Mail
\\n   will bring up an index of the mail contained in the file specified by the
\\n   $MAIL environment variable
\\n :SMail
\\n   will open a new window and then do what :Mail would have done
\\n
\\n
\\n Keys defined in mail browser index
\\n    s = select what to sort by
\\n    r = reverse the current sort order
\\n    o = open the mail under the cursor in a separate window
\\n        <doubleclick> will do the same as o
\\n <cr> = open the mail under the cursor in the current window
\\n    u = update the index
\\n    d = mark for deletion (doesn't really work)
\\n
\\n
\\n When viewing a mail message:
\\n    i = return to index
\\n    a = toggle viewing all headers
\\n    J = go to next message down in the index
\\n    K = go to next message up in the index
\\n
\\n
\\n Globals of use:
\\n   g:mailbrowserSortBy 
\\n       selects the default sort. Choices are 'subject', 'index', or 'from'
\\n       with the optional addition of 'reverse'
\\n       Example (and default):
\\n           let g:mailbrowserSortBy='reverse subject'
\\n
\\n   g:mailbrowserMailPath
\\n       Chose the directory to look in for named mail files
\\n       Example (and default):
\\n           let g:mailbrowserMailPath = $HOME . \"/Mail\"
\\n
\\n   g:mailbrowserFromLength
\\n       Chose how many characters of the \"from\" address to display
\\n       Example (and default):
\\n           let g:mailbrowserFromLength = 25
\\n
\\n   g:mailbrowserShowHeaders
\\n       Choose which mail headers will be displayed as part of the message.
\\n       If this is not empty, then headers that do not match this will not be
\\n       displayed.
\\n       Example (and default):
\\n           let g:mailbrowserShowHeaders = '^\(Subject:\|Date:\|From:\|To:\|Cc:\)'
\\n
\\n   g:mailbrowserHideHeaders
\\n       Choose which mail headers will NOT be displayed as part of the
\\n       message.  If this is not empty, then headers that match this will not
\\n       be displayed.
\\n       Example (and default):
\\n           let g:mailbrowserHideHeaders = \"\"
\\n
\\n Changes in 1.3
\\n   Fixed bug in globbing of filenames
\\n   Auto-install help file when first run
\\n   Added J and K mappings in mail window
\\n
\"

"   
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

"---
" Check if help is installed and up-to-date
" If not, try to install it
"
let s:helpdir    = expand("<sfile>:p:h:h") . "/doc"
let s:helpfile   = s:helpdir . "/mailbrowser.txt"
let s:create_help = 0

" If help doesn't exist, see if the directory is writable
if expand(s:helpfile) == ""
    if filewritable(s:helpdir)
        let s:create_help = 1
    endif
else
" If help already exists, but is older than this script, see if the file is
" writable
    if (getftime(s:helpfile) < getftime(expand("<sfile>:p"))) && filewritable(s:helpfile)
        let s:create_help = 1
    endif
endif
" Recreate the help if needed
if s:create_help 
    exec 'silent new' s:helpfile
    silent %d
    let @" = s:mailbrowserHelp
    silent put
    silent 1d
    silent wq
    exec 'silent helptags' s:helpdir
    echomsg "mailbrowser help updated!"
endif

" Field to sort by
if !exists("g:mailbrowserSortBy")
  let g:mailbrowserSortBy='reverse index'
endif


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
  let g:mailbrowserShowHeaders = '^\(Subject:\|Date:\|From:\|To:\|Cc:\)'
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
" Four buffers are created:
"   The raw mail file
"   A buffer for the index
"   A buffer for displaying a single mail message
"   A buffer containing data about each mail message so we can quickly access them
"
" These three variables are set in each of the three buffers to point to the
" other buffers:
"   b:mailfile
"   b:mailindex
"   b:mailview
"   b:maildata
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
    let globfiles = globpath(g:mailbrowserMailPath,filename)
    " Only take the first one found
    let globfile = substitute(globfiles,"\<NL>.*$",'','')
    " Can't find anything - then abort
    if !filereadable(globfile)
      echomsg 'File' filename 'does not exist!'
      return
    endif
    let filename = globfile
  endif

  " Get the name of the mail buffer
  let filename = fnamemodify(filename,":p")
  " Construct names for the scratch buffers that we will use
  let mailfile = filename
  let mailindex = fnamemodify(mailfile,":t") . "-index"
  let mailview  = fnamemodify(mailfile,":t") . "-message"
  let maildata  = fnamemodify(mailfile,":t") . "-data"

  " Figure out the sort order for the index
  if g:mailbrowserSortBy =~ '\v\creverse'
      let sortdirection = -1
      let sortdirlabel = "reverse "
  else
      let sortdirection = 1
      let sortdirlabel = ""
  endif
  if g:mailbrowserSortBy =~ '\v\csubject'
      let sorttype = "subject"
  elseif g:mailbrowserSortBy =~ '\v\cfrom'
      let sorttype = "from"
  else
      let sorttype = "index"
  endif
  let sortby=sortdirlabel . sorttype


  "----------------------------
  " Go to or create the index
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
  let b:mailfile  = mailfile
  let b:mailindex = mailindex
  let b:mailview  = mailview
  let b:maildata  = maildata
  let b:sortdirection = sortdirection
  let b:sorttype      = sorttype
  let b:sortby        = sortby
 
  " Set up keyboard commands for the index window
  nnoremap <silent> <buffer> <2-leftmouse>  :call <SID>OpenMail('new')<cr>
  nnoremap <silent> <buffer> o  :call <SID>OpenMail('new')<cr>
  nnoremap          <buffer> s  :call <SID>SortSelect()<cr>
  nnoremap <silent> <buffer> r  :call <SID>SortReverse()<cr>
  nnoremap <silent> <buffer> <cr> :call <SID>OpenMail('e')<cr>
  nnoremap <silent> <buffer> u  :call <SID>BuildIndex()<cr>
  nnoremap <silent> <buffer> d  :call <SID>DeleteMail()<cr>


  "----------------------------
  " Open the mail data file and make it unmodifiable to protect it
  exec "silent new" mailfile
  setlocal nomodifiable
  setlocal noswapfile
  setlocal bufhidden=hide
  setlocal nowrap
  setlocal autoread
  let b:mailfile  = mailfile
  let b:mailindex = mailindex
  let b:mailview  = mailview
  let b:maildata  = maildata
  hide

  "----------------------------
  " Create a buffer for viewing mail messages
  exec "silent new" mailview
  call s:SetScratchWindow()
  let b:mailfile  = mailfile
  let b:mailindex = mailindex
  let b:mailview  = mailview
  let b:maildata  = maildata
  let b:showheaders=g:mailbrowserShowHeaders
  let b:hideheaders=g:mailbrowserHideHeaders
  setlocal filetype=mail
  nnoremap <silent> <buffer> i  :call <SID>GotoWindow(b:mailindex,'e')<cr>
  nnoremap <silent> <buffer> a  :call <SID>ToggleHeaders()<cr>
  nnoremap <silent> <buffer> d  :call <SID>DeleteMail()<cr>
  nnoremap <silent> <buffer> J  :call <SID>NextMail("+1")<cr>
  nnoremap <silent> <buffer> K  :call <SID>NextMail("-1")<cr>
  hide

  "----------------------------
  " Create a buffer for holding mail data
  exec "silent new" maildata
  call s:SetScratchWindow()
  let b:mailfile  = mailfile
  let b:mailindex = mailindex
  let b:mailview  = mailview
  let b:maildata  = maildata
  let b:showheaders=g:mailbrowserShowHeaders
  let b:hideheaders=g:mailbrowserHideHeaders
  let b:sortdirection = sortdirection
  let b:sorttype      = sorttype
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
  " First extract all the data from the mail file
  call s:BuildData()
  call s:SortData(b:maxindex,1)
endfunction

"--
" Copy information from the data buffer into a more human readable index
"
function! s:DataToIndex(cursorindex,cursorcolumn)

  call s:GotoWindow(b:mailindex,'new')
  setlocal modifiable
  " Empty the window
  silent 1,$d
  " Add header
  let @" = "\"Mail from " . b:mailfile . " sorted by " . b:sortby . "\n\"="
  put

  " Go to the data window
  call s:GotoWindow(b:maildata,'new')

  " Prepare to right justify the index
  let indexlength = b:indexlength
  let spaces = "      "
  while strlen(spaces) < indexlength
      let spaces = spaces . "      "
  endwhile

  " Start at the beginning and find all the headers
  0
  while 1
      let l = getline(".")
      exec l
      let pad = strpart(spaces,0,indexlength - strlen(index))
      let @" = pad. index . " " . flag . " " . date . " " . from . " " . subject
      wincmd p
      $put
      " return to data
      wincmd p
      if line(".") == line("$")
          break
      endif
      +1
  endwhile
  " Hide the data window
  hide

  " Delete first empty line in index
  0d
  " Save the length of the count field
  let b:indexlength = indexlength

  " Protect it
  setlocal nomodifiable

  " Move cursor to selected item
  exec '/^\s*' . a:cursorindex . ' /'
  execute "normal!" a:cursorcolumn . "|"

  " syntax highlighting
  if hlexists("mailindexline")
    syn clear mailindexline
  endif
  if hlexists("mailindex")
    syn clear mailindex
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
  let s = 0
  let e = b:indexlength+2
  exec 'syn match mailindex   "\%>' . s . 'v\%<' . e . 'v." contained'
  let s = e - 1
  let e = s + 2 + 1
  exec 'syn match mailflag    "\%>' . s . 'v\%<' . e . 'v." contained'
  let s = e - 1
  let e = s + 16 + 1
  exec 'syn match maildate    "\%>' . s . 'v\%<' . e . 'v." contained'
  let s = e - 1
  let e = s + g:mailbrowserFromLength + 1
  exec 'syn match mailfrom    "\%>' . s . 'v\%<' . e . 'v." contained'
  let s = e - 1
  exec 'syn match mailsubject "\%>' . s . 'v." contained'
  hi link mailindex       Normal
  hi link mailflag        Constant
  hi link maildate        Identifier
  hi link mailfrom        Statement
  hi link mailsubject     Type

  " highlight the displayed message
  highlight clear DisplayedMessage
  highlight DisplayedMessage ctermfg=white ctermbg=darkred guibg=darkred  guifg=white term=bold cterm=bold
endfunction

"-- 
" Extract data about each mail from the mail file
"
function! s:BuildData()
  call s:GotoWindow(b:maildata,'new')
  setlocal modifiable
  " Empty the window
  silent 1,$d

  " Count number of messages
  let index = 0

  " Go to the email window
  call s:GotoWindow(b:mailfile,'new')

  " See if it needs to be reloaded
  silent checktime
  
  " Make a padding string to use in GetHeaders()
  let s:frompadding = "               "
  while strlen(s:frompadding) < g:mailbrowserFromLength
      let s:frompadding = s:frompadding . "               "
  endwhile


  " Flag whether we've finished or not
  let keepgoing = 1

  " Start at the beginning and find all the headers
  0
  while keepgoing
    " Get the line number of the first line of the message
    let start = line(".")
    " Get the contents of the first line
    let l = getline(".")
    " Is it a proper mail header?
    if l !~ '\C^From\s\+\(\S\+\)\s\+\(.*\)'
        let keepgoing = 0
        continue
    endif

    " Increase the count and initialize data
    let index = index + 1
    let from = substitute(l,'^From\s\+','','')
    let date = substitute(from,'\S\+\s\+','','')
    let from = substitute(from,'\(\S\+\).*','\1','')
    let date = strpart(date,0,11) . strpart(date,20,4)
    let subject = ''
    let flag = "N"

    " Try to find the headers we are interested in or blank line,
    " indicating end of headers
    while keepgoing && search('\v\C^((From\:)|(Subject\:)|(Status\:)|(\n))','W')
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
            else
                let flag=" "
            endif
            continue
        endif

        "Shouldn't get here!
        echoerr "Error Extracting Mail Headers"
        let keepgoing = 0
        continue

    endwhile

    " Search for the next message - or the end of the file
    if !search('\v\C^From ','W')
        $
    else
        -1
    endif

    " The line number of the last line of the mail message
    let end=line(".")

    " Shorten or lengthen the from to the selected length
    let from = strpart(from . s:frompadding,0,g:mailbrowserFromLength)

    " Make sure we have legal syntax for the vimscript lines we'll create
    let from = escape(from,'\"')
    let subject = escape(subject,'\"')

    " Create a vimscript line that we'll keep in the data buffer
    let @" = 'let index=' . index . 
    \        " | let start=" . start . 
    \        " | let headerend=" . headerend . 
    \        " | let end=" . end . 
    \        " | let flag='" . flag . "'" .
    \        " | let date='" . date . "'" .
    \        ' | let from="' . from . '"' . 
    \        ' | let subject="' . subject . '"'

    " Go to next message
    +1

    " go back to data
    wincmd p
    " Save data
    $put
    " return to file
    wincmd p
  endwhile

  " Hide the main file
  hide
  " Remove first (blank) line in data window
  silent 0d

  " NOT NEEDED
  " right justify message number
  let b:maxindex = index
  let b:indexlength = strlen(b:maxindex)

  " Protect it
  setlocal nomodifiable

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
  " Buffers should already exist when calling this function
  if !bufexists(a:name)
    echoerr "Couldn't find buffer for" a:name
    return
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
" Mark a mail item as "deleted"  does not actually delete anything
"
function! s:DeleteMail()
  " Are we in the index window?
  if bufname("%") == b:mailindex
    " Get the index number of the line we are on
    let index = strpart(getline("."),0,b:indexlength)
    let startcolumn = col(".")
  elseif bufname("%") == b:mailview
    " In this case, get the mail item number from the variable
    let index = b:index
    let startcolumn = 0
    " After marking it deleted, return to the index
  else
    echomsg "Can't figure out what to delete!\n"
    return 0
  endif

  " Change the flag to D in the data window
  call s:GotoWindow(b:maildata,'new')
  if !search('/\v^let index=' . index,'w')
    echoerr "Error locating mail data"
  else
    setlocal modifiable
    s/let flag='.\+'/let flag='D'/
    setlocal nomodifiable
  endif
  hide

  " Change the flag to D in the index window
  call s:GotoWindow(b:mailindex,'e')
  if !search('\v^\s\*' . index . '\s\+','w')
    echoerr "Can't find deleted item in index"
  else
    call s:UpdateCurrentIndexItem()
  endif

endfunction


function! s:UpdateCurrentIndexItem()


endfunction

"---
"
"
function! s:NextMail(offset)
   " Do we close the index when done?
  let windowswitch = "e"
  if bufwinnr(b:mailindex) >= 0
      let windowswitch = "new"
  endif
  call s:GotoWindow(b:mailindex,windowswitch)
  " Check if we're into the header
  if getline(line(".")+a:offset) !~ '^"'
    exec a:offset
  endif
  call s:OpenMail(windowswitch)
endfunction

"---
"
"
function! s:OpenMail(new)
    " Get the index number from the current line
    let l = getline(".")
    if (l =~ '^"') 
        return
    endif
    let index = substitute(strpart(l,0,b:indexlength),'\v^\s+','','')
    call s:GotoWindow(b:maildata,'new')
    exec "0/^let index=" . index
    exec getline(".")
    " hide maildata
    hide

    if hlexists("DisplayedMessage")
      syn clear DisplayedMessage
    endif

    " Not sure I like this
    "exec 'syn match DisplayedMessage ".\%' . line(".") . 'l"'

    call s:GetMailMsg(start,end,a:new)
    let b:index = index
endfunction

function! s:GetMailMsg(start,end,new)
    call s:GotoWindow(b:mailfile,'new')
    exec "silent " . a:start . "," a:end . "y a"
    call s:CloseWindow(b:mailfile)
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

    if (l =~ '\v^\s+')
        if b:deleted_previous
            silent delete
        endif
        return
    endif

    let b:deleted_previous = 0
    if (b:hideheaders != "") && (l =~ b:hideheaders)
        silent delete
        let b:deleted_previous = 1
    endif

    if (b:showheaders != "") && (l !~ b:showheaders)
        silent delete
        let b:deleted_previous = 1
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
" This isn't really right, but I don't have a way to convert string dates to
" numbers
function! s:DateCmp(line1,line2,direction)
    exec a:line1
    let date1=date
    exec a:line2
    return s:StrCmp(date1,date,a:direction)
endfunction

"---
" Compare From
"
function! s:FromCmp(line1,line2,direction)
    exec a:line1
    let from1=from
    let index1=index
    exec a:line2
    let c = s:StrCmp(from1,from,a:direction)
    if (c == 0)
        return index1 > index ? 1 : (index1 == index ? 0 : -1)
    else
        return c
    endif
endfunction

"---
" Compare Subject
"
function! s:SubjectCmp(line1,line2,direction)
    exec a:line1
    let subject1=substitute(subject,'\v\c^re: ','','g')
    let index1 = index
    exec a:line2
    let subject2=substitute(subject,'\v\c^re: ','','g')
    let c = s:StrCmp(subject1,subject2,a:direction)
    if (c == 0)
        return index1 > index ? 1 : (index1 == index ? 0 : -1)
    else
        return c
    endif
endfunction

"---
" Compare Index
"
function! s:IndexCmp(line1,line2,direction)
    exec a:line1
    let index1=index
    exec a:line2
    return index1 > index ? a:direction : (index1 == index ? 0 : -a:direction)
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
  call s:SortIndex()
endfunction

"---
" Toggle through the different sort orders
"
function! s:SortSelect()
  echon "Sort by (r)everse (i)ndex, (f)rom, (s)ubject:  "
  let b:sortdirection = 1
  let b:sortdirlabel = ""
  while 1
    let c = nr2char(getchar())
    if c == "r"
        let b:sortdirection = -1
        let b:sortdirlabel = "reverse"
        echon "reverse "
    elseif c == "f"
        let b:sorttype = "from"
        break
    elseif c == "i"
        let b:sorttype = "index"
        break
    elseif c == "s"
        let b:sorttype = "subject"
        break
    endif
  endwhile
  let b:sortby=b:sortdirlabel . b:sorttype
  echon b:sorttype
  call s:SortIndex()
endfunction

"---
" Sort the file listing
"
function! s:SortIndex()

    " Get the index of the message we are on so we can go back there when done
    " sorting.
    let l = getline(".")
    if l =~ '^"'
        silent /^[^"]/
        let l = getline(".")
    endif
    let startindex = substitute(l,'\v(\s*\S+).*','\1','')
    let startcolumn=col(".")

    let sorttype = b:sorttype
    let sortdirection = b:sortdirection

    " Sort the data, then regenerate the index from that
    call s:GotoWindow(b:maildata,'new')

    let b:sorttype = sorttype
    let b:sortdirection = sortdirection

    call s:SortData(startindex,startcolumn)
endfunction

function! s:SortData(startindex,startcolumn)
    " Allow modification
    setlocal modifiable

    " Do the sort
    if b:sorttype == "subject"
      1,$call s:Sort("s:SubjectCmp",b:sortdirection)
    elseif b:sorttype == "from"
      1,$call s:Sort("s:FromCmp",b:sortdirection)
    elseif b:sorttype == "date"
      1,$call s:Sort("s:DateCmp",b:sortdirection)
    elseif b:sorttype == "index"
      1,$call s:Sort("s:IndexCmp",b:sortdirection)
    else
      1,$call s:Sort("s:IndexCmp",b:sortdirection)
    endif

    " Disallow modification
    setlocal nomodifiable

    call s:DataToIndex(a:startindex,a:startcolumn)
endfunction


"--
" Set up the Mail Command
"
command! -n=? -complete=dir Mail :call s:BrowseEmail(0,'<args>')
command! -n=? -complete=dir SMail :call s:BrowseEmail(1,'<args>')


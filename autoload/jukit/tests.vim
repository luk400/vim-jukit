" FUNCTIONS WITH MAPPINGS TO TEST:
" [X] jukit#layouts#set_layout()
" [X] jukit#send#line()
" [X] jukit#send#selection()
" [X] jukit#send#section(0)
" [X] jukit#send#until_current_section()
" [X] jukit#send#all()
" [X] jukit#cells#delete()
" [X] jukit#cells#split()
" [X] jukit#cells#create_below(0)
" [X] jukit#cells#create_above(0)
" [X] jukit#cells#create_below(1)
" [X] jukit#cells#create_above(1)
" [X] jukit#cells#merge_above()
" [X] jukit#cells#merge_below()
" [X] jukit#cells#move_up()
" [X] jukit#cells#move_down()
" [X] jukit#cells#jump_to_next_cell()
" [X] jukit#cells#jump_to_previous_cell()
" [X] jukit#splits#output()
" [X] jukit#splits#term()
" [X] jukit#splits#history()
" [X] jukit#splits#output_and_history()
" [X] jukit#splits#close_history()
" [X] jukit#splits#close_output_split()
" [X] jukit#splits#close_output_and_history(1)
" [X] jukit#splits#out_hist_scroll(1)
" [X] jukit#splits#out_hist_scroll(0)
" [X] jukit#splits#show_last_cell_output(1)
" [X] jukit#splits#toggle_auto_hist()
" [X] jukit#cells#delete_outputs(0)
" [X] jukit#cells#delete_outputs(1)
" [X] jukit#convert#notebook_convert("jupyter-notebook")
" [X] jukit#convert#save_nb_to_file(0,1,'html')
" [-] jukit#convert#save_nb_to_file(0,1,'pdf')
" [-] jukit#convert#save_nb_to_file(1,1,'html')
" [-] jukit#convert#save_nb_to_file(1,1,'pdf')
" [-] jukit#ueberzug#set_default_pos()


let s:test_dir = jukit#util#plugin_path() . '/tests'
let s:json_file = s:test_dir . "/jukit_tests_summary.json"

if !isdirectory(s:test_dir)
  call mkdir(s:test_dir)
endif


fun! jukit#tests#create_test_script(vim_cmd) abort
    let lines = []
    for key_val in items(s:all_tests)
        call add(lines, "rm -f " . s:test_dir . "/.test.py && " . a:vim_cmd . " " . s:test_dir
            \. "/.test.py -c \"call jukit#tests#run_test('" . key_val[0] . "', 1)\"")
    endfor

    let file = s:test_dir . "/jukit_tests.sh"
    call writefile(lines, file)
    qa!
endfun


fun! jukit#tests#run_test(test_name, quit) abort
    try
        if !(index(keys(s:all_tests), a:test_name) >= 0)
            throw printf('Test %s not found - available tests: ' . join(keys(s:all_tests)), a:test_name)
        endif

        let result = s:all_tests[a:test_name]()
        call s:write_to_testjson(a:test_name, [result[0], result[1]])
    catch
        echohl ErrorMsg
        echomsg v:exception
        echohl None

        call s:write_to_testjson(a:test_name, [0, v:exception])
    endtry

    if a:quit
        qa!
    endif
endfun


fun! s:delete_if_exists(file) abort
    if filereadable(a:file)
        call delete(a:file)
    endif
endfun


fun! s:write_to_testjson(key, val) abort
    " create s:json_file if it doesn't exist
    if !filereadable(s:json_file)
        call writefile([json_encode({})], s:json_file)
    endif

    " load json
    let j = json_decode(join(readfile(s:json_file)))

    " set value
    let j[a:key] = a:val

    " write json
    call writefile([json_encode(j)], s:json_file)
endfun


fun! s:create_above() abort
    " first create code cell above and check if there's a marker below in the
    " expected position
    call jukit#cells#create_above(0)
    let code_cell_passed = (stridx(getline(4), '|%%--%%|') >= 0)

    " clear file content
    normal! ggdG

    " create markdown cell above and check if there's a marker below in the
    " expected position as well as md-symbols above and below
    call jukit#cells#create_above(1)
    let marker_as_expected = stridx(getline(4), '|%%--%%|') >= 0
    let md_symbol_above = stridx(getline(1), '°°°') >= 0
    let md_symbol_below = stridx(getline(3), '°°°') >= 0
    let md_cell_passed = marker_as_expected && md_symbol_above && md_symbol_below

    let test_passed = code_cell_passed && md_cell_passed
    let fail_info = "code_cell_passed: " . code_cell_passed . ", md_cell_passed: "
        \. md_cell_passed

    return [test_passed, fail_info]
endfun


fun! s:create_below() abort
    " first create code cell below and check if there's a marker below in the
    " expected position
    call jukit#cells#create_below(0)
    let code_cell_passed = (stridx(getline(2), '|%%--%%|') >= 0)

    " clear file content
    normal! ggdG

    " create markdown cell below and check if there's a marker below in the
    " expected position as well as md-symbols above and below
    call jukit#cells#create_below(1)
    let marker_as_expected = stridx(getline(2), '|%%--%%|') >= 0
    let md_symbol_above = stridx(getline(3), '°°°') >= 0
    let md_symbol_below = stridx(getline(5), '°°°') >= 0
    let md_cell_passed = marker_as_expected && md_symbol_above && md_symbol_below

    let test_passed = code_cell_passed && md_cell_passed
    let fail_info = "code_cell_passed: " . code_cell_passed . ", md_cell_passed: "
        \. md_cell_passed

    return [test_passed, fail_info]
endfun


fun! s:merge_above() abort
    call jukit#cells#create_below(0)
    call jukit#cells#merge_above()

    " no cell marker should be present anymore after merge
    let code_cells_merged = stridx(join(getline(1, '$')), '|%%--%%|') == -1

    " clear file content
    normal! ggdG

    call jukit#cells#create_above(1)
    call jukit#cells#create_below(1)
    call jukit#cells#merge_above()
    " a single marker should now be present in line 5
    let marker_as_expected = stridx(getline(5), '|%%--%%|') >= 0

    let test_passed = code_cells_merged && marker_as_expected
    let fail_info = "code_cells_merged: " . code_cells_merged . ", marker_as_expected: "
        \. marker_as_expected

    return [test_passed, fail_info]
endfun


fun! s:merge_below() abort
    call jukit#cells#create_above(0)
    call jukit#cells#merge_below()

    " no cell marker should be present anymore after merge
    let code_cells_merged = stridx(join(getline(1, '$')), '|%%--%%|') == -1

    " clear file content
    normal! ggdG

    call jukit#cells#create_below(1)
    call jukit#cells#create_above(1)
    call jukit#cells#merge_below()
    " the marker on line 6 should now not be present anymore
    let marker_as_expected = stridx(getline(6), '|%%--%%|') == -1

    let test_passed = code_cells_merged && marker_as_expected
    let fail_info = "code_cells_merged: " . code_cells_merged . ", marker_as_expected: "
        \. marker_as_expected

    return [test_passed, fail_info]
endfun


fun! s:move_up() abort
    call jukit#cells#create_below(0)
    call jukit#cells#move_up()

    " marker should now be on line 4
    let test_passed = stridx(getline(4), '|%%--%%|') >= 0
    let fail_info = getline(4)

    return [test_passed, fail_info]
endfun


fun! s:move_down() abort
    call jukit#cells#create_above(0)
    call jukit#cells#move_down()

    " marker should now be on line 2
    let test_passed = stridx(getline(2), '|%%--%%|') >= 0
    let fail_info = getline(2)

    return [test_passed, fail_info]
endfun


fun! s:jump_to_next_cell() abort
    call jukit#cells#create_below(0)
    normal! gg
    call jukit#cells#jump_to_next_cell()

    " cursor should now be on line 3
    let test_passed = line('.') == 3
    let fail_info = line('.')

    return [test_passed, fail_info]
endfun


fun! s:jump_to_previous_cell() abort
    call jukit#cells#create_below(0)
    call jukit#cells#jump_to_previous_cell()

    " cursor should now be on line 1
    let test_passed = line('.') == 1
    let fail_info = line('.')

    return [test_passed, fail_info]
endfun


fun! s:line_to_output() abort
    call s:delete_if_exists(s:test_dir . '/output_success')

    call setline('.', "import os; os.close(os.open('" . s:test_dir . "/output_success', os.O_CREAT))")
    call jukit#splits#output()

    sleep 5
    call jukit#send#line()
    sleep 1

    let test_passed = filereadable(s:test_dir . '/output_success')
    let fail_info = system("ls -lahtr " . s:test_dir)

    return [test_passed, fail_info]
endfun


fun! s:section_to_output() abort
    call s:delete_if_exists(s:test_dir . '/output_success')

    call jukit#cells#create_below(0)
    call setline('.', "import os; os.close(os.open('" . s:test_dir . "/output_success', os.O_CREAT))")
    call jukit#splits#output()

    sleep 5
    call jukit#send#section(0)
    sleep 1

    let test_passed = filereadable(s:test_dir . '/output_success')
    let fail_info = system("ls -lahtr " . s:test_dir)

    return [test_passed, fail_info]
endfun


fun! s:all_to_output() abort
    call s:delete_if_exists(s:test_dir . '/output_success1')
    call s:delete_if_exists(s:test_dir . '/output_success2')

    call jukit#cells#create_below(0)
    call setline('.', "import os; os.close(os.open('" . s:test_dir . "/output_success1', os.O_CREAT))")
    call jukit#cells#create_below(0)
    call setline('.', "import os; os.close(os.open('" . s:test_dir . "/output_success2', os.O_CREAT))")
    call jukit#splits#output()

    sleep 5
    call jukit#send#all()
    sleep 1

    let first_file_exists = filereadable(s:test_dir . '/output_success1')
    let second_file_exists = filereadable(s:test_dir . '/output_success2')

    let test_passed = first_file_exists && second_file_exists
    let fail_info = "first_section_sent: " . first_file_exists
        \. ", second_section_sent: " . second_file_exists

    return [test_passed, fail_info]
endfun


fun! s:until_current_to_output() abort
    call s:delete_if_exists(s:test_dir . '/output_success1')
    call s:delete_if_exists(s:test_dir . '/output_success2')
    call s:delete_if_exists(s:test_dir . '/output_success3')

    call jukit#cells#create_below(0)
    call setline('.', "import os; os.close(os.open('" . s:test_dir . "/output_success1', os.O_CREAT))")
    call jukit#cells#create_below(0)
    call setline('.', "import os; os.close(os.open('" . s:test_dir . "/output_success2', os.O_CREAT))")
    call jukit#cells#create_below(0)
    call setline('.', "import os; os.close(os.open('" . s:test_dir . "/output_success3', os.O_CREAT))")
    call jukit#cells#jump_to_previous_cell()
    call jukit#splits#output()

    sleep 5
    call jukit#send#until_current_section()
    sleep 1

    let first_file_exists = filereadable(s:test_dir . '/output_success1')
    let second_file_exists = filereadable(s:test_dir . '/output_success2')
    let third_file_exists = filereadable(s:test_dir . '/output_success3')

    let test_passed = first_file_exists && second_file_exists && !third_file_exists
    let fail_info = "first_section_sent: " . first_file_exists
        \. ", second_section_sent: " . second_file_exists
        \. ", third_section_sent: " . third_file_exists

    return [test_passed, fail_info]
endfun


fun! s:selection_to_output() abort
    call s:delete_if_exists(s:test_dir . '/output_success')

    call setline('.', "SKIP_THIS import os; os.close(os.open('" . s:test_dir . "/output_success', os.O_CREAT)) AND SKIP THIS")
    call jukit#splits#output()

    sleep 5
    call feedkeys("fivf)l:\<c-u>call jukit#send#selection()\<cr>", "xni")
    sleep 1

    let test_passed = filereadable(s:test_dir . '/output_success')
    let fail_info = system("ls -lahtr " . s:test_dir)

    return [test_passed, fail_info]
endfun


fun! s:delete_cell() abort
    call jukit#cells#create_below(0)
    call jukit#cells#delete()

    " no cell marker should be present anymore after deletion
    let code_cell_deleted = stridx(join(getline(1, '$')), '|%%--%%|') == -1

    let test_passed = code_cell_deleted
    let fail_info = join(getline(1, '$'), "\n")

    return [test_passed, fail_info]
endfun


fun! s:split_cell() abort
    call jukit#cells#split()

    " cell marker should now be in line 1
    let cell_marker_present = stridx(getline(1), '|%%--%%|') != -1

    let test_passed = cell_marker_present
    let fail_info = getline(1)

    return [test_passed, fail_info]
endfun


fun! s:set_layout() abort
    " unsure how to test this, but at least it should not throw an error

    call jukit#splits#output_and_history()
    call jukit#layouts#set_layout()

    let test_passed = 1
    let fail_info = ""

    return [test_passed, fail_info]
endfun


fun! s:output_split() abort
    call s:delete_if_exists(s:test_dir . '/output_success')

    call jukit#splits#output()

    sleep 5
    call jukit#send#send_to_split("import os; os.close(os.open('" . s:test_dir . "/output_success', os.O_CREAT))")
    sleep 1

    let test_passed = filereadable(s:test_dir . '/output_success')
    let fail_info = system("ls -lahtr " . s:test_dir)

    return [test_passed, fail_info]
endfun


fun! s:term_split() abort
    call s:delete_if_exists(s:test_dir . '/output_success')

    call jukit#splits#term()

    sleep 5
    call jukit#send#send_to_split("touch " . s:test_dir . "/output_success")
    sleep 1

    let test_passed = filereadable(s:test_dir . '/output_success')
    let fail_info = system("ls -lahtr " . s:test_dir)

    return [test_passed, fail_info]
endfun


fun! s:history_split() abort
    " unsure how to test this, but at least it should not throw an error

    call jukit#splits#history()

    let test_passed = 1
    let fail_info = ""

    return [test_passed, fail_info]
endfun


fun! s:output_and_history_split() abort
    call s:delete_if_exists(s:test_dir . '/output_success')

    call jukit#splits#output_and_history()

    sleep 5
    call jukit#send#send_to_split("import os; os.close(os.open('" . s:test_dir . "/output_success', os.O_CREAT))")
    sleep 1

    let test_passed = filereadable(s:test_dir . '/output_success')

    let test_passed = 1
    let fail_info = system("ls -lahtr " . s:test_dir)

    return [test_passed, fail_info]
endfun


fun! s:close_history_split() abort
    call jukit#splits#history()
    sleep 250m
    call jukit#splits#close_history()
    sleep 250m

    let test_passed = !jukit#splits#split_exists('outhist')
    let fail_info = ""

    return [test_passed, fail_info]
endfun


fun! s:close_output_split() abort
    call jukit#splits#output()
    sleep 250m
    call jukit#splits#close_output_split()
    sleep 250m

    let test_passed = !jukit#splits#split_exists('output')
    let fail_info = ""

    return [test_passed, fail_info]
endfun


fun! s:close_output_and_history_split() abort
    call jukit#splits#output_and_history()
    sleep 250m
    call jukit#splits#close_output_and_history(0)
    sleep 250m

    let output_closed = !jukit#splits#split_exists('output')
    let history_closed = !jukit#splits#split_exists('outhist')

    let test_passed = output_closed && history_closed
    let fail_info = "output_closed: " . output_closed . ", history_closed: " . history_closed

    return [test_passed, fail_info]
endfun


fun! s:outhist_scroll() abort
    " unsure how to test this, but at least it should not throw an error

    call jukit#splits#history()
    call jukit#splits#out_hist_scroll(0)
    call jukit#splits#out_hist_scroll(1)

    let test_passed = 1
    let fail_info = ""

    return [test_passed, fail_info]
endfun


fun! s:show_last_cell_output() abort
    " unsure how to test this, but at least it should not throw an error

    call jukit#splits#history()
    call jukit#splits#show_last_cell_output(1)

    let test_passed = 1
    let fail_info = ""

    return [test_passed, fail_info]
endfun


fun! s:toggle_auto_hist() abort
    " unsure how to test this, but at least it should not throw an error

    call jukit#splits#toggle_auto_hist()

    let test_passed = 1
    let fail_info = ""

    return [test_passed, fail_info]
endfun


fun! s:save_output() abort
    call s:delete_if_exists(s:test_dir . '/.jukit/.test_outhist.json')

    call setline('.', "1+1")
    call jukit#splits#output()

    sleep 5
    call jukit#send#section(0)
    sleep 1

    let outhist = json_decode(join(readfile(s:test_dir . '/.jukit/.test_outhist.json')))

    let test_passed = outhist['NONE'][1]["data"]["text/plain"] == "2"
    let fail_info = json_encode(outhist)

    return [test_passed, fail_info]
endfun


fun! s:delete_saved_output() abort
    call s:delete_if_exists(s:test_dir . '/.jukit/.test_outhist.json')

    call setline('.', "1+1")
    call jukit#splits#output()

    sleep 5
    call jukit#send#section(0)
    sleep 1

    call jukit#cells#delete_outputs(0)

    let outhist = json_decode(join(readfile(s:test_dir . '/.jukit/.test_outhist.json')))

    let test_passed = outhist == {}
    let fail_info = json_encode(outhist)

    return [test_passed, fail_info]
endfun


fun! s:delete_all_saved_outputs() abort
    call s:delete_if_exists(s:test_dir . '/.jukit/.test_outhist.json')

    call jukit#cells#create_below(0)
    call setline('.', "1+1")
    call jukit#cells#create_below(0)
    call setline('.', "1+1")
    call jukit#splits#output()

    sleep 5
    call jukit#send#all()
    sleep 1

    call jukit#cells#delete_outputs(1)

    let outhist = json_decode(join(readfile(s:test_dir . '/.jukit/.test_outhist.json')))

    let test_passed = outhist == {}
    let fail_info = json_encode(outhist)

    return [test_passed, fail_info]
endfun


fun! s:notebook_convert() abort
    call s:delete_if_exists(s:test_dir . '/.test.ipynb')

    call jukit#convert#notebook_convert()
    let ipynb = json_decode(join(readfile(s:test_dir . '/.test.ipynb')))

    let has_cells_key = has_key(ipynb, 'cells')
    let has_metadata_key = has_key(ipynb, 'metadata')
    let has_nbformat_key = has_key(ipynb, 'nbformat')

    let test_passed = has_cells_key && has_metadata_key && has_nbformat_key
    let fail_info = "has_cells_key: " . has_cells_key . ", has_metadata_key: "
        \. has_metadata_key . ", has_nbformat_key: " . has_nbformat_key

    return [test_passed, fail_info]
endfun


fun! s:save_nb_to_file() abort
    call s:delete_if_exists(s:test_dir . '/.test.html')

    call jukit#convert#save_nb_to_file(0,0,'html')
    sleep 5

    let test_passed = filereadable(s:test_dir . '/.test.html')
    let fail_info = system('ls -lahtr ' . s:test_dir)

    return [test_passed, fail_info]
endfun


let s:all_tests = {
    \ 'create_above': function('s:create_above'),
    \ 'create_below': function('s:create_below'),
    \ 'merge_above': function('s:merge_above'),
    \ 'merge_below': function('s:merge_below'),
    \ 'move_down': function('s:move_down'),
    \ 'move_up': function('s:move_up'),
    \ 'jump_to_next_cell': function('s:jump_to_next_cell'),
    \ 'jump_to_previous_cell': function('s:jump_to_previous_cell'),
    \ 'line_to_output': function('s:line_to_output'),
    \ 'section_to_output': function('s:section_to_output'),
    \ 'all_to_output': function('s:all_to_output'),
    \ 'until_current_to_output': function('s:until_current_to_output'),
    \ 'selection_to_output': function('s:selection_to_output'),
    \ 'delete_cell': function('s:delete_cell'),
    \ 'split_cell': function('s:split_cell'),
    \ 'set_layout': function('s:set_layout'),
    \ 'output_split': function('s:output_split'),
    \ 'term_split': function('s:term_split'),
    \ 'history_split': function('s:history_split'),
    \ 'output_and_history_split': function('s:output_and_history_split'),
    \ 'close_history_split': function('s:close_history_split'),
    \ 'close_output_split': function('s:close_output_split'),
    \ 'close_output_and_history_split': function('s:close_output_and_history_split'),
    \ 'outhist_scroll': function('s:outhist_scroll'),
    \ 'show_last_cell_output': function('s:show_last_cell_output'),
    \ 'toggle_auto_hist': function('s:toggle_auto_hist'),
    \ 'save_output': function('s:save_output'),
    \ 'delete_saved_output': function('s:delete_saved_output'),
    \ 'delete_all_saved_outputs': function('s:delete_all_saved_outputs'),
    \ 'notebook_convert': function('s:notebook_convert'),
    \ 'save_nb_to_file': function('s:save_nb_to_file'),
\ }

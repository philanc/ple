--std             = "ngx_lua+busted"
unused_args     = false
redefined       = false
max_line_length = false


globals = {
    "editor",
}


not_globals = {
    "string.len",
    "table.getn",
}


ignore = {
}


exclude_files = {
    ".install",
    ".luarocks",
}

